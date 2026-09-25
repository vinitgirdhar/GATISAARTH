import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

/// Raster basemap for places no installed vector archive covers.
///
/// A tile comes from the on-disk cache first, then from the network, and is
/// written to the cache when downloaded, so anything seen online stays visible
/// offline. The network source is Stadia Maps' OSM Bright raster, and only when
/// the build carries a key of the team's own:
///
///     flutter run --dart-define=STADIA_API_KEY=<key>
///
/// Without one the raster layer is cache-only and the vector archives are the
/// map (Profile > Offline Maps). No key is compiled in.
class BundledOfflineTileProvider extends TileProvider {
  BundledOfflineTileProvider() {
    unawaited(initCache());
  }

  static const String apiKey = String.fromEnvironment('STADIA_API_KEY');

  /// True when this build may download raster tiles at all.
  static bool get hasNetworkSource => apiKey.isNotEmpty;

  static Future<String?>? _cacheDir;

  /// Resolves (once) the directory downloaded tiles are kept in.
  static Future<String?> initCache() => _cacheDir ??= _openCache();

  static String? _cachePath;

  static Future<String?> _openCache() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = await Directory('${base.path}/osm_tile_cache')
          .create(recursive: true);
      return _cachePath = dir.path;
    } catch (e) {
      debugPrint('[TileCache] no cache directory: $e');
      return null;
    }
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final key = '${coordinates.z}/${coordinates.x}/${coordinates.y}';
    final dir = _cachePath;
    if (dir != null) {
      final file = File('$dir/$key.png');
      if (file.existsSync()) return FileImage(file);
    }
    return _RasterTile(key: key, cacheDir: dir);
  }
}

/// Offline circuit breaker for tile downloads.
///
/// After any failure (socket error, timeout, non-200, non-PNG) [canAttempt] is
/// false for [cooldown], so an offline phone stops trying the radio for every
/// visible tile. A success re-opens it immediately; each new failure restarts
/// the cooldown from that failure.
class TileNetworkGate {
  TileNetworkGate({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const Duration cooldown = Duration(seconds: 60);

  final DateTime Function() _clock;
  DateTime? _reopensAt;

  /// True unless a failure happened less than [cooldown] ago. A clock that
  /// jumped backwards (remaining > cooldown) counts as expired.
  bool get canAttempt {
    final reopensAt = _reopensAt;
    if (reopensAt == null) return true;
    final remaining = reopensAt.difference(_clock());
    return remaining <= Duration.zero || remaining > cooldown;
  }

  void recordSuccess() => _reopensAt = null;

  void recordFailure() => _reopensAt = _clock().add(cooldown);
}

/// One raster tile: cache, then network, then a transparent square that is
/// evicted at once so the real tile loads when the network returns.
@immutable
class _RasterTile extends ImageProvider<_RasterTile> {
  const _RasterTile({required this.key, required this.cacheDir});

  final String key;
  final String? cacheDir;

  static const String _base = 'https://tiles.stadiamaps.com/tiles/osm_bright';
  static const Duration _timeout = Duration(seconds: 10);
  static const int _maxBytes = 2 * 1024 * 1024;

  static final HttpClient _http = HttpClient()
    ..userAgent = 'GatiSaarth/1.0 (navigation prototype)'
    ..idleTimeout = const Duration(seconds: 15)
    ..connectionTimeout = const Duration(seconds: 4);
  static final TileNetworkGate _gate = TileNetworkGate();

  @override
  Future<_RasterTile> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_RasterTile>(this);

  @override
  ImageStreamCompleter loadImage(_RasterTile key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(decode),
        scale: 1,
        informationCollector: () => [DiagnosticsProperty('Tile', this.key)],
      );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final file = cacheDir == null ? null : File('$cacheDir/$key.png');
    for (final source in [() => _read(file), _download]) {
      final bytes = await source();
      if (bytes == null) continue;
      try {
        final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
        if (file != null && !file.existsSync()) unawaited(_write(file, bytes));
        return codec;
      } catch (_) {
        // Corrupt bytes: try the next source.
      }
    }
    scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
    return decode(await ui.ImmutableBuffer.fromUint8List(_transparentPng));
  }

  static Future<Uint8List?> _read(File? file) async {
    try {
      if (file == null || !await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(File file, Uint8List bytes) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('[TileCache] could not keep a tile: $e');
    }
  }

  // ponytail: a timed-out request is abandoned, not aborted; add
  // request.abort() if stalled servers turn out to leak sockets.
  Future<Uint8List?> _download() async {
    if (!BundledOfflineTileProvider.hasNetworkSource || !_gate.canAttempt) {
      return null;
    }
    try {
      final request = await _http
          .getUrl(Uri.parse(
              '$_base/$key.png?api_key=${BundledOfflineTileProvider.apiKey}'))
          .timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode == HttpStatus.ok &&
          response.contentLength <= _maxBytes) {
        final bytes = await consolidateHttpClientResponseBytes(response)
            .timeout(_timeout);
        if (bytes.length <= _maxBytes && _isPng(bytes)) {
          _gate.recordSuccess();
          return bytes;
        }
      } else {
        await response.drain<void>();
      }
    } catch (_) {
      // Offline or refused: the gate below keeps the radio quiet a while.
    }
    _gate.recordFailure();
    return null;
  }

  static bool _isPng(Uint8List b) =>
      b.length > 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47;

  /// A valid 1×1 transparent PNG.
  static final Uint8List _transparentPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

  @override
  bool operator ==(Object other) => other is _RasterTile && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
