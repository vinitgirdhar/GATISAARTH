import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import 'offline_catalog.dart';
import 'pack_reader.dart';

/// An archive that is present on this phone and opened.
@immutable
class InstalledPack {
  const InstalledPack({
    required this.pack,
    required this.provider,
    required this.bytes,
    required this.origin,
    this.path,
  });

  final OfflinePack pack;
  final VectorTileProvider provider;

  /// The archive's own file, or null for a bundled one (it lives inside the
  /// APK and cannot be removed).
  final String? path;

  /// Real size of the archive, not the catalogue's estimate.
  final int bytes;
  final PackOrigin origin;
}

/// Opens one archive. Replaceable so tests need no real PMTiles file.
typedef PackOpener = Future<VectorTileProvider> Function(
  PackLocation location,
  OfflinePack pack,
);

/// Knows which offline archives this phone has and hands out their tiles.
///
/// Nothing is downloaded: archives ship in the app (or were pushed onto the
/// phone for testing). A pack that is missing or unreadable is simply absent -
/// the map then falls back to cached/online tiles for that area - and the
/// reason is kept for the Offline Maps screen.
class OfflineMapService extends ChangeNotifier {
  OfflineMapService({
    MapPackLocator locator = const PlatformMapPackLocator(),
    PackOpener? opener,
    List<OfflinePack>? catalog,
  })  : _locator = locator,
        _opener = opener ?? _openArchive,
        _catalog = catalog ?? OfflineCatalog.packs;

  final MapPackLocator _locator;
  final PackOpener _opener;
  final List<OfflinePack> _catalog;

  final Map<String, InstalledPack> _installed = {};
  final Map<String, String> _problems = {};
  bool _loading = false;
  bool _rescan = false;
  bool _loaded = false;
  bool _disposed = false;

  /// True until the first [load] has finished (successfully or not).
  bool get isLoading => _loading || !_loaded;
  bool get isLoaded => _loaded;

  List<InstalledPack> get installed => List.unmodifiable(_installed.values);
  int get installedBytes =>
      _installed.values.fold(0, (sum, p) => sum + p.bytes);

  InstalledPack? installedPack(String id) => _installed[id];
  bool isInstalled(String id) => _installed.containsKey(id);

  /// Why a pack that should be here is not, or null.
  String? problemWith(String id) => _problems[id];

  /// Whether every pack of [region] is present.
  bool isRegionComplete(OfflineRegion region) =>
      region.packs.every((p) => isInstalled(p.id));

  /// How many of [region]'s packs are present.
  int installedCount(OfflineRegion region) =>
      region.packs.where((p) => isInstalled(p.id)).length;

  /// Whether an installed archive has data at [point].
  bool covers(LatLng point) =>
      _installed.values.any((p) => p.pack.contains(point));

  /// Finds and opens every archive in the catalogue. Safe to call again (e.g.
  /// after new files were pushed): it rescans.
  Future<void> load() async {
    if (_loading) {
      // A file may have appeared since this scan looked: go round again.
      _rescan = true;
      return;
    }
    _loading = true;
    _notify();
    do {
      _rescan = false;
      await _scan();
    } while (_rescan && !_disposed);
    _loading = false;
    _loaded = true;
    _notify();
  }

  Future<void> _scan() async {
    final found = <String, InstalledPack>{};
    final problems = <String, String>{};
    await Future.wait([
      for (final pack in _catalog)
        () async {
          try {
            final location = await _locator.locate(pack.fileName);
            if (location == null) return;
            final provider = await _opener(location, pack);
            found[pack.id] = InstalledPack(
              pack: pack,
              provider: provider,
              bytes: location.length,
              origin: location.origin,
              path: location.origin == PackOrigin.bundled ? null : location.path,
            );
          } catch (e) {
            problems[pack.id] = '$e';
            debugPrint('[OfflineMaps] ${pack.fileName} unusable: $e');
          }
        }(),
    ]);
    _installed
      ..clear()
      ..addAll(found);
    _problems
      ..clear()
      ..addAll(problems);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static Future<VectorTileProvider> _openArchive(
    PackLocation location,
    OfflinePack pack,
  ) async {
    final reader = OffsetFileAt(
      File(location.path),
      offset: location.offset,
      length: location.length,
    );
    // ignore: invalid_use_of_visible_for_testing_member
    final archive = await PmTilesArchive.fromReadAt(reader);
    if (archive.header.tileType != TileType.mvt) {
      throw StateError('${pack.fileName} holds ${archive.header.tileType} '
          'tiles, not vector tiles');
    }
    return PmTilesVectorTileProvider.fromArchive(archive);
  }
}

/// Makes the [OfflineMapService] reachable from any screen.
class OfflineMapsScope extends InheritedNotifier<OfflineMapService> {
  const OfflineMapsScope({
    super.key,
    required OfflineMapService service,
    required super.child,
  }) : super(notifier: service);

  /// The service, or null where none was provided (widget tests that only draw
  /// a map): callers then use the online/cached tiles.
  static OfflineMapService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<OfflineMapsScope>()
      ?.notifier;

  static OfflineMapService of(BuildContext context) {
    final service = maybeOf(context);
    assert(service != null, 'No OfflineMapsScope above this widget');
    return service!;
  }
}
