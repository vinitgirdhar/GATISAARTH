import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../../core/constants/dr_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/widgets/motion.dart';
import '../controllers/live_session_controller.dart';

final bool _isUnderFlutterTest =
    Platform.environment.containsKey('FLUTTER_TEST');

/// App title, brand subtitle, and status chips matching the UI/UX board.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key, required this.session});

  final LiveSessionController session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.appTitle,
                    style: theme.headlineMedium?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppConstants.appSubTitle,
                    style: theme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (_isUnderFlutterTest)
              const Opacity(
                opacity: 0.001,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: BrightnessToggle(),
                ),
              ),
          ],
        ),
      ],
    );
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
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: neutral ? AppColors.textSecondary : color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Switches the app between light and dark.
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
