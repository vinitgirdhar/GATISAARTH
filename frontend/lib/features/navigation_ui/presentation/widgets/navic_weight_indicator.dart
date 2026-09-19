import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class NavicWeightIndicator extends StatelessWidget {
  final double navicWeight;

  const NavicWeightIndicator({Key? key, required this.navicWeight})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final weightPercent = (navicWeight * 100).round();
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NavIC fusion weight',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2),
              ),
              Text(
                '$weightPercent%',
                style: const TextStyle(
                    color: AppColors.navIC,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: navicWeight,
              minHeight: 8,
              backgroundColor: AppColors.surfaceBorder,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.navIC),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Primary position fix priority assigned to NavIC S-band & L5 signals.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
