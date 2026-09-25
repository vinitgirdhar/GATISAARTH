import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// One figure in a row of figures (speed, heading, margin…). It takes an equal
/// share of its [Row] and shrinks its text rather than wrapping or clipping, so
/// a row of three still fits a 320 dp phone.
class TelemetryCard extends StatelessWidget {
  const TelemetryCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.subtitle,
    this.accentColor = AppColors.cyan,
  });

  final String label;
  final String value;
  final String? unit;
  final String? subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppShadow.card,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OneLine(Text(
                label.toUpperCase(),
                style: text.labelSmall
                    ?.copyWith(letterSpacing: 0.6, fontWeight: FontWeight.w700),
              )),
              const SizedBox(height: 6),
              _OneLine(Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: text.headlineMedium?.copyWith(
                      color: accentColor,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (unit != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Text(
                        unit!,
                        style: TextStyle(
                          color: accentColor.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              )),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                _OneLine(Text(
                  subtitle!,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps [child] on one line, scaled down when the card is narrow.
class _OneLine extends StatelessWidget {
  const _OneLine(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: child,
      );
}
