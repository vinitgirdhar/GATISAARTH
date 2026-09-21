import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/platform/maps/map_download_service.dart';
import '../../../core/platform/maps/offline_catalog.dart';
import '../../../core/platform/maps/offline_map_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';
import '../../navigation_ui/presentation/widgets/basemap_layers.dart';
import '../../navigation_ui/presentation/widgets/map_follow.dart';
import 'region_card.dart';

/// The maps that work without a connection: what this build carries, how big it
/// is, and a live preview drawn from the very files a drive will use - so
/// switching on airplane mode and panning the preview *is* the offline test.
class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen>
    with SingleTickerProviderStateMixin {
  final MapController _preview = MapController();
  final ScrollController _scroll = ScrollController();
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addListener(_flyStep);

  OfflineRegion _selected = OfflineCatalog.delhi;
  bool _ready = false;

  LatLng _from = OfflineCatalog.delhi.center;
  LatLng _to = OfflineCatalog.delhi.center;
  double _fromZoom = 9;
  double _toZoom = 9;

  @override
  void dispose() {
    _fly.dispose();
    _scroll.dispose();
    _preview.dispose();
    super.dispose();
  }

  static LatLngBounds _bounds(OfflineRegion r) =>
      LatLngBounds(LatLng(r.south, r.west), LatLng(r.north, r.east));

  static CameraFit _fit(OfflineRegion r) => CameraFit.bounds(
        bounds: _bounds(r),
        padding: const EdgeInsets.all(28),
        maxZoom: 12,
      );

  /// Glides the preview to [region], pulling back in the middle of a long trip
  /// so the two places are seen to be connected rather than swapped.
  void _flyTo(OfflineRegion region) {
    setState(() => _selected = region);
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(
        0,
        duration: AppMotion.of(context, AppMotion.medium),
        curve: Curves.easeOutCubic,
      );
    }
    if (!_ready) return;
    final camera = _preview.camera;
    final target = _fit(region).fit(camera);
    _from = camera.center;
    _fromZoom = camera.zoom;
    _to = target.center;
    _toZoom = target.zoom;
    if (MediaQuery.disableAnimationsOf(context)) {
      _preview.move(_to, _toZoom);
      return;
    }
    _fly.forward(from: 0);
  }

  void _flyStep() {
    final t = Curves.easeInOutCubic.transform(_fly.value);
    final far = (_from.latitude - _to.latitude).abs() +
        (_from.longitude - _to.longitude).abs();
    // Zoom out by up to ~2 levels mid-flight, more for a longer trip.
    final pullBack = math.min(2.0, far * 0.6) * math.sin(math.pi * t);
    _preview.move(
      LatLng(
        _from.latitude + (_to.latitude - _from.latitude) * t,
        _from.longitude + (_to.longitude - _from.longitude) * t,
      ),
      (_fromZoom + (_toZoom - _fromZoom) * t - pullBack)
          .clamp(MapZoom.min, 18.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = OfflineMapsScope.maybeOf(context);
    final downloads = MapDownloadsScope.maybeOf(context);
    final dark = AppColors.isDark;

    final sections = <Widget>[
      _PreviewCard(
        service: service,
        dark: dark,
        selected: _selected,
        controller: _preview,
        initialFit: _fit(_selected),
        onReady: () => _ready = true,
      ),
      _StorageSummary(service: service, downloads: downloads),
      for (final region in OfflineCatalog.regions)
        RegionCard(
          region: region,
          service: service,
          downloads: downloads,
          selected: region.id == _selected.id,
          onShow: () => _flyTo(region),
        ),
      const _HowItWorks(),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Offline maps')),
      body: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) {
          final section = sections[i];
          if (i >= 3) return section;
          return FadeSlideIn(
            delay: Duration(milliseconds: 70 * i),
            offset: -0.06,
            child: section,
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ preview

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.service,
    required this.dark,
    required this.selected,
    required this.controller,
    required this.initialFit,
    required this.onReady,
  });

  final OfflineMapService? service;
  final bool dark;
  final OfflineRegion selected;
  final MapController controller;
  final CameraFit initialFit;
  final VoidCallback onReady;

  static List<LatLng> _box(OfflinePack p) => [
        LatLng(p.north, p.west),
        LatLng(p.north, p.east),
        LatLng(p.south, p.east),
        LatLng(p.south, p.west),
      ];

  @override
  Widget build(BuildContext context) {
    final outline = AppColors.primary;
    final muted = AppColors.textMuted;
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: BasemapThemes.loadingColor(dark: dark),
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadow.card,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.cardRadius,
        child: Stack(
          children: [
            FlutterMap(
              mapController: controller,
              options: MapOptions(
                initialCameraFit: initialFit,
                minZoom: MapZoom.min,
                maxZoom: 18,
                backgroundColor: BasemapThemes.loadingColor(dark: dark),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag |
                      InteractiveFlag.flingAnimation |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom,
                ),
                onMapReady: onReady,
              ),
              children: [
                // No raster fallback: the preview shows only what is offline.
                Basemap(service: service, dark: dark),
                PolygonLayer(polygons: [
                  for (final region in OfflineCatalog.regions)
                    for (final pack in region.packs)
                      Polygon(
                        points: _box(pack),
                        color: region.id == selected.id && !pack.detail
                            ? outline.withValues(alpha: 0.07)
                            : null,
                        borderColor: region.id == selected.id
                            ? outline.withValues(
                                alpha: pack.detail ? 0.95 : 0.7)
                            : muted.withValues(alpha: 0.7),
                        borderStrokeWidth: pack.detail ? 1.6 : 1.3,
                        pattern: pack.detail
                            ? const StrokePattern.solid()
                            : StrokePattern.dashed(segments: const [8, 6]),
                      ),
                ]),
              ],
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: IgnorePointer(
                child: _Chip(
                  icon: Icons.map_rounded,
                  label: selected.name,
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: IgnorePointer(
                child: Text(
                  OfflineCatalog.attribution,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary.withValues(alpha: 0.6),
                    shadows: [
                      Shadow(
                        color: AppColors.surface.withValues(alpha: 0.9),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.control),
        boxShadow: AppShadow.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ summary

class _StorageSummary extends StatelessWidget {
  const _StorageSummary({required this.service, required this.downloads});

  final OfflineMapService? service;
  final MapDownloadService? downloads;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final loading = s == null ? false : s.isLoading;
    final count = s?.installed.length ?? 0;
    final total = OfflineCatalog.packs.length;
    final ok = count > 0;
    final color = loading
        ? AppColors.textSecondary
        : (count == total ? AppColors.success : AppColors.warning);

    final String title;
    final String detail;
    final d = downloads;
    if (loading) {
      title = 'Checking map files…';
      detail = 'Looking for the maps stored on this phone.';
    } else if (d != null && d.isBusy) {
      title = 'Downloading ${d.pending == 1 ? '1 map' : '${d.pending} maps'}…';
      detail = 'Keep the app open. ${(d.overallFraction * 100).round()}% done'
          ' · you can keep using the app meanwhile.';
    } else if (!ok) {
      title = 'No offline maps on this phone yet';
      detail = 'Download a region below, or the map uses cached and online '
          'tiles.';
    } else {
      title = '${megabytes(s!.installedBytes)} of maps on this phone';
      detail = '$count of $total maps ready · works without internet · '
          'OpenStreetMap data';
    }

    return MapsSurface(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: loading
                ? Padding(
                    padding: const EdgeInsets.all(13),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: color,
                    ),
                  )
                : Icon(
                    ok ? Icons.download_done_rounded : Icons.cloud_off_rounded,
                    color: color,
                    size: 24,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- how it works

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );

    return MapsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          line(
            Icons.brush_rounded,
            'The map is drawn on this phone from OpenStreetMap vector data, '
            'so roads stay sharp however far you zoom.',
          ),
          line(
            Icons.airplanemode_active_rounded,
            'To test it, switch on airplane mode and pan or zoom the preview '
            'above. Nothing there needs a connection.',
          ),
          line(
            Icons.download_for_offline_rounded,
            'Download the areas you drive in and delete the ones you do not. '
            'Maps come straight from OpenStreetMap data, only for the area '
            'you choose.',
          ),
          line(
            Icons.cloud_queue_rounded,
            'Outside downloaded areas the map uses cached tiles and fetches '
            'more while you are online.',
          ),
        ],
      ),
    );
  }
}
