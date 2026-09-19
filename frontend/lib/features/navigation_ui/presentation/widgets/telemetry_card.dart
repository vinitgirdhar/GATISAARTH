import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class TelemetryCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String? subtitle;
  final Color accentColor;

  const TelemetryCard({
    Key? key,
    required this.label,
    required this.value,
    this.unit,
    this.subtitle,
    this.accentColor = AppColors.cyan,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppShadow.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(
                          color: accentColor,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 3),
                    Text(
                      unit!,
                      style: TextStyle(
                        color: accentColor.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
