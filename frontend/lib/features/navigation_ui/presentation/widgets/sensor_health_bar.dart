import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';

class SensorHealthBar extends StatelessWidget {
  final SensorHealthModel sensorHealth;

  const SensorHealthBar({Key? key, required this.sensorHealth})
      : super(key: key);

  Widget _buildSensorPill(String name, bool isHealthy, {bool isUnsupported = false}) {
    final color = isUnsupported
        ? AppColors.textMuted
        : (isHealthy ? AppColors.healthy : AppColors.error);
    final statusText = isUnsupported ? 'N/A' : (isHealthy ? 'OK' : 'OFF');

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Column(
          children: [
            Text(
              name,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              statusText,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'HW SENSORS',
                  style: Theme.of(context).textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  sensorHealth.barometer ? 'Baro OK' : 'Baro: N/A (GPS alt)',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildSensorPill('Accel', sensorHealth.accelerometer),
              const SizedBox(width: 4),
              _buildSensorPill('Gyro', sensorHealth.gyroscope),
              const SizedBox(width: 4),
              _buildSensorPill('Mag', sensorHealth.magnetometer),
              const SizedBox(width: 4),
              _buildSensorPill('GNSS', sensorHealth.gnss),
              const SizedBox(width: 4),
              _buildSensorPill('Baro', sensorHealth.barometer, isUnsupported: !sensorHealth.barometer),
            ],
          ),
        ],
      ),
    );
  }
}
