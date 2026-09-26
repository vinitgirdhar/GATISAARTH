import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../../core/nav/route/planned_route.dart';
import '../../../../core/platform/maps/offline_map_service.dart';
import '../../../../core/platform/maps/offline_tile_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../navigation_ui/presentation/widgets/basemap_layers.dart';

/// A static route preview: no vehicle, no camera-follow. The camera is fitted
/// once to the route's bounds — used by the planner's confirmation screen and
/// the picker is its own, separate plain map.
class RoutePreviewMap extends StatelessWidget {
  const RoutePreviewMap({super.key, required this.route, this.height = 220});

  final PlannedRoute route;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final service = OfflineMapsScope.maybeOf(context);
    final points = [
      for (var i = 0; i < route.pointCount; i++)
        LatLng(route.latAt(i), route.lonAt(i)),
    ];
    final bounds = LatLngBounds.fromPoints(points);
    final casing =
        dark ? const Color(0xCC1C1C1E) : Colors.white.withValues(alpha: 0.9);

    return ClipRRect(
      borderRadius: AppRadius.cardRadius,
      child: SizedBox(
        height: height,
        child: RepaintBoundary(
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(32),
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              Basemap(service: service, rasterProvider: BundledOfflineTileProvider(), dark: dark),
              PolylineLayer(polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 5,
                  borderStrokeWidth: 1.6,
                  borderColor: casing,
                  color: AppColors.primary,
                ),
              ]),
              MarkerLayer(markers: [
                Marker(
                  point: points.first,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.healthy,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
                Marker(
                  point: points.last,
                  width: 32,
                  height: 32,
                  alignment: Alignment.topCenter,
                  child: Icon(Icons.location_on_rounded,
                      color: AppColors.primary, size: 30),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
