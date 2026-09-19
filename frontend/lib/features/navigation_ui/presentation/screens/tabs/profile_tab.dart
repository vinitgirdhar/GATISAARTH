import 'package:flutter/material.dart';
import '../../../../../core/platform/hardware/vehicle_alignment_engine.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/theme_controller.dart';
import '../../../../../core/widgets/motion.dart';
import '../../controllers/live_session_controller.dart';
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
                  ? Colors.white.withOpacity(0.08)
                  : AppColors.lightSurfaceBorder,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isTwoWheeler
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
                      isTwoWheeler
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
                      isTwoWheeler
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
                  ? Colors.white.withOpacity(0.08)
                  : AppColors.lightSurfaceBorder,
            ),
          ),
          child: Column(
            children: [
              _ProfileMenuTile(
                icon: isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                title: 'Appearance',
                subtitle: isDark ? 'Dark mode enabled' : 'Light mode enabled',
                trailing: Switch(
                  value: isDark,
                  activeColor: AppColors.primary,
                  onChanged: (val) => theme.toggle(),
                ),
              ),
              const Divider(height: 1),
              _ProfileMenuTile(
                icon: Icons.map_rounded,
                title: 'Offline Maps',
                subtitle: 'Pre-bundled Delhi coverage & disk cache',
                trailing: const Icon(Icons.chevron_right_rounded, size: 22),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Offline tile caching active and ready.'),
                      backgroundColor: AppColors.primary,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
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
                  ? Colors.white.withOpacity(0.08)
                  : AppColors.lightSurfaceBorder,
            ),
          ),
          child: Column(
            children: [
              _ProfileMenuTile(
                icon: isTwoWheeler
                    ? Icons.two_wheeler_rounded
                    : Icons.directions_car_rounded,
                title: 'Vehicle Preference',
                subtitle: isTwoWheeler
                    ? 'Two-wheeler (Motorcycle / Scooter)'
                    : 'Car / Four-wheeler',
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isTwoWheeler ? '2-WHEELER' : 'CAR',
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
                subtitle: 'v1.0.0 · Offline Ready 🇮🇳',
                trailing: const Icon(Icons.chevron_right_rounded, size: 22),
              ),
              const Divider(height: 1),
              const _ProfileMenuTile(
                icon: Icons.shield_rounded,
                title: 'Privacy & Architecture',
                subtitle: '100% on-device pure Dart dead reckoning',
                trailing: Text(
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
                color: AppColors.primary.withOpacity(0.12),
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
