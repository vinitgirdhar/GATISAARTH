import 'package:flutter/material.dart';

import '../../../../core/nav/model/simulated_outage.dart';
import '../../../../core/nav/nav_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../navigation_engine/domain/dr_readiness.dart';
import '../controllers/live_session_controller.dart';
import 'dr_readiness_checklist.dart';
import 'status_strip.dart' show formatDistance;

/// The visible "Simulate GNSS loss" control: pick a duration, watch the
/// countdown, and read the drift/along-cross/uncertainty/recovery-jump
/// scorecard once it ends. Stays open across all three states so a demo
/// operator never has to reopen it mid-run.
Future<void> showSimulatedOutageSheet(
  BuildContext context,
  LiveSessionController session,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SimulatedOutageSheet(session: session),
  );
}

class SimulatedOutageSheet extends StatefulWidget {
  const SimulatedOutageSheet({super.key, required this.session});

  final LiveSessionController session;

  @override
  State<SimulatedOutageSheet> createState() => _SimulatedOutageSheetState();
}

class _SimulatedOutageSheetState extends State<SimulatedOutageSheet> {
  final _durations = SimulatedOutageConfig.standard.offeredDurations;
  late Duration _selected = _durations[(_durations.length / 2).floor()];

  /// Set once the driver asks to run another one, so the picker shows again
  /// even though the controller still remembers the last result.
  bool _showPicker = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        final session = widget.session;
        final Widget body;
        if (session.isSimulatingOutage) {
          _showPicker = false;
          body = _RunningBody(session: session);
        } else if (!_showPicker && session.lastSimulatedOutageResult != null) {
          body = _ResultBody(
            result: session.lastSimulatedOutageResult!,
            onClose: () => Navigator.of(context).pop(),
            onRunAgain: () => setState(() => _showPicker = true),
          );
        } else {
          body = _PickerBody(
            durations: _durations,
            selected: _selected,
            onSelect: (d) => setState(() => _selected = d),
            blockedReason: session.simulatedOutageBlockedReason,
            readiness: session.drReadiness,
            onStart: () {
              final reason = session.startSimulatedOutage(_selected);
              if (reason == null) {
                setState(() => _showPicker = false);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(reason)),
                );
              }
            },
          );
        }
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(AppSpacing.md),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.cardRadius,
              boxShadow: AppShadow.card,
            ),
            // Scrollable: the picker body grew a readiness checklist, which
            // can be taller than a short phone screen leaves room for.
            child: SingleChildScrollView(child: body),
          ),
        );
      },
    );
  }
}

class _PickerBody extends StatelessWidget {
  const _PickerBody({
    required this.durations,
    required this.selected,
    required this.onSelect,
    required this.blockedReason,
    required this.onStart,
    required this.readiness,
  });

  final List<Duration> durations;
  final Duration selected;
  final ValueChanged<Duration> onSelect;
  final String? blockedReason;
  final VoidCallback onStart;

  /// The same Dead Reckoning readiness checklist the tunnel-ahead card
  /// shows, so a demo without a real tunnel still previews it before
  /// pressing Start.
  final DrReadinessReport readiness;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Simulate GNSS loss',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Withholds real GPS fixes for the chosen time so the app runs on '
          'dead reckoning alone, exactly like a real outage, then scores it '
          'against the fixes it withheld.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        DrReadinessChecklist(report: readiness),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in durations)
              ChoiceChip(
                label: Text('${d.inSeconds} s'),
                selected: selected == d,
                onSelected: (_) => onSelect(d),
              ),
          ],
        ),
        if (blockedReason != null) ...[
          const SizedBox(height: 10),
          Text(
            blockedReason!,
            style: TextStyle(color: AppColors.warning, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: blockedReason == null ? onStart : null,
            child: const Text('Start'),
          ),
        ),
      ],
    );
  }
}

class _RunningBody extends StatelessWidget {
  const _RunningBody({required this.session});

  final LiveSessionController session;

  @override
  Widget build(BuildContext context) {
    final remaining = session.simulatedOutageRemaining ?? Duration.zero;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.gps_off_rounded, color: AppColors.warning, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'GNSS blackout (simulated) · ${remaining.inSeconds} s left',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Real GPS keeps arriving but is withheld — the map runs on dead '
          'reckoning only, like a real outage.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: session.cancelSimulatedOutage,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.result,
    required this.onClose,
    required this.onRunAgain,
  });

  final SimulatedOutageResult result;
  final VoidCallback onClose;
  final VoidCallback onRunAgain;

  static String _dash(double? v, {int decimals = 1, String unit = ' m'}) =>
      v == null ? '--' : '${v.toStringAsFixed(decimals)}$unit';

  static String _hms(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final r = result;
    final targetPct = NavConfig.live.outageReport.driftTargetPct;
    final met = r.meetsTarget(targetPct);
    final verdict = met == null
        ? '-- vs SIH <${targetPct.toStringAsFixed(0)} % target'
        : met
            ? 'PASS vs SIH <${targetPct.toStringAsFixed(0)} % target'
            : 'Above the ${targetPct.toStringAsFixed(0)} % target';
    final color = met == null
        ? AppColors.textSecondary
        : met
            ? AppColors.success
            : AppColors.warning;
    final travelled =
        r.distanceM == null ? '--' : formatDistance(r.distanceM!);
    final driftPct =
        r.driftPct == null ? '--' : '${r.driftPct!.toStringAsFixed(1)} %';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GNSS blackout simulated at ${_hms(r.startedAt)} · '
          '${r.actualDuration.inSeconds} s',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Travelled $travelled · DR error ${_dash(r.endpointErrorM)} '
          '($driftPct)',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        Text(
          'Along-track ${_dash(r.alongTrackM)} · '
          'Cross-track ${_dash(r.crossTrackM)}',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        Text(
          'Uncertainty grew ${_dash(r.initialSigmaM)} → '
          '${_dash(r.peakSigmaM)} · Recovery jump ${_dash(r.recoveryJumpM)}',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        Text(
          verdict,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onRunAgain,
                child: const Text('Run again'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: onClose,
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
