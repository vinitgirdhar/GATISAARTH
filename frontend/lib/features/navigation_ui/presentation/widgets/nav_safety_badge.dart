import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../navigation_engine/domain/navigation_safety.dart';

/// Compact, always-visible summary of [TrustAssessment]: a coloured dot, the
/// level word and a short reason — the same "dot + label" shape as
/// `StatusChip` (`dashboard_header.dart`), extended with the reason clause
/// instead of a second, separate widget shape.
///
/// Colour alone never carries the meaning: [Semantics] exposes the level and
/// reason as text for a screen reader, and the level word is always printed.
class NavSafetyBadge extends StatelessWidget {
  const NavSafetyBadge({super.key, required this.assessment});

  final TrustAssessment assessment;

  static Color colorFor(TrustLevel level) {
    switch (level) {
      case TrustLevel.waiting:
        return AppColors.disabled;
      case TrustLevel.green:
        return AppColors.success;
      case TrustLevel.amber:
        return AppColors.warning;
      case TrustLevel.orange:
        return AppColors.highUncertainty;
      case TrustLevel.red:
        return AppColors.error;
    }
  }

  static String wordFor(TrustLevel level) {
    switch (level) {
      case TrustLevel.waiting:
        return 'Waiting';
      case TrustLevel.green:
        return 'Position reliable';
      case TrustLevel.amber:
        return 'Dead reckoning active';
      case TrustLevel.orange:
        return 'High uncertainty';
      case TrustLevel.red:
        return 'Position unreliable';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(assessment.level);
    final word = wordFor(assessment.level);
    final neutral = assessment.level == TrustLevel.waiting;
    return Semantics(
      label: '$word, ${assessment.reason}',
      excludeSemantics: true,
      child: Container(
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
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: word,
                      style: TextStyle(
                        color: neutral ? AppColors.textSecondary : color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' · ${assessment.reason}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width banner shown only in [TrustLevel.red] / Limited Navigation
/// Mode. Deliberately blunt: it names the mode and tells the driver what to
/// do (follow road signs), never a precise position claim.
class NavSafetyLimitedBanner extends StatelessWidget {
  const NavSafetyLimitedBanner({super.key});

  static const String message =
      'Limited navigation — position unreliable. Follow road signs.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
