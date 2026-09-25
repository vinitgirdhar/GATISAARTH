import 'package:flutter/material.dart';
import '../../../../../core/constants/dr_constants.dart';
import '../../../../../core/platform/hardware/vehicle_alignment_engine.dart';
import '../../../../../core/platform/maps/map_download_service.dart';
import '../../../../../core/platform/maps/offline_catalog.dart';
import '../../../../../core/platform/maps/offline_map_service.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/theme_controller.dart';
import '../../../../../core/widgets/motion.dart';
import '../../controllers/live_session_scope.dart';
import '../../widgets/vehicle_profile_selector.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final theme = ThemeScope.of(context);
    final isDark = AppColors.isDark;
    final isTwoWheeler = session.vehicleProfile == VehicleProfile.twoWheeler;
    final isPedestrian = session.vehicleProfile == VehicleProfile.pedestrian;
    final maps = OfflineMapsScope.maybeOf(context);
    final downloads = MapDownloadsScope.maybeOf(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        // 1. Vehicle Profile & Tuning Section
        const SectionHeader(
          title: 'Vehicle Configuration',
          subtitle: 'Active dynamics and filter tuning',
        ),
        const SizedBox(height: 8),
        VehicleProfileSelector(
          selected: session.vehicleProfile,
          onChanged: session.setVehicleProfile,
        ),
        const SizedBox(height: 12),
        // Active Profile Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.lightSurfaceBorder,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPedestrian
                      ? Icons.directions_walk_rounded
                      : isTwoWheeler
                          ? Icons.two_wheeler_rounded
                          : Icons.directions_car_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPedestrian
                          ? 'Pedestrian / Last-mile Active'
                          : isTwoWheeler
                              ? 'Two-Wheeler Dynamics Active'
                              : 'Car / Four-Wheeler Dynamics Active',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPedestrian
                          ? 'Vehicle-only lateral constraints disabled'
                          : isTwoWheeler
                              ? 'Lean-angle compensation & bump suppression enabled'
                              : 'Non-holonomic constraint (NHC) zero-lateral slip active',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // 2. Preferences Section
        const SectionHeader(
          title: 'Preferences',
          subtitle: 'Display, offline data, and telemetry',
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.lightSurfaceBorder,
            ),
          ),
          child: Column(
            children: [
              _ProfileMenuTile(
                icon:
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                title: 'Appearance',
                subtitle: isDark ? 'Dark mode enabled' : 'Light mode enabled',
                trailing: Switch(
                  value: isDark,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) => theme.toggle(),
                ),
              ),
              const Divider(height: 1),
              _ProfileMenuTile(
                icon: Icons.directions_run_rounded,
                title: 'Automatic activity mode',
                subtitle: session.automaticActivityEnabled
                    ? 'Detected · ${session.activityMode.name}'
                    : 'Off · manual profile takes precedence',
                trailing: Switch(
                  value: session.automaticActivityEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (enabled) =>
                      session.setAutomaticActivityEnabled(enabled),
                ),
              ),
              const Divider(height: 1),
              _ProfileMenuTile(
                icon: Icons.vibration_rounded,
                title: 'Haptic alerts',
                subtitle: 'Safety patterns for GNSS loss and unsafe ambiguity',
                trailing: Switch(
                  value: session.hapticsEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: session.setHapticsEnabled,
                ),
              ),
              const Divider(height: 1),
              _ProfileMenuTile(
                icon: Icons.record_voice_over_rounded,
                title: 'Safe outage voice',
                subtitle:
                    'Speaks only on GNSS loss, unsafe ambiguity, and recovery',
                trailing: Switch(
                  value: session.voiceGuidanceEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: session.setVoiceGuidanceEnabled,
                ),
              ),
              const Divider(height: 1),
              _ProfileMenuTile(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Trusted Portal Scanner',
                subtitle: session.anchorPackId == null
                    ? 'Loading local anchor pack'
                    : session.hasInstalledAnchors
                        ? 'Offline pack · ${session.anchorPackId}'
                        : 'No field-surveyed anchors installed',
                trailing: const Icon(Icons.chevron_right_rounded, size: 22),
                onTap: () => Navigator.pushNamed(context, '/portal-anchor'),
              ),
              const Divider(height: 1),
              _ProfileMenuTile(
                icon: Icons.map_rounded,
                title: 'Offline Maps',
                subtitle: _offlineMapsSubtitle(maps, downloads),
                trailing: const Icon(Icons.chevron_right_rounded, size: 22),
                onTap: () => Navigator.pushNamed(context, '/offline-maps'),
              ),
              const Divider(height: 1),
              _ProfileMenuTile(
                icon: Icons.fact_check_rounded,
                title: 'Outage Log',
                subtitle: session.outageLog.isEmpty
                    ? 'Every GNSS outage this session, scored on recovery'
                    : '${session.outageLog.length} scored this session',
                trailing: const Icon(Icons.chevron_right_rounded, size: 22),
                onTap: () => Navigator.pushNamed(context, '/outage-log'),
              ),
              const Divider(height: 1),
              _ProfileMenuTile(
                icon: Icons.speed_rounded,
                title: 'Outage Benchmark',
                subtitle: 'Score dead reckoning with GNSS switched off',
                trailing: const Icon(Icons.chevron_right_rounded, size: 22),
                onTap: () => Navigator.pushNamed(context, '/benchmark'),
              ),
              const Divider(height: 1),
              _ProfileMenuTile(
                icon: Icons.bug_report_rounded,
                title: 'Diagnostics Console',
                subtitle: 'Internal telemetry and replay logs',
                trailing: const Icon(Icons.chevron_right_rounded, size: 22),
                onTap: () => Navigator.pushNamed(context, '/diagnostics'),
                isLast: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // 3. About Section (Vehicle Preference & System Info only - No Account)
        const SectionHeader(
          title: 'About',
          subtitle: 'Vehicle preference & system details',
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.lightSurfaceBorder,
            ),
          ),
          child: Column(
            children: [
              _ProfileMenuTile(
                icon: isPedestrian
                    ? Icons.directions_walk_rounded
                    : isTwoWheeler
                        ? Icons.two_wheeler_rounded
                        : Icons.directions_car_rounded,
                title: 'Vehicle Preference',
                subtitle: isPedestrian
                    ? 'Pedestrian / last-mile'
                    : isTwoWheeler
                        ? 'Two-wheeler (Motorcycle / Scooter)'
                        : 'Car / Four-wheeler',
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isPedestrian
                        ? 'WALK'
                        : (isTwoWheeler ? '2-WHEELER' : 'CAR'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              _ProfileMenuTile(
                icon: Icons.explore_rounded,
                title: 'GatiSaarth Navigation Engine',
                subtitle: 'v${AppConstants.appVersion} · Offline Ready 🇮🇳 · '
                    'specifications',
                trailing: const Icon(Icons.chevron_right_rounded, size: 22),
                onTap: () => Navigator.pushNamed(context, '/engine'),
              ),
              const Divider(height: 1),
              // Not `const`: a const tile is never rebuilt, so it kept the
              // previous brightness's colours after a theme flip.
              _ProfileMenuTile(
                icon: Icons.shield_rounded,
                title: 'Privacy & Architecture',
                subtitle: '100% on-device pure Dart dead reckoning',
                trailing: const Text(
                  '🇮🇳',
                  style: TextStyle(fontSize: 18),
                ),
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _offlineMapsSubtitle(
  OfflineMapService? maps,
  MapDownloadService? downloads,
) {
  final regions = OfflineCatalog.regions.map((r) => r.name).join(' · ');
  if (downloads != null && downloads.isBusy) {
    return 'Downloading ${downloads.pending == 1 ? '1 map' : '${downloads.pending} maps'}'
        ' · ${(downloads.overallFraction * 100).round()}%';
  }
  if (maps == null || maps.isLoading || maps.installed.isEmpty) return regions;
  final mb = (maps.installedBytes / 1e6).round();
  return '$regions · $mb MB on this phone';
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        bottom: isLast ? const Radius.circular(20) : Radius.zero,
        top: Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
