import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../navigation_engine/domain/dr_readiness.dart';

/// The "GNSS Loss Preparation" checklist: one row per [DrReadinessReport]
/// check plus the overall verdict. Icon + text for every state — never
/// colour alone (root CLAUDE.md accessibility note) — so it reads the same
/// on the tunnel-ahead card and the "Simulate GNSS loss" sheet.
class DrReadinessChecklist extends StatelessWidget {
  const DrReadinessChecklist({super.key, required this.report});

  final DrReadinessReport report;

  @override
  Widget build(BuildContext context) {
    final overallColor = switch (report.overall) {
      DrReadinessLevel.ready => AppColors.success,
      DrReadinessLevel.partiallyReady => AppColors.warning,
      DrReadinessLevel.notReady => AppColors.error,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in report.rows) _ReadinessRowTile(row: row),
        const SizedBox(height: 4),
        Text(
          report.overall.label,
          style: TextStyle(
            color: overallColor,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}

class _ReadinessRowTile extends StatelessWidget {
  const _ReadinessRowTile({required this.row});

  final ReadinessRow row;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    switch (row.status) {
      case ReadinessStatus.ok:
        icon = Icons.check_circle_outline;
        color = AppColors.success;
      case ReadinessStatus.warn:
        icon = Icons.error_outline;
        color = AppColors.warning;
      case ReadinessStatus.notReady:
        icon = Icons.cancel_outlined;
        color = AppColors.error;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${row.label}: ',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: row.reason,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
