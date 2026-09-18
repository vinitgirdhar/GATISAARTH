import 'package:flutter/material.dart';

import '../../../../core/constants/dr_constants.dart';
import '../../../../core/platform/network/backend_telemetry_client.dart'
    show BackendSyncState;
import '../../../../core/theme/app_theme.dart';
import '../controllers/live_session_controller.dart';
import 'fusion_confidence_badge.dart';
import 'fusion_mode_badge.dart';

/// App title, the confidence ring, and the at-a-glance status chips.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key, required this.session});

  final LiveSessionController session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final estimate = session.uncertainty;
    final backendLive = session.backendState == BackendSyncState.connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.appTitle,
                      style: theme.headlineMedium?.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(AppConstants.appSubTitle, style: theme.bodyMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            FusionConfidenceBadge(
              confidence: estimate?.confidence,
              marginMeters: estimate?.marginMeters,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FusionModeBadge(fusionMode: session.fusionMode),
            StatusChip(
              color: session.isSensorLive
                  ? AppColors.healthy
                  : AppColors.disabled,
              label: session.isSensorLive
                  ? 'Sensors live · ${_compact(session.sampleCount)}'
                  : 'Sensors idle',
            ),
            StatusChip(
              color: backendLive ? AppColors.healthy : AppColors.disabled,
              label: backendLive
                  ? 'Backend live · ${session.backendRecords} frames'
                  : 'Standalone · backend offline',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          AppConstants.prototypeNotice,
          style: theme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  static String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

/// Small pill with a status dot.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final neutral = color == AppColors.disabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: neutral ? 0.22 : 0.12),
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: neutral ? AppColors.textSecondary : color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
