import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/standard_card.dart';

class NavicWeightIndicator extends StatelessWidget {
  final double navicWeight;

  const NavicWeightIndicator({Key? key, required this.navicWeight})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final weightPercent = (navicWeight * 100).round();
    final isDark = AppColors.isDark;

    return StandardCard(
      titleText: 'NAVIC FUSION WEIGHT',
      trailing: Text(
        '$weightPercent%',
        style: const TextStyle(
          color: AppColors.navIC,
          fontWeight: FontWeight.w800,
          fontSize: 16,
          fontFamily: 'Inter',
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: navicWeight,
              minHeight: 8,
              backgroundColor: isDark
                  ? const Color(0xFF334155)
                  : const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.navIC),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Primary position fix priority assigned to NavIC S-band & L5 signals.',
            style: TextStyle(
              color: isDark
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF64748B),
              fontSize: 12,
              height: 1.3,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}
