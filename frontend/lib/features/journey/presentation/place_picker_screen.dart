import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/platform/maps/offline_map_service.dart';
import '../../../core/platform/maps/offline_tile_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/geo_format.dart';
import '../../navigation_ui/presentation/controllers/live_session_scope.dart';
import '../../navigation_ui/presentation/widgets/basemap_layers.dart';
import '../domain/journey.dart';

/// Full-map picker: a fixed centre pin over a draggable map. Confirming
/// returns a "Dropped pin" [JourneyPlace] via `Navigator.pop`.
class PlacePickerScreen extends StatefulWidget {
  const PlacePickerScreen({super.key, required this.pickingFrom});

  /// True picks a start point ("Set start"); false a destination
  /// ("Set destination").
  final bool pickingFrom;

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  final BundledOfflineTileProvider _raster = BundledOfflineTileProvider();

  // Delhi, until the session gives a real fix.
  LatLng _center = const LatLng(28.6139, 77.2090);
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final session = LiveSessionScope.of(context);
    _center = LatLng(session.latitude, session.longitude);
  }

  void _confirm() {
    Navigator.of(context).pop(JourneyPlace(
      name: 'Dropped pin',
      lat: _center.latitude,
      lon: _center.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final service = OfflineMapsScope.maybeOf(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickingFrom ? 'Choose start' : 'Choose destination'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onPositionChanged: (position, hasGesture) {
                setState(() => _center = position.center);
              },
            ),
            children: [
              Basemap(service: service, rasterProvider: _raster, dark: dark),
            ],
          ),
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 32),
                child: Icon(Icons.location_on_rounded,
                    size: 44, color: AppColors.primary),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.94),
                      borderRadius: AppRadius.pillRadius,
                      boxShadow: AppShadow.card,
                    ),
                    child: Text(
                      formatCoordinates(_center.latitude, _center.longitude),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _confirm,
                      child: Text(
                        widget.pickingFrom ? 'Set start' : 'Set destination',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
