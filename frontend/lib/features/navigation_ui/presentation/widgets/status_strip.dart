import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// A one-glance strip above the map: an icon in [color], a bold headline and
/// a quieter detail line. Announced to screen readers as it changes.
class StatusStrip extends StatelessWidget {
  const StatusStrip({
    super.key,
    required this.icon,
    required this.color,
    required this.headline,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String headline;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '$headline, $detail',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    headline,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    detail,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "850 m" below a kilometre, "1.25 km" above.
String formatDistance(double m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.round()} m';
