import 'package:flutter/material.dart';

import '../../../../core/constants/dr_constants.dart';
import '../../../../core/platform/network/backend_telemetry_client.dart'
    show BackendSyncState;
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/widgets/motion.dart';
import '../controllers/live_session_controller.dart';
import 'fusion_confidence_badge.dart';
import 'fusion_mode_badge.dart';

/// App title, the confidence ring, and the at-a-glance status chips.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key, required this.session});

  final LiveSessionController session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final estimate = session.uncertainty;
    final backendLive = session.backendState == BackendSyncState.connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.appTitle,
                    style: theme.headlineMedium?.copyWith(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(AppConstants.appSubTitle, style: theme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const BrightnessToggle(),
            const SizedBox(width: 4),
            FusionConfidenceBadge(
              confidence: estimate?.confidence,
              marginMeters: estimate?.marginMeters,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FusionModeBadge(fusionMode: session.fusionMode),
            StatusChip(
              color: session.isSensorLive
                  ? AppColors.healthy
                  : AppColors.disabled,
              label: session.isSensorLive
                  ? 'Sensors live · ${_compact(session.sampleCount)}'
                  : 'Sensors idle',
            ),
            StatusChip(
              color: backendLive ? AppColors.healthy : AppColors.disabled,
              label: backendLive
                  ? 'Backend live · ${session.backendRecords} frames'
                  : 'Standalone · backend offline',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          AppConstants.prototypeNotice,
          style: theme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  static String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

/// Small pill with a status dot.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final neutral = color == AppColors.disabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: neutral ? 0.22 : 0.12),
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: neutral ? AppColors.textSecondary : color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Switches the app between light and dark. The choice is remembered across
/// launches (see [ThemeController]).
class BrightnessToggle extends StatelessWidget {
  const BrightnessToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.of(context);
    final isDark = controller.isDark;
    return Semantics(
      button: true,
      label: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      excludeSemantics: true,
      child: PressableScale(
        onTap: controller.toggle,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: AppShadow.card,
          ),
          child: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            size: 18,
            color: isDark ? AppColors.warning : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
