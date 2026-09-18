import 'dart:async';
import 'dart:io';

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

/// Offline-First TileProvider with automatic network tile caching.
///
/// Tile resolution priority chain:
///   1. **Pre-bundled asset tiles** — shipped inside the APK, zero latency, zero network.
///   2. **Disk-cached tiles** — previously fetched from OSM and persisted on device.
///   3. **Live network fetch** — downloads from OpenStreetMap, auto-saves to disk cache.
///   4. **Transparent fallback** — when fully offline and tile was never cached before.
///
/// This ensures that any map region your teammate views while online will
/// work perfectly offline afterwards, regardless of their physical location.
class BundledOfflineTileProvider extends TileProvider {
  // ---------------------------------------------------------------------------
  // Cache directory management (lazy, one-time init)
  // ---------------------------------------------------------------------------
  static String? _cacheDirPath;
  static bool _cacheInitAttempted = false;

  /// Resolves the on-device cache directory. Safe to call multiple times;
  /// only does real I/O once. Called from `main()` for fastest readiness,
  /// but also triggered lazily from the constructor as a safety net.
  static Future<void> initCache() async {
    if (_cacheDirPath != null || _cacheInitAttempted) return;
    _cacheInitAttempted = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${dir.path}/osm_tile_cache');
      await cacheDir.create(recursive: true);
      _cacheDirPath = cacheDir.path;
      debugPrint('[TileCache] Initialized at: ${cacheDir.path}');
    } catch (e) {
      debugPrint('[TileCache] Init failed (non-fatal): $e');
    }
  }

  BundledOfflineTileProvider() {
    // Safety net: kick off async init if main() didn't call it yet.
    if (_cacheDirPath == null && !_cacheInitAttempted) {
      initCache();
    }
  }

  // ---------------------------------------------------------------------------
  // Pre-bundled tile keys (shipped inside the APK as PNG assets)
  // ---------------------------------------------------------------------------
  static const Set<String> _bundledTiles = {
    '11/1462/853',
    '11/1462/854',
    '11/1463/853',
    '11/1463/854',
    '12/2924/1707',
    '12/2924/1708',
    '12/2925/1707',
    '12/2925/1708',
    '12/2926/1707',
    '12/2926/1708',
    '13/5848/3414',
    '13/5848/3415',
    '13/5848/3416',
    '13/5849/3414',
    '13/5849/3415',
    '13/5849/3416',
    '13/5850/3414',
    '13/5850/3415',
    '13/5850/3416',
    '13/5851/3414',
    '13/5851/3415',
    '13/5851/3416',
    '13/5852/3414',
    '13/5852/3415',
    '13/5852/3416',
    '13/5853/3414',
    '13/5853/3415',
    '13/5853/3416',
    '14/11697/6828',
    '14/11697/6829',
    '14/11697/6830',
    '14/11697/6831',
    '14/11697/6832',
    '14/11697/6833',
    '14/11698/6828',
    '14/11698/6829',
    '14/11698/6830',
    '14/11698/6831',
    '14/11698/6832',
    '14/11698/6833',
    '14/11699/6828',
    '14/11699/6829',
    '14/11699/6830',
    '14/11699/6831',
    '14/11699/6832',
    '14/11699/6833',
    '14/11700/6828',
    '14/11700/6829',
    '14/11700/6830',
    '14/11700/6831',
    '14/11700/6832',
    '14/11700/6833',
    '14/11701/6828',
    '14/11701/6829',
    '14/11701/6830',
    '14/11701/6831',
    '14/11701/6832',
    '14/11701/6833',
    '14/11702/6828',
    '14/11702/6829',
    '14/11702/6830',
    '14/11702/6831',
    '14/11702/6832',
    '14/11702/6833',
    '14/11703/6828',
    '14/11703/6829',
    '14/11703/6830',
    '14/11703/6831',
    '14/11703/6832',
    '14/11703/6833',
    '14/11704/6828',
    '14/11704/6829',
    '14/11704/6830',
    '14/11704/6831',
    '14/11704/6832',
    '14/11704/6833',
    '14/11705/6828',
    '14/11705/6829',
    '14/11705/6830',
    '14/11705/6831',
    '14/11705/6832',
    '14/11705/6833',
    '14/11706/6828',
    '14/11706/6829',
    '14/11706/6830',
    '14/11706/6831',
    '14/11706/6832',
    '14/11706/6833',
    '14/11707/6828',
    '14/11707/6829',
    '14/11707/6830',
    '14/11707/6831',
    '14/11707/6832',
    '14/11707/6833',
    '15/23396/13659',
    '15/23396/13660',
    '15/23396/13661',
    '15/23396/13662',
    '15/23396/13663',
    '15/23397/13659',
    '15/23397/13660',
    '15/23397/13661',
    '15/23397/13662',
    '15/23397/13663',
    '15/23398/13659',
    '15/23398/13660',
    '15/23398/13661',
    '15/23398/13662',
    '15/23398/13663',
    '15/23399/13659',
    '15/23399/13660',
    '15/23399/13661',
    '15/23399/13662',
    '15/23399/13663',
    '15/23400/13659',
    '15/23400/13660',
    '15/23400/13661',
    '15/23400/13662',
    '15/23400/13663',
    '15/23410/13662',
    '15/23410/13663',
    '15/23410/13664',
    '15/23411/13662',
    '15/23411/13663',
    '15/23411/13664',
    '15/23412/13662',
    '15/23412/13663',
    '15/23412/13664',
    '16/46795/27320',
    '16/46795/27321',
    '16/46795/27322',
    '16/46795/27323',
    '16/46795/27324',
    '16/46796/27320',
    '16/46796/27321',
    '16/46796/27322',
    '16/46796/27323',
    '16/46796/27324',
    '16/46797/27320',
    '16/46797/27321',
    '16/46797/27322',
    '16/46797/27323',
    '16/46797/27324',
    '16/46798/27320',
    '16/46798/27321',
    '16/46798/27322',
    '16/46798/27323',
    '16/46798/27324',
    '16/46799/27320',
    '16/46799/27321',
    '16/46799/27322',
    '16/46799/27323',
    '16/46799/27324',
    '16/46822/27326',
    '16/46822/27327',
    '16/46822/27328',
    '16/46823/27326',
    '16/46823/27327',
    '16/46823/27328',
    '16/46824/27326',
    '16/46824/27327',
    '16/46824/27328',
  };

  // ---------------------------------------------------------------------------
  // Core tile resolution — called by FlutterMap for every visible tile
  // ---------------------------------------------------------------------------
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final key =
        '${coordinates.z.toInt()}/${coordinates.x.toInt()}/${coordinates.y.toInt()}';

    // ── Tier 1: Pre-bundled APK asset (zero latency, zero network) ──
    if (_bundledTiles.contains(key)) {
      return AssetImage('assets/maps/tiles/$key.png');
    }

    // ── Tier 2: Disk cache hit (synchronous file check) ──
    if (_cacheDirPath != null) {
      final cacheFile = File('$_cacheDirPath/$key.png');
      if (cacheFile.existsSync()) {
        return FileImage(cacheFile);
      }
    }

    // ── Tier 3: Network fetch with auto-caching → Tier 4: transparent fallback ──
    if (_cacheDirPath != null) {
      return _CachingNetworkTileImage(
        tileKey: key,
        cacheDirPath: _cacheDirPath!,
      );
    }

    // Cache dir not ready yet — plain network (no disk persistence)
    return NetworkImage(
      _CachingNetworkTileImage._tileUrl(key),
      headers: {'User-Agent': _CachingNetworkTileImage._userAgent},
    );
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

// =============================================================================
// Custom ImageProvider: fetches a tile from Stadia Maps over ONE shared
// HttpClient, persists it to disk, and returns a transparent tile on failure.
// While [_networkGate] is closed (recent failure => probably offline) the
// network is skipped entirely.
// =============================================================================
class _CachingNetworkTileImage extends ImageProvider<_CachingNetworkTileImage> {
  final String tileKey;
  final String cacheDirPath;

  /// Stadia Maps tile server (free tier, API key authenticated). The key can
  /// be overridden at build time: `--dart-define=STADIA_API_KEY=...`.
  static const String _stadiaTileBase =
      'https://tiles.stadiamaps.com/tiles/osm_bright';
  static const String _stadiaApiKey = String.fromEnvironment(
    'STADIA_API_KEY',
    defaultValue: '9ca55c4e-7cb5-45b9-9da3-10421c141cbe',
  );

  static const String _userAgent =
      'GatiSaarth/1.0 (navigation prototype)';

  static const Duration _fetchTimeout = Duration(seconds: 10);

  static String _tileUrl(String tileKey) =>
      '$_stadiaTileBase/$tileKey.png?api_key=$_stadiaApiKey';

  /// One client for every tile (static finals are created lazily on first use).
  static final HttpClient _httpClient = HttpClient()
    ..userAgent = _userAgent
    ..idleTimeout = const Duration(seconds: 15)
    ..connectionTimeout = const Duration(seconds: 4);

  static final TileNetworkGate _networkGate = TileNetworkGate();

  const _CachingNetworkTileImage({
    required this.tileKey,
    required this.cacheDirPath,
  });

  @override
  Future<_CachingNetworkTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_CachingNetworkTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachingNetworkTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<String>('Tile key', tileKey),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    // ── Double-check disk cache (another getImage call may have cached it) ──
    final cacheFile = File('$cacheDirPath/$tileKey.png');
    final cached = await _readCached(cacheFile);
    final cachedCodec =
        cached == null ? null : await _tryDecode(cached, decode);
    if (cachedCodec != null) return cachedCodec;

    // ── Tier 3: network (skipped while the circuit breaker is open) ──
    final fetched = await _fetchFromNetwork();
    if (fetched != null) {
      _saveToCacheAsync(cacheFile, fetched); // fire-and-forget
      final codec = await _tryDecode(fetched, decode);
      if (codec != null) return codec;
    }

    // ── Tier 4: Transparent 1×1 fallback (no broken image icon) ──
    // Drop it from Flutter's in-memory image cache straight away, otherwise
    // the blank placeholder would be served for this tile for the rest of the
    // session and it would never load once the network is back.
    scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
    return _decode(_kTransparentPng, decode);
  }

  Future<Uint8List?> _readCached(File cacheFile) async {
    try {
      if (!await cacheFile.exists()) return null;
      final bytes = await cacheFile.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null; // Non-fatal — try network next
    }
  }

  /// Downloads the tile via the shared client. Returns validated PNG bytes, or
  /// null on any failure; every outcome feeds [_networkGate].
  Future<Uint8List?> _fetchFromNetwork() async {
    if (!_networkGate.canAttempt) return null;
    try {
      final bytes = await _download().timeout(_fetchTimeout);
      if (bytes != null) {
        _networkGate.recordSuccess();
        return bytes;
      }
    } catch (_) {
      // Network unavailable — expected when offline
    }
    _networkGate.recordFailure();
    return null;
  }

  // ponytail: on timeout the request is abandoned, not aborted; add
  // request.abort() if stalled servers turn out to leak sockets.
  Future<Uint8List?> _download() async {
    final request = await _httpClient.getUrl(Uri.parse(_tileUrl(tileKey)));
    final response = await request.close();
    final length = response.contentLength; // -1 when unknown
    if (response.statusCode != HttpStatus.ok || length > _maxTileBytes) {
      await response.drain<void>(); // release the pooled connection
      return null;
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    return bytes.length <= _maxTileBytes && _hasPngSignature(bytes)
        ? bytes
        : null;
  }

  /// Map tiles are a few tens of KB; anything huge is not a tile.
  static const int _maxTileBytes = 2 * 1024 * 1024;

  static const List<int> _pngSignature = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  ];

  static bool _hasPngSignature(Uint8List bytes) {
    if (bytes.length <= _pngSignature.length) return false;
    for (var i = 0; i < _pngSignature.length; i++) {
      if (bytes[i] != _pngSignature[i]) return false;
    }
    return true;
  }

  Future<ui.Codec> _decode(
          Uint8List bytes, ImageDecoderCallback decode) async =>
      decode(await ui.ImmutableBuffer.fromUint8List(bytes));

  Future<ui.Codec?> _tryDecode(
      Uint8List bytes, ImageDecoderCallback decode) async {
    try {
      return await _decode(bytes, decode);
    } catch (_) {
      return null; // corrupt bytes — fall through to the next tier
    }
  }

  /// Saves tile bytes to disk without blocking the image pipeline.
  void _saveToCacheAsync(File cacheFile, List<int> bytes) {
    Future<void>(() async {
      try {
        await cacheFile.parent.create(recursive: true);
        await cacheFile.writeAsBytes(bytes, flush: true);
      } catch (e) {
        debugPrint('[TileCache] Write failed for $tileKey: $e');
      }
    });
  }

  /// Minimal valid 1x1 transparent PNG (70 bytes).
  static final Uint8List _kTransparentPng = Uint8List.fromList(const <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x60, 0x60, 0x60, 0x60,
    0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0xA5, 0xF6,
    0x45, 0x40, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
    0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CachingNetworkTileImage &&
          runtimeType == other.runtimeType &&
          tileKey == other.tileKey;

  @override
  int get hashCode => tileKey.hashCode;

  @override
  String toString() =>
      '${objectRuntimeType(this, '_CachingNetworkTileImage')}($tileKey)';
}
