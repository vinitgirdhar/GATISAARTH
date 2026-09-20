import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../controllers/live_session_controller.dart';
import '../controllers/live_session_scope.dart';
import '../widgets/fusion_mode_badge.dart';
import '../widgets/location_status_banner.dart';
import '../widgets/navigation_map.dart';
import '../widgets/session_status_card.dart';
import '../widgets/telemetry_card.dart';

/// Fullscreen driver view. Like the dashboard it only observes the shared
/// [LiveSessionController]; leaving this screen stops nothing.
class NavigationScreen extends StatelessWidget {
  const NavigationScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final estimate = session.uncertainty;
    final mapHeight =
        (MediaQuery.sizeOf(context).height * 0.36).clamp(240.0, 420.0);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Live navigation')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FusionModeBadge(fusionMode: session.fusionMode),
            ),
            const SizedBox(height: AppSpacing.md),
            LocationStatusBanner(location: session.location),
            FadeSlideIn(
              child: SessionStatusCard(session: session, showAlignment: false),
            ),
            const SizedBox(height: AppSpacing.md),
            _ImuStrip(session: session),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: NavigationMap(
                navigationState: session.navigationState,
                marginMeters: estimate?.marginMeters,
                trail: session.trail.segments,
                height: mapHeight,
                // Inside a scrolling page a drag must scroll the page.
                gestures: MapGestures.zoomOnly,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TelemetryCard(
                  label: 'Live speed',
                  value: (session.speed * 3.6).toStringAsFixed(1),
                  unit: 'km/h',
                  subtitle: '${session.speed.toStringAsFixed(1)} m/s',
                  accentColor: AppColors.cyan,
                ),
                const SizedBox(width: AppSpacing.md),
                TelemetryCard(
                  label: 'Heading',
                  value: '${session.heading.round()}°',
                  unit: 'N',
                  subtitle: 'Magnetometer',
                  accentColor: AppColors.blue,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _ExitButton(onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}

/// Compact raw-sensor readout. Values are the real, smoothed IMU signals;
/// anything the phone cannot measure (e.g. no barometer) says so.
class _ImuStrip extends StatelessWidget {
  const _ImuStrip({required this.session});

  final LiveSessionController session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final pressure =
        s.pressureHpa.isNaN ? 'n/a' : '${s.pressureHpa.toStringAsFixed(1)} hPa';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadow.card,
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _stat('IMU', '${s.sampleCount} pkts', AppColors.cyan),
          _stat(
            'Model latency',
            s.hasModelInference ? '${s.inferenceLatencyMs} ms' : '--',
            AppColors.healthy,
          ),
          _stat('Baro', pressure, AppColors.warning),
          _stat(
            'Accel',
            '${s.accelX.toStringAsFixed(1)}, ${s.accelY.toStringAsFixed(1)}, '
                '${s.accelZ.toStringAsFixed(1)}',
            AppColors.textPrimary,
          ),
          _stat('Gyro', '${s.gyroZ.toStringAsFixed(2)} rad/s',
              AppColors.textPrimary),
          _stat(
            'Mag',
            '${s.magX.toStringAsFixed(0)}, ${s.magY.toStringAsFixed(0)}, '
                '${s.magZ.toStringAsFixed(0)} µT',
            AppColors.cyan,
          ),
          _stat('Temp', '${s.temperature.toStringAsFixed(1)}°C',
              AppColors.textPrimary),
          _stat(
            'Altitude',
            s.hasLiveGnss ? '${s.altitude.toStringAsFixed(0)} m' : '—',
            AppColors.textPrimary,
          ),
        ],
      ),
    );
  }

  static Widget _stat(String label, String value, Color color) => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _ExitButton extends StatelessWidget {
  const _ExitButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Exit live navigation',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              AppColors.error.withValues(alpha: 0.12),
              AppColors.surface,
            ),
            borderRadius: AppRadius.controlRadius,
            boxShadow: AppShadow.card,
          ),
          alignment: Alignment.center,
          child: Text(
            'Exit live navigation',
            style: TextStyle(
              color: AppColors.error,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
