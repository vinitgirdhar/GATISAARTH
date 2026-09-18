import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class GnssSignalIndicator extends StatelessWidget {
  const GnssSignalIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.healthy.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Icon(Icons.gps_fixed, color: AppColors.healthy, size: 20),
    );
  }
}
