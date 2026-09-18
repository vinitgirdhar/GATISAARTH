import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';

class SatelliteBreakdown extends StatelessWidget {
  final SatelliteBreakdownModel satelliteBreakdown;

  const SatelliteBreakdown({Key? key, required this.satelliteBreakdown})
      : super(key: key);

  Widget _buildConstellationRow(
      String name, SatelliteInfoModel info, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(name,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${info.count} sats • ${info.signalStrength.toStringAsFixed(1)} dBHz',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MULTI-GNSS CONSTELLATION RECEPTION',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          _buildConstellationRow(
              'NavIC (IRNSS)', satelliteBreakdown.navIC, AppColors.navIC),
          _buildConstellationRow(
              'GPS (USA)', satelliteBreakdown.gps, AppColors.gps),
          _buildConstellationRow(
              'Galileo (EU)', satelliteBreakdown.galileo, AppColors.galileo),
          _buildConstellationRow(
              'GLONASS (RU)', satelliteBreakdown.glonass, AppColors.glonass),
        ],
      ),
    );
  }
}
