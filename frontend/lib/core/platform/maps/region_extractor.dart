import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';

import 'pmtiles_writer.dart';

/// Lets the caller stop an extraction between two network requests.
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const ExtractCancelled();
  }
}

class ExtractCancelled implements Exception {
  const ExtractCancelled();

  @override
  String toString() => 'Download cancelled';
}

class ExtractResult {
  const ExtractResult({
    required this.tiles,
    required this.tileBytes,
    required this.fileBytes,
  });

  final int tiles;
  final int tileBytes;
  final int fileBytes;
}

/// Copies the part of a big PMTiles archive that covers a box into a small one:
/// what `pmtiles extract` does, on the phone.
///
/// The source is read with range requests, so only the directory pages and the
/// wanted tiles cross the network - a city out of the 138 GB planet build costs
/// a few tens of megabytes. Steps:
///
/// 1. list the tile ids the box needs, per zoom;
/// 2. look each one up in the source's directories (this gives every tile's
///    length before any tile is fetched);
/// 3. from those lengths lay out the new archive and write its head;
/// 4. fetch the tile bytes in a few large ranges (neighbouring tiles are close
///    together in a clustered archive) and write them behind the head.
class RegionExtractor {
  RegionExtractor({
    required this.source,
    required this.reader,
    this.maxGapBytes = 64 * 1024,
    this.maxChunkBytes = 4 * 1024 * 1024,
    this.concurrency = 4,
    this.attempts = 3,
    this.retryDelay = const Duration(milliseconds: 400),
  });

  /// The archive to cut from, already opened.
  final PmTilesArchive source;

  /// A reader over the same bytes [source] was opened with.
  final ReadAt reader;

  /// Two wanted tiles closer than this share one request (the bytes between
  /// them are fetched and discarded).
  final int maxGapBytes;

  /// A single request never asks for more than this (unless one tile is bigger).
  final int maxChunkBytes;

  /// Requests in flight at once.
  final int concurrency;

  /// Tries per request before giving up.
  final int attempts;
  final Duration retryDelay;

  Future<ExtractResult> extract({
    required File output,
    required double west,
    required double south,
    required double east,
    required double north,
    required int minZoom,
    required int maxZoom,
    Map<String, Object?> extraMetadata = const {},
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    // -- 1 + 2: which tiles exist, and how long is each -----------------------
    final ids = _tileIds(west, south, east, north, minZoom, maxZoom);
    final found = <_Wanted>[];
    for (var i = 0; i < ids.length; i++) {
      cancel?.throwIfCancelled();
      final entry = await _withRetry(() => source.lookup(ids[i]));
      if (entry != null && !entry.isLeaf && entry.length > 0) {
        found.add(_Wanted(ids[i], entry.offset, entry.length));
      }
      if (i % 64 == 0) {
        onProgress?.call(_lookupShare * i / ids.length);
        await Future<void>.delayed(Duration.zero); // let the UI breathe
      }
    }
    if (found.isEmpty) {
      throw StateError('There is no map data in this area.');
    }

    // -- 3: lay out the new archive -------------------------------------------
    var outOffset = 0;
    final entries = <PmTileEntry>[];
    for (final w in found) {
      w.outOffset = outOffset;
      entries.add(PmTileEntry(
        tileId: w.tileId,
        offset: outOffset,
        length: w.length,
      ));
      outOffset += w.length;
    }
    final sourceMetadata = await _withRetry(() => source.metadata);
    final head = PmTilesWriter.head(
      entries: entries,
      metadata: {
        if (sourceMetadata is Map<String, dynamic>) ...sourceMetadata,
        ...extraMetadata,
      },
      west: west,
      south: south,
      east: east,
      north: north,
      minZoom: minZoom,
      maxZoom: math.min(maxZoom, source.header.maxZoom),
      tileCompression: _compressionCode(source.header.tileCompression),
    );

    // -- 4: fetch and write ---------------------------------------------------
    final out = await openArchiveForWriting(output, head);
    try {
      final groups = _group(found);
      var written = 0;
      for (var i = 0; i < groups.length; i += concurrency) {
        cancel?.throwIfCancelled();
        final window = groups.sublist(i, math.min(i + concurrency, groups.length));
        final fetched = [
          for (final g in window)
            _fetch(source.header.tileDataOffset + g.start, g.end - g.start),
        ];
        for (var k = 0; k < window.length; k++) {
          cancel?.throwIfCancelled();
          final bytes = await fetched[k];
          for (final w in window[k].tiles) {
            final from = w.srcOffset - window[k].start;
            await out.setPosition(head.tileDataOffset + w.outOffset);
            await out.writeFrom(bytes, from, from + w.length);
            written += w.length;
          }
          onProgress?.call(
            _lookupShare +
                (0.99 - _lookupShare) * written / math.max(1, outOffset),
          );
        }
      }
      await out.flush();
    } finally {
      await out.close();
    }
    onProgress?.call(1);
    return ExtractResult(
      tiles: found.length,
      tileBytes: outOffset,
      fileBytes: head.fileLength,
    );
  }

  /// Share of the progress bar spent finding tiles; the rest is downloading.
  static const double _lookupShare = 0.08;

  List<int> _tileIds(
    double west,
    double south,
    double east,
    double north,
    int minZoom,
    int maxZoom,
  ) {
    final ids = <int>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final (x0, y0, x1, y1) = TileMath.range(
        west: west,
        south: south,
        east: east,
        north: north,
        zoom: z,
      );
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          ids.add(ZXY(z, x, y).toTileId());
        }
      }
    }
    return ids..sort();
  }

  /// Wanted tiles in source order, merged into requests.
  List<_Group> _group(List<_Wanted> found) {
    final bySource = [...found]..sort((a, b) => a.srcOffset - b.srcOffset);
    final groups = <_Group>[];
    _Group? current;
    for (final w in bySource) {
      final c = current;
      if (c != null &&
          w.srcOffset - c.end <= maxGapBytes &&
          w.srcOffset + w.length - c.start <= maxChunkBytes) {
        c.tiles.add(w);
        c.end = math.max(c.end, w.srcOffset + w.length);
      } else {
        current = _Group(w.srcOffset, w.srcOffset + w.length)..tiles.add(w);
        groups.add(current);
      }
    }
    return groups;
  }

  Future<Uint8List> _fetch(int start, int length) => _withRetry(() async {
        final bytes = await (await reader.readAt(start, length)).toBytes();
        if (bytes.length != length) {
          throw StateError('Short read: ${bytes.length} of $length bytes.');
        }
        return bytes;
      });

  /// Runs a network operation, trying again after a short, growing pause when it
  /// fails: a phone on a moving connection drops requests all the time. A
  /// cancellation is never retried.
  Future<T> _withRetry<T>(Future<T> Function() operation) async {
    Object? error;
    StackTrace? stack;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await operation();
      } on ExtractCancelled {
        rethrow;
      } catch (e, s) {
        error = e;
        stack = s;
        if (attempt < attempts) {
          await Future<void>.delayed(retryDelay * attempt);
        }
      }
    }
    Error.throwWithStackTrace(error!, stack!);
  }

  static int _compressionCode(Compression c) => switch (c) {
        Compression.none => 1,
        Compression.gzip => 2,
        Compression.brotli => 3,
        Compression.zstd => 4,
        _ => 0,
      };
}

class _Wanted {
  _Wanted(this.tileId, this.srcOffset, this.length);

  final int tileId;
  final int srcOffset;
  final int length;
  int outOffset = 0;
}

class _Group {
  _Group(this.start, this.end);

  final int start;
  int end;
  final List<_Wanted> tiles = [];
}
