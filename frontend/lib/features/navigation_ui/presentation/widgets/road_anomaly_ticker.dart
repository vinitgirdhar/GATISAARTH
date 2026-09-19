import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';

class RoadAnomalyTicker extends StatelessWidget {
  final List<AnomalyEventModel> anomalyEvents;

  const RoadAnomalyTicker({Key? key, required this.anomalyEvents})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
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
          Text(
            'Detected road anomalies',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          if (anomalyEvents.isEmpty)
            Text(
              'None yet — bumps and potholes appear here as they are felt.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ...anomalyEvents
              .map((event) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 14, color: AppColors.warning),
                            const SizedBox(width: 6),
                            Text(
                              event.type.replaceAll('_', ' '),
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        Text(
                          '${(event.confidence * 100).round()}% confidence',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ],
      ),
    );
  }
}
