import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
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
    final label = Theme.of(context).textTheme.labelSmall;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadow.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('IMU temperature · bias', style: label),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${thermalState.temperature.toStringAsFixed(1)}°C · '
                    '${thermalState.biasCorrection.toStringAsFixed(4)}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Road vibration', style: label),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_sentence(vibrationLevel)} · '
                    '${vibrationRms.toStringAsFixed(2)} g',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
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
