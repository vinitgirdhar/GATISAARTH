import 'package:flutter/material.dart';

import '../../../../core/nav/model/outage_recovery.dart';
import '../../../../core/nav/nav_config.dart';
import '../../../../core/theme/app_theme.dart';
import 'status_strip.dart';

/// Scores the outage a returning GNSS fix just ended: how long, how far, and
/// how far off the dead-reckoned position was, against the SIH target.
///
/// The truth is the phone's own returning fix, so its accuracy is printed
/// next to the error; a card never claims more precision than that fix has.
class OutageRecoveryCard extends StatelessWidget {
  const OutageRecoveryCard({
    super.key,
    required this.recovery,
    this.targetPct,
  });

  final OutageRecovery recovery;

  /// Defaults to the SIH target in `NavConfig.live`.
  final double? targetPct;

  @override
  Widget build(BuildContext context) {
    final r = recovery;
    final targetPct =
        this.targetPct ?? NavConfig.live.outageReport.driftTargetPct;
    final met = r.meetsTarget(targetPct);
    final color = met ? AppColors.success : AppColors.warning;
    final target = '${targetPct.toStringAsFixed(0)} %';
    final headline =
        'Outage ${r.durationS.round()} s · ${formatDistance(r.distanceM)} · '
        'error ${r.errorM.round()} m (${r.driftPct.toStringAsFixed(1)} %)';
    final verdict =
        met ? 'within the $target target' : 'above the $target target';
    final detail = r.coreLed
        ? '$verdict · vs returning fix (±${r.fixAccuracyM.round()} m)'
        : '$verdict · core was not leading the map';

    return StatusStrip(
      icon: met ? Icons.verified_rounded : Icons.error_outline_rounded,
      color: color,
      headline: headline,
      detail: detail,
    );
  }
}
