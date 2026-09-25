import 'package:flutter/material.dart';

import '../../../../core/nav/sensors/parking_level.dart';
import '../../../../core/theme/app_theme.dart';
import 'status_strip.dart';

/// The car-park floor the barometer counts from where GNSS was lost.
class ParkingLevelCard extends StatelessWidget {
  const ParkingLevelCard({super.key, required this.level});

  final ParkingLevel level;

  @override
  Widget build(BuildContext context) {
    final h = level.heightM;
    final where = h < 0 ? 'below' : 'above';
    return StatusStrip(
      icon: Icons.local_parking_rounded,
      color: AppColors.cyan,
      headline: 'Parking level ${level.label}',
      detail: '${h.abs().toStringAsFixed(1)} m $where where GNSS was lost · '
          'barometer',
    );
  }
}
