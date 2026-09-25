import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/nav/sensors/sensor_sample.dart';
import '../../../../../core/platform/gnss/gnss_telemetry.dart';
import '../../../../../core/platform/location/live_location_service.dart';
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
    final rows = sensorRows(session);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        // 1. Header with the live count
        Row(
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
                    'What each sensor is delivering right now',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _LiveCount(rows: rows),
          ],
        ),

        const SizedBox(height: AppSpacing.lg),

        // 2. One row per sensor, from measured data only
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
              for (final (i, r) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1),
                _SensorStatusTile(
                  icon: r.icon,
                  name: r.name,
                  statusText: r.status,
                  statusColor: r.color,
                  detail: r.detail,
                  isLast: i == rows.length - 1,
                ),
              ],
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
          satelliteBreakdown:
              SatelliteBreakdownModel.fromTelemetry(session.gnssTelemetry),
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

/// One row of the sensor list.
typedef SensorRow = ({
  IconData icon,
  String name,
  String status,
  Color color,
  String detail,
  bool stream,
  bool live,
});

/// Builds the sensor list from what the session has actually measured: the
/// core's per-sensor stream statistics and fault diagnoses, the GNSS state,
/// the model and the mount. No row says "Live" unless data says so.
List<SensorRow> sensorRows(LiveSessionController s) {
  final snap = s.navSnapshot;
  SensorRow imu(SensorType type, IconData icon, String name) {
    final stats = snap?.sensorStats[type];
    final diag = snap?.sensorFaults[type];
    if (stats == null || stats.received == 0) {
      return (
        icon: icon,
        name: name,
        status: 'Waiting',
        color: AppColors.textSecondary,
        detail: 'No samples yet',
        stream: true,
        live: false,
      );
    }
    if (diag != null && !diag.usable) {
      return (
        icon: icon,
        name: name,
        status: 'Fault',
        color: AppColors.error,
        detail: '${diag.fault.name} · ${diag.detail ?? 'not used by the core'}',
        stream: true,
        live: false,
      );
    }
    final hz = stats.effectiveHz;
    return (
      icon: icon,
      name: name,
      status: 'Live',
      color: AppColors.success,
      detail: '${hz == null ? '--' : hz.round()} Hz measured'
          '${stats.dropped > 0 ? ' · ${stats.dropped} dropped' : ''}',
      stream: true,
      live: true,
    );
  }

  final margin = s.uncertainty?.marginMeters;
  final SensorRow gnss = s.hasLiveGnss
      ? (
          icon: Icons.gps_fixed_rounded,
          name: 'GPS / GNSS',
          status: 'Live',
          color: AppColors.success,
          detail: 'Fix active · ±${margin?.toStringAsFixed(1) ?? '--'} m',
          stream: true,
          live: true,
        )
      : (
          icon: Icons.gps_off_rounded,
          name: 'GPS / GNSS',
          status: s.isSimulatingTunnel
              ? 'Test outage'
              : switch (s.gnssStatus) {
                  LocationStatus.serviceOff => 'Location off',
                  LocationStatus.permissionDenied ||
                  LocationStatus.permissionBlocked =>
                    'No permission',
                  LocationStatus.stale => 'Lost',
                  _ => 'Searching',
                },
          color: AppColors.warning,
          detail: s.inOutage ? 'Dead reckoning' : 'Waiting for satellites',
          stream: true,
          live: false,
        );

  final pressure = s.pressureHpa;
  final SensorRow baro = pressure.isNaN
      ? (
          icon: Icons.air_rounded,
          name: 'Barometer',
          status: 'Not present',
          color: AppColors.textSecondary,
          detail: 'No pressure reading from this phone',
          stream: false,
          live: false,
        )
      : (
          icon: Icons.air_rounded,
          name: 'Barometer',
          status: 'Live',
          color: AppColors.success,
          detail: '${pressure.toStringAsFixed(1)} hPa',
          stream: true,
          live: true,
        );

  final t = s.temperature;
  final SensorRow thermal = (
    icon: Icons.thermostat_rounded,
    name: 'Thermal state',
    status: t == null ? 'Unknown' : (t >= 45 ? 'Hot' : 'Normal'),
    color: t == null
        ? AppColors.textSecondary
        : (t >= 45 ? AppColors.warning : AppColors.success),
    detail: t == null
        ? 'Temperature not reported'
        : '${t.toStringAsFixed(1)}°C · phone battery',
    stream: false,
    live: false,
  );

  return [
    gnss,
    imu(SensorType.accelerometer, Icons.speed_rounded, 'Accelerometer'),
    imu(SensorType.gyroscope, Icons.screen_rotation_rounded, 'Gyroscope'),
    imu(SensorType.magnetometer, Icons.explore_rounded, 'Magnetometer'),
    baro,
    (
      icon: Icons.memory_rounded,
      name: 'AI speed estimator',
      status: s.isSpeedEstimatorReady ? 'Loaded' : 'Fallback',
      color: s.isSpeedEstimatorReady ? AppColors.success : AppColors.warning,
      detail: s.isSpeedEstimatorReady
          ? 'TFLite FP32 model active'
          : 'Rule-based fallback active',
      stream: false,
      live: false,
    ),
    thermal,
    (
      icon: Icons.phone_android_rounded,
      name: 'Mount alignment',
      status: s.isMountCalibrated ? 'Calibrated' : 'Learning',
      color: s.isMountCalibrated ? AppColors.success : AppColors.warning,
      detail: s.isMountCalibrated
          ? 'Pitch ${s.pitchDegrees.toStringAsFixed(1)}° · '
              'Roll ${s.rollDegrees.toStringAsFixed(1)}°'
          : 'Drive straight, speed up and brake a few times',
      stream: false,
      live: false,
    ),
  ];
}

/// "3/4 live": sensor streams delivering data now, out of those present.
class _LiveCount extends StatelessWidget {
  const _LiveCount({required this.rows});

  final List<SensorRow> rows;

  @override
  Widget build(BuildContext context) {
    final streams = rows.where((r) => r.stream);
    final live = streams.where((r) => r.live).length;
    final all = streams.isNotEmpty && live == streams.length;
    final color = all ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(all ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            '$live/${streams.length} live',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
