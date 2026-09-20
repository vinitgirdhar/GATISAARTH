import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:http/http.dart' show ByteStream;
import 'package:pmtiles/pmtiles.dart';
import 'package:pool/pool.dart';

/// Where an offline archive's bytes live: a file, from [offset], for [length].
///
/// A bundled archive is not a file of its own: Android keeps it inside the APK,
/// stored uncompressed, so it is read in place at an offset - no second copy on
/// the phone.
class PackLocation {
  const PackLocation({
    required this.path,
    required this.offset,
    required this.length,
    required this.origin,
  });

  final String path;
  final int offset;
  final int length;
  final PackOrigin origin;
}

enum PackOrigin {
  /// Shipped inside the app; cannot be removed.
  bundled,

  /// Downloaded by the app into its own storage; can be removed.
  downloaded,

  /// Copied onto the phone by hand (`adb push`) for testing or updating maps
  /// without a new build; can be removed.
  sideloaded,
}

/// Finds an archive by file name, or null when this build does not have it.
abstract class MapPackLocator {
  Future<PackLocation?> locate(String fileName);
}

/// Asks the Android side, which knows the APK and the app's storage folders.
class PlatformMapPackLocator implements MapPackLocator {
  const PlatformMapPackLocator();

  static const MethodChannel _channel =
      MethodChannel('com.gatisaarth.app/map_packs');

  @override
  Future<PackLocation?> locate(String fileName) async {
    try {
      final found = await _channel.invokeMapMethod<String, Object?>(
        'locate',
        {'name': fileName},
      );
      if (found == null) return null;
      return PackLocation(
        path: found['path']! as String,
        offset: (found['offset']! as num).toInt(),
        length: (found['length']! as num).toInt(),
        origin: switch (found['origin']) {
          'downloaded' => PackOrigin.downloaded,
          'sideloaded' => PackOrigin.sideloaded,
          _ => PackOrigin.bundled,
        },
      );
    } on MissingPluginException {
      return null; // not Android (or a test): the app falls back to online tiles
    } on PlatformException {
      return null;
    }
  }
}

/// Reads a byte range of an archive that starts [offset] bytes into a file.
///
/// Every read opens its own handle: a `RandomAccessFile` allows one outstanding
/// read, and the map asks for many tiles at once. The pool keeps the number of
/// open handles bounded.
class OffsetFileAt implements ReadAt {
  OffsetFileAt(this.file, {this.offset = 0, this.length});

  final File file;

  /// Where the archive begins inside [file].
  final int offset;

  /// Archive size; reads never go past it, so one embedded archive cannot read
  /// its neighbour's bytes. Null means "to the end of the file".
  final int? length;

  final Pool _pool = Pool(8, timeout: const Duration(seconds: 30));

  @override
  Future<ByteStream> readAt(int at, int count) async {
    final limit = length;
    final available = limit == null ? count : math.max(0, limit - at);
    final wanted = math.min(count, available);
    if (wanted <= 0) return ByteStream.fromBytes(const <int>[]);
    return _pool.withResource(() async {
      final handle = await file.open();
      try {
        await handle.setPosition(offset + at);
        return ByteStream.fromBytes(await handle.read(wanted));
      } finally {
        await handle.close();
      }
    });
  }

  @override
  Future<void> close() => _pool.close();
}
