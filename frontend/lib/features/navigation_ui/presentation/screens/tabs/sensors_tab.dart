import 'package:flutter/material.dart';
import '../../../../../core/constants/dr_constants.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/motion.dart';
import '../../../../navigation_engine/domain/entities/navigation_state.dart';
import '../../controllers/live_session_controller.dart';
import '../../controllers/live_session_scope.dart';
import '../../widgets/ai_inference_panel.dart';
import '../../widgets/engine_status_card.dart';
import '../../widgets/navic_weight_indicator.dart';
import '../../widgets/road_anomaly_ticker.dart';
import '../../widgets/satellite_breakdown.dart';
import '../../widgets/thermal_compensation_card.dart';

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
                color: AppColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.success.withOpacity(0.3),
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
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _SensorStatusTile(
                icon: Icons.gps_fixed_rounded,
                name: 'GPS / GNSS',
                statusText: session.hasLiveGnss ? 'Excellent' : 'Simulated Outage',
                statusColor: session.hasLiveGnss
                    ? AppColors.success
                    : AppColors.warning,
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
                detail: '${session.temperature.toStringAsFixed(1)}°C · Bias compensated',
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
        ),
        NavicWeightIndicator(
          navicWeight: _navicWeight(session),
        ),

        const SizedBox(height: AppSpacing.lg),

        // 4. Navigation Engine Status & Drive Recorder
        const SectionHeader(
          title: 'Navigation core',
          subtitle:
              'The filter takes over once it knows how the phone sits in the vehicle',
        ),
        EngineStatusCard(
          snapshot: session.navSnapshot,
          isLeading: session.isEngineLeading,
          blocker: session.engineHandoverBlocker,
          isRecording: session.isRecording,
          recordedDuration: session.recordedDuration,
          recordedLines: session.recordedLines,
          recordingError: session.recordingError,
          onStartRecording: () async {
            final path = await session.startRecording();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(path == null
                    ? 'Could not start recording — storage unavailable'
                    : 'Recording this drive. The screen stays on.'),
                backgroundColor:
                    path == null ? AppColors.error : AppColors.cyan,
                duration: const Duration(seconds: 3),
              ),
            );
          },
          onStopRecording: () async {
            final file = await session.stopRecording();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(file == null
                    ? 'Recording stopped'
                    : 'Saved ${file.name} (${file.sizeMb.toStringAsFixed(1)} MB)'),
                backgroundColor: AppColors.healthy,
                duration: const Duration(seconds: 3),
              ),
            );
          },
          onMarkEvent: () {
            session.markEvent('driver marker');
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Marked this moment in the log'),
                backgroundColor: AppColors.cyan,
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),

        const SizedBox(height: AppSpacing.lg),

        // 5. AI Inference & Thermal Compensation
        const SectionHeader(
          title: 'Edge AI & telemetry',
          subtitle:
              'On-device neural inference, thermal compensation & road conditions',
        ),
        AiInferencePanel(
          inferenceStats: InferenceStatsModel(
            latencyMs: session.hasModelInference
                ? session.inferenceLatencyMs
                : null,
            modelVersion: session.isModelLoaded
                ? AppConstants.defaultModelVersion
                : 'Model not loaded',
            confidence: session.hasModelInference
                ? session.inferenceConfidence
                : null,
            estimatedSpeed: session.hasModelInference
                ? session.inferenceSpeed
                : null,
          ),
        ),
        ThermalCompensationCard(
          thermalState: ThermalStateModel(
            temperature: session.temperature,
            biasCorrection: session.thermalBias,
          ),
          vibrationLevel: session.vibrationLevel,
          vibrationRms: session.vibrationRms,
        ),
        RoadAnomalyTicker(anomalyEvents: session.anomalies),
      ],
    );
  }

  static SatelliteBreakdownModel _satellites(LiveSessionController s) {
    if (!s.hasLiveGnss) {
      return const SatelliteBreakdownModel(
        navIC: SatelliteInfoModel(count: 4, signalStrength: 38.5),
        gps: SatelliteInfoModel(count: 0, signalStrength: 0.0),
        galileo: SatelliteInfoModel(count: 0, signalStrength: 0.0),
        glonass: SatelliteInfoModel(count: 0, signalStrength: 0.0),
      );
    }
    if (s.isSimulatingCanyon) {
      return const SatelliteBreakdownModel(
        navIC: SatelliteInfoModel(count: 4, signalStrength: 28.0),
        gps: SatelliteInfoModel(count: 2, signalStrength: 18.5),
        galileo: SatelliteInfoModel(count: 0, signalStrength: 0.0),
        glonass: SatelliteInfoModel(count: 0, signalStrength: 0.0),
      );
    }
    return const SatelliteBreakdownModel(
      navIC: SatelliteInfoModel(count: 7, signalStrength: 44.0),
      gps: SatelliteInfoModel(count: 9, signalStrength: 41.5),
      galileo: SatelliteInfoModel(count: 4, signalStrength: 32.0),
      glonass: SatelliteInfoModel(count: 5, signalStrength: 35.0),
    );
  }

  static double _navicWeight(LiveSessionController s) {
    if (!s.hasLiveGnss) return 0.55;
    return s.isSimulatingCanyon ? 0.35 : 0.65;
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
              color: AppColors.primary.withOpacity(0.1),
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
              color: statusColor.withOpacity(0.12),
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
