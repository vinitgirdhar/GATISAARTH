import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/standard_card.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';

/// IMU temperature / gyro-bias correction and live road-vibration level.
class ThermalCompensationCard extends StatelessWidget {
  final ThermalStateModel thermalState;
  final String vibrationLevel;
  final double vibrationRms;

  const ThermalCompensationCard({
    Key? key,
    required this.thermalState,
    required this.vibrationLevel,
    required this.vibrationRms,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final labelColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return StandardCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IMU temperature · bias',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                    letterSpacing: 0.2,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${thermalState.temperature.toStringAsFixed(1)}°C · '
                    '${thermalState.biasCorrection.toStringAsFixed(4)}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 38,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: isDark
                ? const Color(0xFF334155).withValues(alpha: 0.6)
                : const Color(0xFFE2E8F0),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Road vibration',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                    letterSpacing: 0.2,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_sentence(vibrationLevel)} · '
                    '${vibrationRms.toStringAsFixed(2)} g',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _sentence(String upper) =>
      upper.isEmpty ? upper : upper[0] + upper.substring(1).toLowerCase();
}
