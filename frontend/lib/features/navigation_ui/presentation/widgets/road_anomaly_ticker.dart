import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/standard_card.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';

class RoadAnomalyTicker extends StatelessWidget {
  final List<AnomalyEventModel> anomalyEvents;

  const RoadAnomalyTicker({Key? key, required this.anomalyEvents})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final secondaryColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return StandardCard(
      titleText: 'DETECTED ROAD ANOMALIES',
      trailing: anomalyEvents.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Text(
                '${anomalyEvents.length} Detected',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                  fontFamily: 'Inter',
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (anomalyEvents.isEmpty)
            Text(
              'None yet — bumps and potholes appear here as they are felt.',
              style: TextStyle(
                color: secondaryColor,
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
          for (int i = 0; i < anomalyEvents.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        anomalyEvents[i].type.replaceAll('_', ' '),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${(anomalyEvents[i].confidence * 100).round()}% confidence',
                    style: TextStyle(
                      color: secondaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            if (i < anomalyEvents.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: isDark
                    ? const Color(0xFF334155).withValues(alpha: 0.5)
                    : const Color(0xFFE2E8F0),
              ),
          ],
        ],
      ),
    );
  }
}
