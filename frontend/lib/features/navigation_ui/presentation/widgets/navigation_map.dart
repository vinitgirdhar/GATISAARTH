import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../../core/platform/maps/offline_tile_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/geo_format.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';
import 'confidence_halo.dart';
import 'fusion_confidence_badge.dart';

/// Live map with the vehicle puck. Tiles come from the bundled/cached
/// offline provider (the URL template below is never fetched — the provider
/// resolves every tile itself).
class NavigationMap extends StatefulWidget {
  final NavigationStateModel navigationState;

  /// Modelled position uncertainty in metres; null while there is no fix.
  final double? marginMeters;
  final double height;

  /// The map always re-centres on the vehicle, so panning is pointless — and
  /// inside a scrolling page it would swallow vertical drags. When true only
  /// pinch/double-tap zoom is enabled (fullscreen navigation); otherwise the
  /// map is a static live preview.
  final bool interactive;

  /// Fill whatever the parent gives it, edge to edge (no card margin, corners
  /// or shadow), instead of being a fixed-[height] card. [height] is ignored.
  final bool expand;

  /// Gap between the bottom edge and the coordinates pill. Raise it when the
  /// map runs underneath a sheet that would otherwise cover the pill.
  final double bottomInset;

  const NavigationMap({
    Key? key,
    required this.navigationState,
    required this.marginMeters,
    this.height = 260,
    this.interactive = false,
    this.expand = false,
    this.bottomInset = 12,
  }) : super(key: key);

  @override
  State<NavigationMap> createState() => _NavigationMapState();
}

class _NavigationMapState extends State<NavigationMap> {
  final MapController _mapController = MapController();
  final BundledOfflineTileProvider _tileProvider = BundledOfflineTileProvider();

  @override
  void didUpdateWidget(covariant NavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.navigationState;
    final now = widget.navigationState;
    // The puck is drawn at the exact position; the camera only needs to follow
    // once the vehicle has moved visibly (moving it re-lays-out every tile).
    final dLatM = (now.latitude - old.latitude) * 111000;
    final dLonM = (now.longitude - old.longitude) *
        111000 *
        math.cos(now.latitude * math.pi / 180);
    if (dLatM.abs() + dLonM.abs() > 0.3) {
      _mapController.move(
        LatLng(now.latitude, now.longitude),
        _mapController.camera.zoom,
      );
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  static String _modeLabel(FusionMode mode) {
    switch (mode) {
      case FusionMode.gnssLocked:
        return 'GNSS locked';
      case FusionMode.gnssDegraded:
        return 'GNSS degraded';
      case FusionMode.deadReckoning:
        return 'Dead reckoning';
      case FusionMode.reacquiring:
        return 'Reacquiring GNSS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.navigationState;
    final position = LatLng(state.latitude, state.longitude);
    final margin = widget.marginMeters;
    final radius = widget.expand ? BorderRadius.zero : AppRadius.cardRadius;

    return RepaintBoundary(
      child: Semantics(
        label: 'Map. ${_modeLabel(state.fusionMode)}. '
            '${formatLatitude(state.latitude)}, '
            '${formatLongitude(state.longitude)}',
        child: Container(
          height: widget.expand ? null : widget.height,
          margin: widget.expand
              ? EdgeInsets.zero
              : const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: radius,
            boxShadow: widget.expand ? null : AppShadow.raised,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: position,
                    initialZoom: 15.0,
                    maxZoom: 18.0,
                    minZoom: 10.0,
                    interactionOptions: InteractionOptions(
                      flags: widget.interactive
                          ? InteractiveFlag.pinchZoom |
                              InteractiveFlag.doubleTapZoom
                          : InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    _DarkMapFilter(
                      child: TileLayer(
                        // Placeholder only: BundledOfflineTileProvider ignores it.
                        urlTemplate: 'https://tiles.invalid/{z}/{x}/{y}.png',
                        userAgentPackageName: 'GatiSaarth',
                        tileProvider: _tileProvider,
                        minNativeZoom: 11,
                        maxNativeZoom: 16,
                        minZoom: 10.0,
                        maxZoom: 18.0,
                        errorTileCallback: (tile, error, stackTrace) {},
                      ),
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: position,
                          width: 120,
                          height: 120,
                          child: IgnorePointer(
                            child: Center(
                              child: ConfidenceHalo(
                                confidence: state.confidence,
                              ),
                            ),
                          ),
                        ),
                        Marker(
                          point: position,
                          width: 54,
                          height: 54,
                          child: Transform.rotate(
                            // Heading is degrees clockwise from north, which
                            // is also Flutter's clockwise-positive rotation.
                            angle: state.heading * math.pi / 180,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.surface,
                                    boxShadow: AppShadow.card,
                                  ),
                                ),
                                const Icon(
                                  Icons.navigation,
                                  color: AppColors.cyan,
                                  size: 26,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: _FrostedPill(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.layers_outlined,
                          size: 13,
                          color: AppColors.cyan,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _modeLabel(state.fusionMode),
                          style: _pillStyle,
                        ),
                      ],
                    ),
                  ),
                ),
                const Positioned(
                  top: 14,
                  right: 12,
                  child: Text(
                    '© OpenStreetMap · Stadia Maps',
                    style: TextStyle(
                      fontSize: 9,
                      color: Color(0x99000000),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Positioned(
                  bottom: widget.bottomInset,
                  left: 12,
                  right: 12,
                  child: _FrostedPill(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            '${formatLatitude(state.latitude)}, '
                            '${formatLongitude(state.longitude)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _pillStyle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          margin == null ? 'No fix yet' : '±${margin.round()} m',
                          style: TextStyle(
                            color: margin == null
                                ? AppColors.textSecondary
                                : FusionConfidenceBadge.colorFor(
                                    state.confidence,
                                  ),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static final TextStyle _pillStyle = TextStyle(
    color: AppColors.textPrimary.withValues(alpha: 0.85),
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );
}

/// Floating map chip. Deliberately a near-opaque surface with a soft shadow
/// rather than a live backdrop blur: blurring a moving map every frame is
/// costly on low-power GPUs, and the look is nearly identical.
class _FrostedPill extends StatelessWidget {
  final Widget child;

  const _FrostedPill({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.control),
        boxShadow: AppShadow.card,
      ),
      child: child,
    );
  }
}

/// Turns the bundled daylight OSM raster into a dark-mode map.
///
/// The tiles ship as one light set, so dark mode inverts them and pulls the
/// saturation and brightness down — the usual treatment for raster basemaps,
/// and far smaller than shipping a second tile pyramid. In light mode the
/// child is returned untouched, so there is no filter layer to composite.
class _DarkMapFilter extends StatelessWidget {
  const _DarkMapFilter({required this.child});

  final Widget child;

  /// invert -> desaturate (45%) -> scale brightness to 88%.
  static const ColorFilter _dark = ColorFilter.matrix(<double>[
    -0.4989, -0.3462, -0.0349, 0, 224.4, //
    -0.1029, -0.7422, -0.0349, 0, 224.4, //
    -0.1029, -0.3462, -0.4309, 0, 224.4, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    if (!AppColors.isDark) return child;
    return ColorFiltered(colorFilter: _dark, child: child);
  }
}
