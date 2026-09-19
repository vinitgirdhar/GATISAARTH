import 'package:flutter/material.dart';

import '../../../../core/platform/location/live_location_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';

/// Tells the user *why* there is no live position and offers the one action
/// that fixes it. Renders nothing while location is healthy or still
/// warming up.
class LocationStatusBanner extends StatelessWidget {
  const LocationStatusBanner({super.key, required this.location});

  final LiveLocationService location;

  @override
  Widget build(BuildContext context) {
    final info = _infoFor(location);
    if (info == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            info.color.withValues(alpha: 0.08),
            AppColors.surface,
          ),
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppShadow.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: info.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(info.icon, color: info.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.message,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: PressableScale(
                onTap: info.onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: info.color,
                    borderRadius: AppRadius.pillRadius,
                  ),
                  child: Text(
                    info.actionLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _BannerInfo? _infoFor(LiveLocationService location) {
    switch (location.status) {
      case LocationStatus.serviceOff:
        return _BannerInfo(
          icon: Icons.location_off_rounded,
          color: AppColors.error,
          title: 'Location is turned off',
          message: 'Turn it on to get your live GNSS position. Until then the '
              'app runs on its inertial sensors only.',
          actionLabel: 'Open location settings',
          onAction: location.openLocationSettings,
        );
      case LocationStatus.permissionDenied:
        return _BannerInfo(
          icon: Icons.my_location_rounded,
          color: AppColors.warning,
          title: 'Allow location access',
          message: 'GatiSaarth needs precise location to show where you are '
              'and to detect GNSS loss.',
          actionLabel: 'Allow',
          onAction: location.requestPermission,
        );
      case LocationStatus.permissionBlocked:
        return _BannerInfo(
          icon: Icons.lock_outline_rounded,
          color: AppColors.error,
          title: 'Location access is blocked',
          message: 'Enable location for GatiSaarth in system settings '
              '(choose "Precise").',
          actionLabel: 'Open app settings',
          onAction: location.openAppSettings,
        );
      case LocationStatus.initializing:
      case LocationStatus.searching:
      case LocationStatus.live:
      case LocationStatus.stale:
        return null;
    }
  }
}

class _BannerInfo {
  const _BannerInfo({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
}
