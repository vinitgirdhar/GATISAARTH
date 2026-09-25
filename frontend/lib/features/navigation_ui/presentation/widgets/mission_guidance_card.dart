import 'package:flutter/material.dart';

import '../../../../core/nav/guidance/mission_guidance.dart';
import '../../../../core/theme/app_theme.dart';

/// Shown in place of [MissionGuidanceCard] whenever the navigation safety
/// controller has flagged the position RED / Limited Navigation Mode: turn
/// and speed-limit guidance built from a position the app itself does not
/// trust is worse than no guidance at all.
class MissionGuidancePausedNotice extends StatelessWidget {
  const MissionGuidancePausedNotice({super.key});

  static const String text = 'Guidance paused — position unreliable';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: text,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.volume_off_rounded, color: AppColors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
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

class MissionGuidanceCard extends StatelessWidget {
  const MissionGuidanceCard(
      {super.key, required this.decision, this.compact = false});

  final MissionGuidanceDecision decision;
  final bool compact;

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
        padding:
            EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 8 : 11),
        decoration: BoxDecoration(
          color: compact ? AppColors.surface : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(
              warning ? Icons.volume_up_rounded : Icons.gps_fixed_rounded,
              color: color,
              size: compact ? 17 : 20,
            ),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Text(
                decision.display,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 11 : 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
