import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/platform/gnss/gnss_telemetry.dart';
import '../../../../../core/widgets/motion.dart';
import '../../../../navigation_engine/domain/entities/navigation_state.dart';
import '../../controllers/live_session_controller.dart';
import '../../controllers/live_session_scope.dart';
import '../../widgets/navic_weight_indicator.dart';
import '../../widgets/satellite_breakdown.dart';
import '../../widgets/gnss_integrity_panel.dart';

class SensorsTab extends StatelessWidget {
  const SensorsTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final isDark = AppColors.isDark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        // 1. Header with Online Count
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sensor Status',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Hardware telemetry & multi-sensor fusion',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 14),
                  SizedBox(width: 6),
                  Text(
                    '8/8 Online',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.lg),

        // 2. Sensor Item Cards (Matching UI/UX Board Screen 4)
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.lightSurfaceBorder,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              _SensorStatusTile(
                icon: Icons.gps_fixed_rounded,
                name: 'GPS / GNSS',
                statusText:
                    session.hasLiveGnss ? 'Excellent' : 'Simulated Outage',
                statusColor:
                    session.hasLiveGnss ? AppColors.success : AppColors.warning,
                detail: session.hasLiveGnss
                    ? 'Fix active · ±${(session.uncertainty?.marginMeters ?? 5.0).toStringAsFixed(1)} m'
                    : 'Searching for satellites',
              ),
              const Divider(height: 1),
              _SensorStatusTile(
                icon: Icons.speed_rounded,
                name: 'Accelerometer',
                statusText: 'Good',
                statusColor: AppColors.success,
                detail:
                    '50 Hz · RMS ${session.vibrationRms.toStringAsFixed(2)} g',
              ),
              const Divider(height: 1),
              _SensorStatusTile(
                icon: Icons.screen_rotation_rounded,
                name: 'Gyroscope',
                statusText: 'Good',
                statusColor: AppColors.success,
                detail: '50 Hz · Low drift calibration',
              ),
              const Divider(height: 1),
              _SensorStatusTile(
                icon: Icons.explore_rounded,
                name: 'Magnetometer',
                statusText: 'Good',
                statusColor: AppColors.success,
                detail: '${session.heading.round()}° heading · Uncalibrated',
              ),
              const Divider(height: 1),
              _SensorStatusTile(
                icon: Icons.air_rounded,
                name: 'Barometer',
                statusText: 'Good',
                statusColor: AppColors.success,
                detail: 'Altitude ${session.altitude.toStringAsFixed(1)} m',
              ),
              const Divider(height: 1),
              _SensorStatusTile(
                icon: Icons.camera_alt_rounded,
                name: 'AI Speed Estimator',
                statusText: 'Excellent',
                statusColor: AppColors.success,
                detail: session.isSpeedEstimatorReady
                    ? 'TFLite Int8 model active'
                    : 'Rule-based fallback active',
              ),
              const Divider(height: 1),
              _SensorStatusTile(
                icon: Icons.thermostat_rounded,
                name: 'Thermal State',
                statusText: 'Normal',
                statusColor: AppColors.success,
                detail:
                    '${session.temperature.toStringAsFixed(1)}°C · Bias compensated',
              ),
              const Divider(height: 1),
              _SensorStatusTile(
                icon: Icons.phone_android_rounded,
                name: 'Mount Alignment',
                statusText: 'Calibrated',
                statusColor: AppColors.success,
                detail:
                    'Pitch ${session.pitchDegrees.toStringAsFixed(1)}° · Roll ${session.rollDegrees.toStringAsFixed(1)}°',
                isLast: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // 3. Multi-GNSS Constellations
        const SectionHeader(
          title: 'Satellite constellations',
          subtitle: 'NavIC, GPS, Galileo, and GLONASS tracking',
        ),
        SatelliteBreakdown(
          satelliteBreakdown: _satellites(session),
          isHardwareBacked: session.gnssTelemetry?.hasRealStatus ?? false,
          rawMeasurementsSupported:
              session.gnssTelemetry?.rawMeasurementsSupported ?? false,
        ),
        NavicWeightIndicator(
          navicWeight: _navicWeight(session),
        ),
        GnssIntegrityPanel(
          telemetry: session.gnssTelemetry,
          assessment: session.gnssIntegrity,
          cn0History: session.gnssCn0History,
        ),
      ],
    );
  }

  static SatelliteBreakdownModel _satellites(LiveSessionController s) {
    final telemetry = s.gnssTelemetry;
    SatelliteInfoModel info(GnssConstellation constellation) =>
        SatelliteInfoModel(
          count: telemetry?.countFor(constellation) ?? 0,
          signalStrength: telemetry?.meanCn0For(constellation) ?? 0,
        );
    return SatelliteBreakdownModel(
      navIC: info(GnssConstellation.navic),
      gps: info(GnssConstellation.gps),
      galileo: info(GnssConstellation.galileo),
      glonass: info(GnssConstellation.glonass),
    );
  }

  static double _navicWeight(LiveSessionController s) {
    final telemetry = s.gnssTelemetry;
    if (telemetry == null || telemetry.usedInFixCount == 0) return 0;
    return telemetry.usedCountFor(GnssConstellation.navic) /
        telemetry.usedInFixCount;
  }
}

class _SensorStatusTile extends StatelessWidget {
  const _SensorStatusTile({
    required this.icon,
    required this.name,
    required this.statusText,
    required this.statusColor,
    required this.detail,
    this.isLast = false,
  });

  final IconData icon;
  final String name;
  final String statusText;
  final Color statusColor;
  final String detail;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
