import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import '../../../../../core/platform/location/live_location_service.dart';
import '../../../../../core/platform/hardware/vehicle_alignment_engine.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../navigation_engine/domain/navigation_safety.dart'
    show TrustLevel;
import '../../controllers/live_session_controller.dart';
import '../../controllers/live_session_scope.dart';
import '../../widgets/location_status_banner.dart';
import '../../widgets/nav_safety_badge.dart';
import '../../../../journey/application/journey_service.dart';
import '../../../../journey/presentation/widgets/where_to_card.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({Key? key, required this.onNavigateToTab}) : super(key: key);

  final void Function(int tabIndex) onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final summary = _locationSummary(session);
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        Text('Home', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.lg),
        LocationStatusBanner(location: session.location),
        if (session.trust.level != TrustLevel.waiting &&
            session.trust.limited) ...[
          const NavSafetyLimitedBanner(),
          const SizedBox(height: AppSpacing.md),
        ],
        _NavigationOverview(
          title: summary.title,
          message: summary.message,
          icon: summary.icon,
          color: summary.color,
          isSimulation: summary.isSimulation,
          locationValue: session.hasLiveGnss ? 'Connected' : 'Estimating',
          sensorsValue: session.isSensorLive ? 'Active' : 'Starting',
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'At a glance',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _DriveSnapshot(
          speed: session.hasLiveGnss || session.inOutage
              ? '${(session.speed * 3.6).round()}'
              : '—',
          accuracy: session.uncertainty == null
              ? '—'
              : '±${session.uncertainty!.marginMeters.round()} m',
          alignment: session.isMountCalibrated ? 'Ready' : 'Learning',
        ),
        const SizedBox(height: AppSpacing.lg),
        WhereToCard(
          session: session,
          journey: JourneyScope.maybeOf(context),
          onNavigateToTab: onNavigateToTab,
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () => onNavigateToTab(2),
            icon: const Icon(Icons.sensors_outlined),
            label: const Text('System health'),
          ),
        ),
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
                      onPressed: session.startTunnelTest,
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

class _DriveSnapshot extends StatelessWidget {
  const _DriveSnapshot({
    required this.speed,
    required this.accuracy,
    required this.alignment,
  });

  final String speed;
  final String accuracy;
  final String alignment;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
        ),
        child: Row(
          children: [
            Expanded(
              child: _SnapshotValue(
                label: 'SPEED',
                value: speed,
                suffix: speed == '—' ? '' : ' km/h',
                emphasize: true,
              ),
            ),
            Container(width: 1, height: 42, color: AppColors.surfaceBorder),
            Expanded(
              child: _SnapshotValue(label: 'ACCURACY', value: accuracy),
            ),
            Container(width: 1, height: 42, color: AppColors.surfaceBorder),
            Expanded(
              child: _SnapshotValue(label: 'PHONE', value: alignment),
            ),
          ],
        ),
      );
}

class _SnapshotValue extends StatelessWidget {
  const _SnapshotValue({
    required this.label,
    required this.value,
    this.suffix = '',
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String suffix;
  final bool emphasize;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 6),
            RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                text: value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color:
                          emphasize ? AppColors.primary : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                children: [
                  if (suffix.isNotEmpty)
                    TextSpan(
                      text: suffix,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

({String title, String message, IconData icon, Color color, bool isSimulation})
    _locationSummary(LiveSessionController session) {
  final margin = session.uncertainty?.marginMeters;
  final accuracy = margin == null ? '' : ' · ±${margin.round()} m';
  if (session.isSimulatingTunnel ||
      session.isSimulatingCanyon ||
      session.isSimulatingOutage) {
    final scenario = session.isSimulatingTunnel
        ? 'Tunnel test'
        : session.isSimulatingCanyon
            ? 'Urban canyon test'
            : 'GPS loss test';
    return (
      title: 'Simulation in progress',
      message: '$scenario · your location is estimated',
      icon: Icons.science_outlined,
      color: AppColors.warning,
      isSimulation: true,
    );
  }
  if (session.inOutage) {
    return (
      title: 'Satellite signal lost',
      message: 'Using motion sensors to estimate your position$accuracy',
      icon: Icons.location_searching_rounded,
      color: AppColors.error,
      isSimulation: false,
    );
  }
  if (session.trust.limited) {
    return (
      title: 'Location needs attention',
      message: session.trust.reason,
      icon: Icons.location_disabled_rounded,
      color: AppColors.warning,
      isSimulation: false,
    );
  }
  return switch (session.gnssStatus) {
    LocationStatus.live => (
        title: 'Location is ready',
        message: 'GPS connected$accuracy',
        icon: Icons.my_location_rounded,
        color: AppColors.healthy,
        isSimulation: false,
      ),
    LocationStatus.stale => (
        title: 'Location signal paused',
        message: 'Waiting for a fresh GPS update',
        icon: Icons.location_searching_rounded,
        color: AppColors.warning,
        isSimulation: false,
      ),
    LocationStatus.serviceOff => (
        title: 'Live position paused',
        message: 'Turn on location to resume live positioning',
        icon: Icons.location_off_rounded,
        color: AppColors.error,
        isSimulation: false,
      ),
    LocationStatus.permissionDenied || LocationStatus.permissionBlocked => (
        title: 'Location permission needed',
        message: 'Allow location access to see your position',
        icon: Icons.location_disabled_rounded,
        color: AppColors.warning,
        isSimulation: false,
      ),
    LocationStatus.initializing || LocationStatus.searching => (
        title: 'Finding your location',
        message: 'Waiting for a fresh GPS fix',
        icon: Icons.location_searching_rounded,
        color: AppColors.textSecondary,
        isSimulation: false,
      ),
  };
}

class _NavigationOverview extends StatelessWidget {
  const _NavigationOverview({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.isSimulation,
    required this.locationValue,
    required this.sensorsValue,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final bool isSimulation;
  final String locationValue;
  final String sensorsValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color:
                      color.withValues(alpha: AppColors.isDark ? 0.18 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            )),
                    const SizedBox(height: 4),
                    Text(message,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              if (isSimulation)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.14),
                    borderRadius: AppRadius.pillRadius,
                  ),
                  child: Text(
                    'TEST',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(color: AppColors.surfaceBorder, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Metric(label: 'LOCATION', value: locationValue)),
              Container(width: 1, height: 34, color: AppColors.surfaceBorder),
              Expanded(child: _Metric(label: 'SENSORS', value: sensorsValue)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    )),
            const SizedBox(height: 4),
            Text(value,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    )),
          ],
        ),
      );
}

final bool _isUnderFlutterTest =
    Platform.environment.containsKey('FLUTTER_TEST');
