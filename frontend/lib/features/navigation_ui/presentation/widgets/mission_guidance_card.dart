import 'package:flutter/material.dart';

import '../../../../core/nav/guidance/mission_guidance.dart';
import '../../../../core/theme/app_theme.dart';

class MissionGuidanceCard extends StatelessWidget {
  const MissionGuidanceCard({super.key, required this.decision});

  final MissionGuidanceDecision decision;

  @override
  Widget build(BuildContext context) {
    final warning = decision.event != MissionGuidanceEvent.recovered;
    final color = warning ? AppColors.warning : AppColors.success;
    return Semantics(
      liveRegion: true,
      label: decision.display,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(
              warning ? Icons.volume_up_rounded : Icons.gps_fixed_rounded,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                decision.display,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
