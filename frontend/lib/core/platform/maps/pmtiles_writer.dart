import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// One tile's place in an archive that is being written.
class PmTileEntry {
  const PmTileEntry({
    required this.tileId,
    required this.offset,
    required this.length,
  });

  /// Hilbert-curve tile id (see `ZXY.toTileId` in the `pmtiles` package).
  final int tileId;

  /// Where the tile's bytes start, counted from the start of the tile data.
  final int offset;
  final int length;
}

/// Everything in an archive that comes before the tile data: header, root
/// directory, metadata and leaf directories, as one block ready to be written
/// at the start of the file.
class PmTilesHead {
  const PmTilesHead(this.bytes, this.tileDataOffset, this.tileDataLength);

  final Uint8List bytes;

  /// Where the tile data starts in the file (the length of [bytes]).
  final int tileDataOffset;
  final int tileDataLength;

  int get fileLength => tileDataOffset + tileDataLength;
}

/// Writes a PMTiles version 3 archive of already-compressed vector tiles.
///
/// Used to keep just the part of a bigger archive (a city out of the planet) on
/// the phone. The output is an ordinary PMTiles file: the app reads it with the
/// same code as a bundled one, and the official `pmtiles` tool can open it.
///
/// Layout: `header | root directory | metadata | leaf directories | tile data`.
/// Tile bytes are copied verbatim (they stay gzip-compressed MVT), and the
/// archive is *clustered*: tile data is in tile-id order. Because every tile's
/// length is known before any of it is fetched, the whole head can be written
/// first and the data streamed in behind it, with no scratch copy.
class PmTilesWriter {
  const PmTilesWriter._();

  static const int headerLength = 127;

  /// A reader takes the header and root directory from the first 16 KiB, so
  /// they must fit there.
  static const int headAndRootLimit = 16384;

  static const int compressionGzip = 2;
  static const int tileTypeMvt = 1;

  /// Builds the head for [entries], which must be sorted by tile id and laid
  /// out back to back: each offset is the previous offset plus its length.
  static PmTilesHead head({
    required List<PmTileEntry> entries,
    required Map<String, Object?> metadata,
    required double west,
    required double south,
    required double east,
    required double north,
    required int minZoom,
    required int maxZoom,
    int tileCompression = compressionGzip,
    int tileType = tileTypeMvt,
    int leafSize = 4096,
  }) {
    if (entries.isEmpty) {
      throw ArgumentError('an archive needs at least one tile');
    }
    var expected = 0;
    var lastId = -1;
    for (final e in entries) {
      if (e.tileId <= lastId) {
        throw ArgumentError('entries must be sorted by tile id');
      }
      if (e.offset != expected) {
        throw ArgumentError('entries must be contiguous in the tile data');
      }
      lastId = e.tileId;
      expected += e.length;
    }
    final dataLength = expected;

    final leaf = _leafPlan(entries, leafSize);
    final metadataBytes =
        gzip.encode(utf8.encode(jsonEncode(metadata))) as Uint8List;

    final rootOffset = headerLength;
    final metadataOffset = rootOffset + leaf.root.length;
    final leavesOffset = metadataOffset + metadataBytes.length;
    final leavesLength = leaf.leaves.fold<int>(0, (s, l) => s + l.length);
    final dataOffset = leavesOffset + leavesLength;

    final header = ByteData(headerLength);
    const magic = [0x50, 0x4D, 0x54, 0x69, 0x6C, 0x65, 0x73]; // "PMTiles"
    for (var i = 0; i < magic.length; i++) {
      header.setUint8(i, magic[i]);
    }
    header.setUint8(7, 3);
    void u64(int at, int v) => header.setUint64(at, v, Endian.little);
    u64(8, rootOffset);
    u64(16, leaf.root.length);
    u64(24, metadataOffset);
    u64(32, metadataBytes.length);
    u64(40, leavesOffset);
    u64(48, leavesLength);
    u64(56, dataOffset);
    u64(64, dataLength);
    u64(72, entries.length); // addressed tiles
    u64(80, entries.length); // tile entries
    u64(88, entries.length); // distinct tile contents
    header.setUint8(96, 1); // clustered
    header.setUint8(97, compressionGzip); // internal (directories, metadata)
    header.setUint8(98, tileCompression);
    header.setUint8(99, tileType);
    header.setUint8(100, minZoom);
    header.setUint8(101, maxZoom);
    void e7(int at, double degrees) =>
        header.setInt32(at, (degrees * 1e7).round(), Endian.little);
    e7(102, west);
    e7(106, south);
    e7(110, east);
    e7(114, north);
    final centreZoom = ((minZoom + maxZoom) / 2).floor();
    header.setUint8(118, centreZoom);
    e7(119, (west + east) / 2);
    e7(123, (south + north) / 2);

    final out = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(leaf.root)
      ..add(metadataBytes);
    for (final l in leaf.leaves) {
      out.add(l);
    }
    final bytes = out.takeBytes();
    assert(bytes.length == dataOffset);
    return PmTilesHead(bytes, dataOffset, dataLength);
  }

  // ------------------------------------------------------------ directories

  /// The root directory, and the leaf directories it points to when the tile
  /// list is too long for the root alone to fit in the first 16 KiB.
  static ({Uint8List root, List<Uint8List> leaves}) _leafPlan(
    List<PmTileEntry> entries,
    int leafSize,
  ) {
    final tiles = [
      for (final e in entries)
        _Row(tileId: e.tileId, runLength: 1, offset: e.offset, length: e.length),
    ];
    final rootOnly = _compress(tiles);
    if (rootOnly.length <= headAndRootLimit - headerLength) {
      return (root: rootOnly, leaves: const <Uint8List>[]);
    }
    for (var size = math.max(1, leafSize);; size *= 2) {
      final leaves = <Uint8List>[];
      final pointers = <_Row>[];
      var offset = 0;
      for (var i = 0; i < tiles.length; i += size) {
        final chunk = tiles.sublist(i, math.min(i + size, tiles.length));
        final bytes = _compress(chunk);
        pointers.add(_Row(
          tileId: chunk.first.tileId,
          runLength: 0, // zero marks "this entry is a leaf directory"
          offset: offset,
          length: bytes.length,
        ));
        leaves.add(bytes);
        offset += bytes.length;
      }
      final root = _compress(pointers);
      if (root.length <= headAndRootLimit - headerLength) {
        return (root: root, leaves: leaves);
      }
    }
  }

  static Uint8List _compress(List<_Row> rows) =>
      gzip.encode(_encode(rows)) as Uint8List;

  /// The uncompressed directory: entry count, then four columns - tile-id
  /// deltas, run lengths, lengths, and offsets (0 when an entry starts exactly
  /// where the previous one ended, else offset + 1).
  static Uint8List _encode(List<_Row> rows) {
    final b = BytesBuilder(copy: false);
    _varint(b, rows.length);
    var last = 0;
    for (final r in rows) {
      _varint(b, r.tileId - last);
      last = r.tileId;
    }
    for (final r in rows) {
      _varint(b, r.runLength);
    }
    for (final r in rows) {
      _varint(b, r.length);
    }
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final contiguous =
          i > 0 && r.offset == rows[i - 1].offset + rows[i - 1].length;
      _varint(b, contiguous ? 0 : r.offset + 1);
    }
    return b.takeBytes();
  }

  static void _varint(BytesBuilder b, int value) {
    var v = value;
    while (v >= 0x80) {
      b.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    b.addByte(v);
  }
}

class _Row {
  const _Row({
    required this.tileId,
    required this.runLength,
    required this.offset,
    required this.length,
  });

  final int tileId;
  final int runLength;
  final int offset;
  final int length;
}

/// Web-mercator tile arithmetic for choosing which tiles a box needs.
class TileMath {
  const TileMath._();

  static int tileX(double longitude, int zoom) {
    final n = 1 << zoom;
    return (((longitude + 180) / 360) * n).floor().clamp(0, n - 1);
  }

  static int tileY(double latitude, int zoom) {
    final n = 1 << zoom;
    final lat = latitude.clamp(-85.0511, 85.0511) * math.pi / 180;
    final y =
        (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n;
    return y.floor().clamp(0, n - 1);
  }

  /// `(x0, y0, x1, y1)`: the inclusive tile range covering the box at [zoom].
  static (int, int, int, int) range({
    required double west,
    required double south,
    required double east,
    required double north,
    required int zoom,
  }) =>
      (
        tileX(west, zoom),
        tileY(north, zoom), // north is the smaller y
        tileX(east, zoom),
        tileY(south, zoom),
      );

  /// How many tiles the box needs from [minZoom] to [maxZoom].
  static int count({
    required double west,
    required double south,
    required double east,
    required double north,
    required int minZoom,
    required int maxZoom,
  }) {
    var total = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final (x0, y0, x1, y1) =
          range(west: west, south: south, east: east, north: north, zoom: z);
      total += (x1 - x0 + 1) * (y1 - y0 + 1);
    }
    return total;
  }
}

/// Writes [head] then copies nothing else: a convenience for tests and for the
/// extractor, which streams the tile data in behind it itself.
Future<RandomAccessFile> openArchiveForWriting(File file, PmTilesHead head) async {
  final raf = await file.open(mode: FileMode.write);
  await raf.writeFrom(head.bytes);
  await raf.truncate(head.fileLength);
  return raf;
}
