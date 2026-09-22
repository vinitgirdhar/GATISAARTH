import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/standard_card.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';

class SatelliteBreakdown extends StatelessWidget {
  final SatelliteBreakdownModel satelliteBreakdown;
  final bool isHardwareBacked;
  final bool rawMeasurementsSupported;

  const SatelliteBreakdown({
    Key? key,
    required this.satelliteBreakdown,
    this.isHardwareBacked = false,
    this.rawMeasurementsSupported = false,
  }) : super(key: key);

  Widget _buildConstellationRow({
    required String name,
    required SatelliteInfoModel info,
    required Color color,
    required bool isDark,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    name,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: color.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${info.count} sats • ${info.signalStrength.toStringAsFixed(1)} dBHz',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: isDark
                ? const Color(0xFF334155).withValues(alpha: 0.5)
                : const Color(0xFFE2E8F0),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final totalSats = satelliteBreakdown.navIC.count +
        satelliteBreakdown.gps.count +
        satelliteBreakdown.galileo.count +
        satelliteBreakdown.glonass.count;

    return StandardCard(
      titleText: 'MULTI-GNSS CONSTELLATION RECEPTION',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Text(
          '$totalSats Sats Active',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
            fontFamily: 'Inter',
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isHardwareBacked
                ? rawMeasurementsSupported
                    ? 'Receiver-backed · raw measurements available'
                    : 'Receiver-backed · status measurements only'
                : 'Waiting for Android GNSS status',
            style: TextStyle(
              color: isHardwareBacked
                  ? AppColors.success
                  : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          _buildConstellationRow(
            name: 'NavIC (IRNSS)',
            info: satelliteBreakdown.navIC,
            color: AppColors.navIC,
            isDark: isDark,
          ),
          _buildConstellationRow(
            name: 'GPS (USA)',
            info: satelliteBreakdown.gps,
            color: AppColors.gps,
            isDark: isDark,
          ),
          _buildConstellationRow(
            name: 'Galileo (EU)',
            info: satelliteBreakdown.galileo,
            color: AppColors.galileo,
            isDark: isDark,
          ),
          _buildConstellationRow(
            name: 'GLONASS (RU)',
            info: satelliteBreakdown.glonass,
            color: AppColors.glonass,
            isDark: isDark,
            isLast: true,
          ),
        ],
      ),
    );
  }
}
