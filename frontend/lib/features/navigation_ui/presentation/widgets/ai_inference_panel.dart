import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/standard_card.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';

class AiInferencePanel extends StatelessWidget {
  final InferenceStatsModel inferenceStats;

  const AiInferencePanel({Key? key, required this.inferenceStats})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final isLoaded = inferenceStats.modelVersion != 'Model not loaded';
    final badgeColor = isLoaded ? AppColors.cyan : const Color(0xFF3882F6);
    final labelColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return StandardCard(
      titleText: 'EDGE AI SPEED ESTIMATOR & ODOMETRY',
      subtitleText: isLoaded
          ? 'Advisory: not used for position until it beats the outage '
              'benchmark on recorded drives.'
          : null,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: badgeColor.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Text(
          inferenceStats.modelVersion,
          style: TextStyle(
            color: badgeColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Latency',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                    letterSpacing: 0.2,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    inferenceStats.latencyMs == null
                        ? '--'
                        : '${inferenceStats.latencyMs} ms',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 38,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: isDark
                ? const Color(0xFF334155).withValues(alpha: 0.6)
                : const Color(0xFFE2E8F0),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Est. speed',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                    letterSpacing: 0.2,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    inferenceStats.estimatedSpeed == null
                        ? '--'
                        : '${inferenceStats.estimatedSpeed!.toStringAsFixed(1)} m/s',
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 38,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: isDark
                ? const Color(0xFF334155).withValues(alpha: 0.6)
                : const Color(0xFFE2E8F0),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI conf',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                    letterSpacing: 0.2,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    inferenceStats.confidence == null
                        ? '--'
                        : '${(inferenceStats.confidence! * 100).round()}%',
                    style: const TextStyle(
                      color: AppColors.healthy,
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
