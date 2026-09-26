import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../../core/platform/maps/offline_map_service.dart';
import '../../../../core/platform/maps/offline_tile_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../navigation_ui/presentation/controllers/live_session_scope.dart';
import '../../../navigation_ui/presentation/widgets/basemap_layers.dart';
import '../../../navigation_ui/presentation/widgets/vehicle_puck.dart';

/// Full-screen map behind the journey planner, the way a maps app shows the
/// area around you while you type a destination: centred on the vehicle once,
/// then left for the user to pan (it does not chase the position).
class PlannerBackdropMap extends StatefulWidget {
  const PlannerBackdropMap({super.key});

  @override
  State<PlannerBackdropMap> createState() => _PlannerBackdropMapState();
}

class _PlannerBackdropMapState extends State<PlannerBackdropMap> {
  final BundledOfflineTileProvider _raster = BundledOfflineTileProvider();

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final here = LatLng(session.latitude, session.longitude);
    final hasFix = session.uncertainty != null;
    final dark = AppColors.isDark;
    return FlutterMap(
      options: MapOptions(
        initialCenter: here,
        initialZoom: 15,
        backgroundColor: BasemapThemes.loadingColor(dark: dark),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        Basemap(
          service: OfflineMapsScope.maybeOf(context),
          rasterProvider: _raster,
          dark: dark,
        ),
        if (hasFix)
          MarkerLayer(markers: [
            Marker(
              point: here,
              width: VehiclePuck.extent,
              height: VehiclePuck.extent,
              child: IgnorePointer(
                child: VehiclePuck(
                  color: session.inOutage
                      ? AppColors.deadReckoning
                      : AppColors.primary,
                  headingDegrees: session.heading,
                  estimated: session.inOutage,
                ),
              ),
            ),
          ]),
      ],
    );
  }
}
