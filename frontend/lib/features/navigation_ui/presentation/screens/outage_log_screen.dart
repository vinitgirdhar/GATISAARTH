import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/nav/model/outage_log.dart';
import '../../../../core/nav/model/outage_recovery.dart';
import '../../../../core/nav/nav_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/standard_card.dart';
import '../controllers/live_session_scope.dart';
import '../widgets/status_strip.dart' show formatDistance;

/// Every outage this session, scored by the fix that ended it: the evidence
/// table for the dead-reckoning target, one row per outage.
class OutageLogScreen extends StatelessWidget {
  const OutageLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final log = session.outageLog;
    final target = NavConfig.live.outageReport.driftTargetPct;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outage log'),
        actions: [
          if (!log.isEmpty) ...[
            IconButton(
              tooltip: 'Copy as CSV',
              enableFeedback: false,
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: log.toCsv(target)));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Outage log copied as CSV')),
                );
              },
            ),
            IconButton(
              tooltip: 'Share as CSV',
              enableFeedback: false,
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => SharePlus.instance.share(ShareParams(
                text: log.toCsv(target),
                subject: 'GatiSaarth outage log',
              )),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _Summary(log: log, target: target),
          if (log.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'No outage has ended yet. When GNSS drops for more than '
                '${NavConfig.live.outageReport.minOutage.inSeconds} s and comes '
                'back, the returning fix scores the dead-reckoned position '
                'here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final (i, r) in log.entries.reversed.indexed)
              _Row(number: log.length - i, recovery: r, target: target),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.log, required this.target});

  final OutageLog log;
  final double target;

  @override
  Widget build(BuildContext context) {
    final median = log.medianDriftPct;
    final t = '${target.toStringAsFixed(0)} %';
    return StandardCard(
      titleText: 'This session',
      subtitleText: 'Truth is the returning fix; its accuracy is shown per row',
      child: Row(
        children: [
          _Figure(label: 'Outages', value: '${log.length}'),
          _Figure(
            label: 'Under $t',
            value: log.isEmpty ? '--' : '${log.metTarget(target)}',
          ),
          _Figure(
            label: 'Median drift',
            value: median == null ? '--' : '${median.toStringAsFixed(1)} %',
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.number,
    required this.recovery,
    required this.target,
  });

  final int number;
  final OutageRecovery recovery;
  final double target;

  @override
  Widget build(BuildContext context) {
    final r = recovery;
    final met = r.meetsTarget(target);
    final color = met ? AppColors.success : AppColors.warning;
    final trackParts = <String>[
      if (r.alongTrackM != null) 'along ${r.alongTrackM!.round()} m',
      if (r.crossTrackM != null) 'cross ${r.crossTrackM!.round()} m',
      if (r.recoveryJumpM != null) 'jump ${r.recoveryJumpM!.round()} m',
    ];
    return Semantics(
      label: 'Outage $number${r.isSimulated ? ', simulated' : ''}: '
          '${r.durationS.round()} seconds, '
          '${formatDistance(r.distanceM)}, error ${r.errorM.round()} metres, '
          '${r.driftPct.toStringAsFixed(1)} percent, '
          '${met ? 'within' : 'above'} target'
          '${trackParts.isEmpty ? '' : ', ${trackParts.join(', ')}'}',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          boxShadow: AppShadow.card,
        ),
        child: Row(
          children: [
            Icon(met ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#$number${r.isSimulated ? ' · sim' : ''} · '
                    '${r.durationS.round()} s · '
                    '${formatDistance(r.distanceM)}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'error ${r.errorM.round()} m · vs fix ±${r.fixAccuracyM.round()} m'
                    '${r.coreLed ? '' : ' · core not leading'}',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11.5),
                  ),
                  if (trackParts.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      trackParts.join(' · '),
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              '${r.driftPct.toStringAsFixed(1)} %',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
