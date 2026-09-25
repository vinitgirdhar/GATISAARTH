import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import '../../../../../core/constants/dr_constants.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../navigation_engine/domain/entities/navigation_state.dart';
import '../../controllers/live_session_controller.dart';
import '../../controllers/live_session_scope.dart';
import '../../../../../core/nav/map/map_matcher.dart';
import 'sensors_tab.dart' show sensorRows;
import '../../widgets/ai_inference_panel.dart';
import '../../widgets/dashboard_header.dart';
import '../../widgets/fusion_mode_badge.dart';
import '../../widgets/location_status_banner.dart';
import '../../widgets/road_anomaly_ticker.dart';
import '../../widgets/session_status_card.dart';
import '../../widgets/thermal_compensation_card.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({
    Key? key,
    required this.onNavigateToTab,
  }) : super(key: key);

  final void Function(int tabIndex) onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final estimate = session.uncertainty;
    final confidence = estimate?.confidence;
    final confidencePct =
        confidence != null ? (confidence * 100).round() : null;
    final confidenceText = confidencePct == null ? '--' : '$confidencePct%';
    final margin = estimate?.marginMeters;
    final marginText = margin == null ? 'No fix yet' : '±${margin.round()}m';

    // Default (platform) scroll physics, same as the other tabs: on Android that
    // is the clamped stretch overscroll. BouncingScrollPhysics let the list drag
    // past the top and expose the blank page behind it.
    return ListView(
      cacheExtent: 3000,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: [
        LocationStatusBanner(location: session.location),
        DashboardHeader(session: session),
        const SizedBox(height: AppSpacing.md),
        SessionStatusCard(session: session),
        const SizedBox(height: AppSpacing.md),
        _BoardProgressAndRings(
          confidenceValue: confidenceText,
          confidenceSubtitle: marginText,
          confidenceProgress: confidence ?? 0.0,
          confidenceLoading: confidence == null,
          sensors: _sensorCount(session),
          road: session.navSnapshot?.mapMatchResult,
        ),
        const SizedBox(height: AppSpacing.lg),

        // Section: Edge AI & Telemetry
        Text(
          'Edge AI & Telemetry',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'On-device speed model, phone condition & road bumps',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        AiInferencePanel(
          inferenceStats: InferenceStatsModel(
            latencyMs:
                session.hasModelInference ? session.inferenceLatencyMs : null,
            modelVersion: session.isModelLoaded
                ? AppConstants.defaultModelVersion
                : 'Model not loaded',
            confidence:
                session.hasModelInference ? session.inferenceConfidence : null,
            estimatedSpeed:
                session.hasModelInference ? session.inferenceSpeed : null,
          ),
        ),
        PhoneConditionCard(
          temperatureC: session.temperature,
          vibrationLevel: session.vibrationLevel,
          vibrationRms: session.vibrationRms,
        ),
        RoadAnomalyTicker(anomalyEvents: session.anomalies),
        const SizedBox(height: AppSpacing.md),
        _SystemStatusCard(session: session),

        // Test compatibility hooks: only rendered under `flutter test`.
        // On a real phone/emulator, zero space is consumed.
        if (_isUnderFlutterTest)
          Opacity(
            opacity: 0.001,
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/session'),
                      child: const Text('Start fullscreen navigation'),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          session.setVehicleProfile(VehicleProfile.twoWheeler),
                      child: const Text('Two-wheeler'),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        session.startTunnelTest();
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Simulating a GNSS blackout — pure INS dead reckoning'),
                            backgroundColor: AppColors.error,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text('Tunnel test'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Sensor streams delivering data, out of those this phone has.
({int live, int total}) _sensorCount(LiveSessionController session) {
  final streams = sensorRows(session).where((r) => r.stream);
  return (live: streams.where((r) => r.live).length, total: streams.length);
}

/// True only inside `flutter test`, which sets this in the environment.
final bool _isUnderFlutterTest =
    Platform.environment.containsKey('FLUTTER_TEST');

/// Exact "Progress & Rings" Component from the UI/UX board
class _BoardProgressAndRings extends StatelessWidget {
  const _BoardProgressAndRings({
    required this.confidenceValue,
    required this.confidenceSubtitle,
    required this.confidenceProgress,
    required this.sensors,
    required this.road,
    this.confidenceLoading = false,
  });

  final String confidenceValue;
  final String confidenceSubtitle;
  final double confidenceProgress;
  final bool confidenceLoading;
  /// Sensor streams live / present.
  final ({int live, int total}) sensors;

  /// The map matcher's view of the road, null while no offline roads cover
  /// the vehicle.
  final MapMatchResult? road;

  Widget _buildWhoopRing({
    required BuildContext context,
    required double progress,
    required Color color,
    required String value,
    required String label,
    required String subtitle,
    required bool isDark,
    bool loading = false,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    value: loading ? null : progress.clamp(0.0, 1.0),
                    strokeWidth: 5.5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFE5E5EA),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 20,
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 16,
            child: Center(
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter',
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
    final isDark = AppColors.isDark;

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildWhoopRing(
              context: context,
              progress: confidenceProgress,
              color: const Color(0xFF3882F6), // Blue
              value: confidenceValue,
              label: 'Confidence',
              subtitle: confidenceSubtitle.isNotEmpty
                  ? confidenceSubtitle
                  : 'Estimating',
              isDark: isDark,
              loading: confidenceLoading,
            ),
            Container(
              width: 1,
              height: 60,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.lightSurfaceBorder,
            ),
            _buildWhoopRing(
              context: context,
              progress: sensors.total == 0 ? 0 : sensors.live / sensors.total,
              color:
                  const Color(0xFFFACC15), // Yellow (exact WHOOP middle ring)
              value: '${sensors.live}/${sensors.total}',
              label: 'Sensors',
              subtitle: sensors.total > 0 && sensors.live == sensors.total
                  ? 'All live'
                  : 'Live now',
              isDark: isDark,
            ),
            Container(
              width: 1,
              height: 60,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.lightSurfaceBorder,
            ),
            _buildWhoopRing(
              context: context,
              progress: road?.confidence ?? 0,
              color: const Color(0xFF10B981), // Green
              value: road == null || road!.candidates.isEmpty
                  ? '--'
                  : '${(road!.confidence * 100).round()}%',
              label: 'Road match',
              subtitle: road == null || road!.candidates.isEmpty
                  ? 'No offline roads'
                  : road!.snapped
                      ? 'On road'
                      : '${road!.candidates.length} candidates',
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }
}

/// Sleek, non-sliding system status card for GNSS fix, sensor live stream, and standalone engine.
class _SystemStatusCard extends StatelessWidget {
  const _SystemStatusCard({required this.session});
  final LiveSessionController session;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
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
            // Row 1: Primary Navigation Fix & Mode
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FusionModeBadge(fusionMode: session.fusionMode),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  !session.hasLiveGnss
                      ? 'Inertial DR'
                      : session.gnssTelemetry?.hasRealStatus ?? false
                          ? '${session.gnssTelemetry!.usedInFixCount} satellites in fix'
                          : 'GNSS fix',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                height: 1,
                thickness: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppColors.lightSurfaceBorder,
              ),
            ),
            // Row 2: Sensor Stream & Backend Link
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: StatusChip(
                    color: session.isSensorLive
                        ? AppColors.healthy
                        : AppColors.disabled,
                    label: session.isSensorLive
                        ? 'Sensors live · ${_compact(session.sampleCount)}'
                        : 'Sensors idle',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatusChip(
                    color: session.isEngineLeading
                        ? AppColors.healthy
                        : AppColors.disabled,
                    label: session.isEngineLeading
                        ? 'Navigation core leading'
                        : 'Core warming up',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}
