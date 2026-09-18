import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';

/// Driver-facing confidence: a ring that fills with the modelled confidence
/// and the position-uncertainty margin under it.
///
/// [confidence] null means "no basis for an estimate yet" (no GNSS fix and no
/// outage in progress) — shown as an empty grey ring, never a made-up number.
class FusionConfidenceBadge extends StatelessWidget {
  const FusionConfidenceBadge({
    super.key,
    required this.confidence,
    required this.marginMeters,
  });

  final double? confidence;
  final double? marginMeters;

  static Color colorFor(double? confidence) {
    if (confidence == null) return AppColors.disabled;
    if (confidence >= 0.90) return AppColors.healthy;
    if (confidence >= 0.70) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final value = confidence;
    final color = colorFor(value);
    final percent = value == null ? '--' : '${(value * 100).round()}';
    final margin = marginMeters;
    final marginText = margin == null ? 'No fix yet' : '±${margin.round()} m';

    return Semantics(
      label: value == null
          ? 'Position confidence unavailable, waiting for a fix'
          : 'Position confidence $percent percent, margin ${margin?.round()} metres',
      excludeSemantics: true,
      child: Container(
        width: 96,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppShadow.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 68,
              height: 68,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: value ?? 0),
                    duration: AppMotion.of(context, AppMotion.slow),
                    curve: Curves.easeOutCubic,
                    builder: (context, animated, _) => SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: animated,
                        strokeWidth: 7,
                        strokeCap: StrokeCap.round,
                        backgroundColor: color.withValues(alpha: 0.16),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: percent,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const TextSpan(
                          text: '%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Confidence', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                marginText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: value == null ? AppColors.textMuted : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
