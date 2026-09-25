import 'package:flutter/material.dart';

import '../../../../core/nav/map/tunnel_lookahead.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../navigation_engine/domain/dr_readiness.dart';
import 'dr_readiness_checklist.dart';
import 'status_strip.dart';

/// Warns before a tunnel from the offline map, then counts down the tunnel
/// still to drive. Says whether the AI speed aid has been validated against
/// GNSS on this drive, because inside it that is what holds the speed. While
/// approaching (not yet inside) it also shows the "GNSS Loss Preparation"
/// readiness checklist — see `GnssLossPreparation`.
class TunnelAheadCard extends StatelessWidget {
  const TunnelAheadCard({
    super.key,
    required this.tunnel,
    required this.speedAidValidated,
    this.readiness,
  });

  final TunnelAhead tunnel;
  final bool speedAidValidated;

  /// The Dead Reckoning readiness checklist; shown only while approaching
  /// (never inside, where the outage has already started).
  final DrReadinessReport? readiness;

  @override
  Widget build(BuildContext context) {
    final t = tunnel;
    final name = t.name == null ? '' : '${t.name} · ';
    final headline = t.inside
        ? 'In tunnel · ${formatDistance(t.remainingM)} to the exit'
        : 'Tunnel ${formatDistance(t.distanceM)} ahead · GNSS loss preparation';
    final aid = speedAidValidated
        ? 'speed aid validated on this drive'
        : 'speed aid not validated yet';
    final detail = t.inside
        ? '$name${formatDistance(t.lengthM)} long · dead reckoning · $aid'
        : '$name${formatDistance(t.lengthM)} long · '
            'dead reckoning takes over inside · $aid';
    final r = readiness;
    final strip = StatusStrip(
      icon: Icons.subway_outlined,
      color: t.inside ? AppColors.deadReckoning : AppColors.warning,
      headline: headline,
      detail: detail,
    );
    if (t.inside || r == null) return strip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        strip,
        Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
          ),
          child: DrReadinessChecklist(report: r),
        ),
      ],
    );
  }
}
