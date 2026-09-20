import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../../../../core/platform/maps/offline_map_service.dart';
import 'basemap_style.dart';
import 'map_follow.dart';

/// Which map sources are needed for a viewport. Pure, so it can be tested
/// without a map and shared by the layers and the attribution line.
class BasemapCoverage {
  const BasemapCoverage({
    required this.base,
    required this.detail,
    required this.needsRaster,
  });

  /// Archives that draw the whole picture where they have data.
  final List<InstalledPack> base;

  /// City archives drawn on top of a base once zoomed in.
  final List<InstalledPack> detail;

  /// Whether the cached/online raster tiles must sit underneath: true unless one
  /// base archive covers the entire viewport.
  final bool needsRaster;

  bool get hasVector => base.isNotEmpty || detail.isNotEmpty;

  /// From this map zoom the city archives are mounted. Their data starts one
  /// level above where the statewide overview stops being detailed.
  static const double detailFromZoom = 12.0;

  static BasemapCoverage of({
    required List<InstalledPack> installed,
    required LatLngBounds viewport,
    required double zoom,
  }) {
    bool touches(InstalledPack p) => p.pack.intersects(
          south: viewport.south,
          west: viewport.west,
          north: viewport.north,
          east: viewport.east,
        );

    final visible = installed.where(touches).toList();
    final base = visible.where((p) => !p.pack.detail).toList();
    final detail = zoom >= detailFromZoom
        ? visible.where((p) => p.pack.detail).toList()
        : <InstalledPack>[];

    final corners = [
      viewport.northWest,
      viewport.northEast,
      viewport.southWest,
      viewport.southEast,
    ];
    final covered = base.any((p) => corners.every(p.pack.contains));
    return BasemapCoverage(base: base, detail: detail, needsRaster: !covered);
  }
}

/// The vector styles, built once (parsing about seventy style layers is not
/// something to repeat on every frame).
///
/// Protomaps' own light and dark styles, so the map follows the app's
/// brightness. The city-detail archives are drawn *over* a base map, so their
/// style has no background layer: a tile with nothing in it must stay
/// transparent, not paint an opaque square over the base.
class BasemapThemes {
  const BasemapThemes._();

  static final vtr.Theme light = BasemapStyle.light();
  static final vtr.Theme dark = BasemapStyle.dark();
  static final vtr.Theme lightOverlay = BasemapStyle.light(overlay: true);
  static final vtr.Theme darkOverlay = BasemapStyle.dark(overlay: true);

  static vtr.Theme forBrightness({required bool dark, required bool overlay}) {
    if (overlay) return dark ? darkOverlay : lightOverlay;
    return dark ? BasemapThemes.dark : BasemapThemes.light;
  }

  /// Colour shown under the tiles while they load, matched to each style's
  /// land colour so a slow tile never flashes white.
  static Color loadingColor({required bool dark}) =>
      dark ? const Color(0xFF1F1F1F) : const Color(0xFFE0E0E0);

}

/// The map's picture, as a `FlutterMap` child: vector archives where the phone
/// has them, and the cached/online raster tiles underneath wherever they do not
/// cover the screen.
class Basemap extends StatelessWidget {
  const Basemap({
    super.key,
    required this.service,
    this.rasterProvider,
    required this.dark,
  });

  final OfflineMapService? service;

  /// Cached/online tiles for where no archive reaches. Null draws nothing
  /// there (the Offline Maps preview must show only what is really offline).
  final TileProvider? rasterProvider;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final coverage = BasemapCoverage.of(
      installed: service?.installed ?? const [],
      viewport: camera.visibleBounds,
      zoom: camera.zoom,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (coverage.needsRaster && rasterProvider != null)
          _RasterFallback(provider: rasterProvider!, dark: dark),
        for (final pack in coverage.base)
          _VectorPack(
            key: ValueKey('${pack.pack.id}/base/$dark'),
            installed: pack,
            dark: dark,
            overlay: false,
          ),
        for (final pack in coverage.detail)
          _VectorPack(
            key: ValueKey('${pack.pack.id}/detail/$dark'),
            installed: pack,
            dark: dark,
            overlay: true,
          ),
      ],
    );
  }
}

class _VectorPack extends StatelessWidget {
  const _VectorPack({
    super.key,
    required this.installed,
    required this.dark,
    required this.overlay,
  });

  final InstalledPack installed;
  final bool dark;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    return VectorTileLayer(
      tileProviders: TileProviders({'protomaps': installed.provider}),
      theme: BasemapThemes.forBrightness(dark: dark, overlay: overlay),
      // 512 px tiles: the sizes the Protomaps styles are drawn for.
      tileOffset: TileOffset.mapbox,
      // Vector data scales, so the map stays sharp well past the last stored
      // zoom (an archive's data ends at 12 or 15).
      maximumZoom: MapZoom.max,
      // The archives are local files; the raw-tile disk cache would only copy
      // them again, so keep it small.
      fileCacheMaximumSizeInBytes: 8 * 1024 * 1024,
      memoryTileDataCacheMaxSize: 24,
    );
  }
}

/// The pre-vector map: bundled Delhi tiles, then the on-disk cache, then the
/// network. Only used where no archive covers the screen.
class _RasterFallback extends StatelessWidget {
  const _RasterFallback({required this.provider, required this.dark});

  final TileProvider provider;
  final bool dark;

  /// Inverts and desaturates the daylight raster for dark mode.
  static const ColorFilter _darkFilter = ColorFilter.matrix(<double>[
    -0.4989, -0.3462, -0.0349, 0, 224.4, //
    -0.1029, -0.7422, -0.0349, 0, 224.4, //
    -0.1029, -0.3462, -0.4309, 0, 224.4, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final layer = TileLayer(
      // Placeholder only: the provider resolves every tile itself.
      urlTemplate: 'https://tiles.invalid/{z}/{x}/{y}.png',
      userAgentPackageName: 'GatiSaarth',
      tileProvider: provider,
      minNativeZoom: 11,
      maxNativeZoom: 16,
      minZoom: MapZoom.min,
      maxZoom: MapZoom.max,
      errorTileCallback: (tile, error, stackTrace) {},
    );
    return dark ? ColorFiltered(colorFilter: _darkFilter, child: layer) : layer;
  }
}

/// The attribution the visible sources require, as one line.
String basemapAttribution(BasemapCoverage coverage) {
  final parts = <String>['© OpenStreetMap contributors'];
  if (coverage.hasVector) parts.add('Protomaps');
  if (coverage.needsRaster) parts.add('Stadia Maps');
  return parts.join(' · ');
}

/// True when [point] has no offline archive although some are installed: the
/// map there depends on the network.
bool outsideOfflineRegions(OfflineMapService? service, LatLng point) {
  if (service == null || service.installed.isEmpty) return false;
  return !service.covers(point);
}
