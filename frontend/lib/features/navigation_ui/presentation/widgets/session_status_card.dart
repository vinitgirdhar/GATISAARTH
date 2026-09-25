import 'package:flutter/material.dart';

import '../../../../core/platform/location/live_location_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/live_session_controller.dart';

/// One card that states, in plain words, what the positioning engine is doing
/// right now and why — derived from the real session state, never from a
/// demo switch alone.
class SessionStatusCard extends StatelessWidget {
  const SessionStatusCard({
    super.key,
    required this.session,
    this.showAlignment = true,
  });

  final LiveSessionController session;
  final bool showAlignment;

  @override
  Widget build(BuildContext context) {
    final view = _viewFor(session);
    final isDark = AppColors.isDark;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: view.alert
            ? Color.alphaBlend(
                view.color.withValues(alpha: 0.08),
                AppColors.surface,
              )
            : AppColors.surface,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: view.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(view.icon, color: view.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: view.alert
                            ? view.color
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      view.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showAlignment) ...[
            Divider(
              color: AppColors.surfaceBorder.withValues(alpha: 0.7),
              height: 24,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Pitch ${session.pitchDegrees.toStringAsFixed(1)}° · '
                    'Roll ${session.rollDegrees.toStringAsFixed(1)}°',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // The core's phone-to-vehicle alignment, not just the tilt:
                // the same test the Sensors tab and the hand-over use.
                Text(
                  session.isMountCalibrated
                      ? 'Mount calibrated'
                      : 'Mount learning…',
                  style: TextStyle(
                    color: session.isMountCalibrated
                        ? AppColors.healthy
                        : AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static _StatusView _viewFor(LiveSessionController s) {
    final margin = s.uncertainty?.marginMeters.round();
    final marginText = margin == null ? '' : ' · ±$margin m';
    final vibration = _sentence(s.vibrationLevel);
    final outage = 'T+${s.outageElapsed.inSeconds}s · '
        '${s.outageDistanceMeters.toStringAsFixed(1)} m travelled$marginText';

    if (s.isSimulatingTunnel) {
      return _StatusView(
        icon: Icons.gps_off_rounded,
        color: AppColors.error,
        alert: true,
        title: 'Outage active · pure INS',
        subtitle: 'AI dead reckoning · $outage',
      );
    }
    if (s.isSimulatingCanyon) {
      return _StatusView(
        icon: Icons.location_city_rounded,
        color: AppColors.warning,
        alert: true,
        title: 'Urban canyon · weak GNSS',
        subtitle: 'Fusing IMU + NavIC$marginText · Vibration $vibration',
      );
    }
    switch (s.gnssStatus) {
      case LocationStatus.live:
        return _StatusView(
          icon: Icons.sensors_rounded,
          color: AppColors.cyan,
          alert: false,
          title: 'Nominal GNSS lock',
          subtitle: 'Real-time sensors · Vibration $vibration '
              '(${s.vibrationRms.toStringAsFixed(2)} g) · '
              '${s.temperature?.toStringAsFixed(1) ?? '--'}°C',
        );
      case LocationStatus.stale:
        return _StatusView(
          icon: Icons.gps_off_rounded,
          color: AppColors.error,
          alert: true,
          title: 'GNSS signal lost',
          subtitle: 'Dead reckoning · $outage',
        );
      case LocationStatus.searching:
        return const _StatusView(
          icon: Icons.satellite_alt_rounded,
          color: AppColors.warning,
          alert: true,
          title: 'Searching for GNSS…',
          subtitle: 'Acquiring satellites. Inertial sensors keep tracking '
              'in the meantime.',
        );
      case LocationStatus.serviceOff:
        return const _StatusView(
          icon: Icons.location_off_rounded,
          color: AppColors.error,
          alert: true,
          title: 'Location is off',
          subtitle: 'Running on inertial sensors only.',
        );
      case LocationStatus.permissionDenied:
      case LocationStatus.permissionBlocked:
        return const _StatusView(
          icon: Icons.lock_outline_rounded,
          color: AppColors.warning,
          alert: true,
          title: 'No location permission',
          subtitle: 'Running on inertial sensors only.',
        );
      case LocationStatus.initializing:
        return _StatusView(
          icon: Icons.hourglass_top_rounded,
          color: AppColors.textSecondary,
          alert: false,
          title: 'Starting up…',
          subtitle: 'Checking location and sensors.',
        );
    }
  }

  static String _sentence(String upper) =>
      upper.isEmpty ? upper : upper[0] + upper.substring(1).toLowerCase();
}

class _StatusView {
  const _StatusView({
    required this.icon,
    required this.color,
    required this.alert,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final bool alert;
  final String title;
  final String subtitle;
}
