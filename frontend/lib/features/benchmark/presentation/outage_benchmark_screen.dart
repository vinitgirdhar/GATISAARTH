import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/nav/benchmark/outage_report.dart';
import '../../../core/nav/motion/motion_classifier.dart' show VehicleClass;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/standard_card.dart';
import '../data/benchmark_backend.dart';
import '../data/benchmark_report_exporter.dart';

/// Replays a drive with GNSS switched off and scores where each method thought
/// the car was against the fix it was denied (§39, §76).
///
/// Runs on whatever phone it is installed on: truth is that phone's own GNSS,
/// so no reference hardware is needed, and the bundled reference drive gives
/// every phone the same yardstick.
class OutageBenchmarkScreen extends StatefulWidget {
  const OutageBenchmarkScreen({
    super.key,
    this.backend = const DeviceBenchmarkBackend(),
  });

  final BenchmarkBackend backend;

  @override
  State<OutageBenchmarkScreen> createState() => _OutageBenchmarkScreenState();
}

class _OutageBenchmarkScreenState extends State<OutageBenchmarkScreen> {
  late Future<List<BenchmarkSource>> _sources = widget.backend.sources();
  BenchmarkSource? _running;
  double _progress = 0;
  OutageReport? _report;
  BenchmarkSource? _reportSource;
  bool _simulated = false;
  String? _error;

  Future<void> _run(BenchmarkSource source) async {
    setState(() {
      _running = source;
      _progress = 0;
      _report = null;
      _reportSource = null;
      _error = null;
    });
    try {
      final report = await widget.backend.run(
        source,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _reportSource = source;
        _simulated = source.simulated;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  Future<void> _share(BenchmarkSource source) async {
    final ok = await _confirm(
      title: 'Share this drive?',
      body: 'The file holds the route you rode, second by second: GPS '
          'positions and motion-sensor readings. A compressed copy is sent; '
          'the original stays on this phone. Share it only with someone you '
          'trust.',
      action: 'Share',
    );
    if (!ok) return;
    try {
      await widget.backend.share(source);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not share the drive: $e');
    }
  }

  Future<void> _delete(BenchmarkSource source) async {
    final ok = await _confirm(
      title: 'Delete this drive?',
      body: 'It is removed from this phone and cannot be recovered.',
      action: 'Delete',
    );
    if (!ok) return;
    await widget.backend.delete(source);
    if (mounted) {
      setState(() {
        _sources = widget.backend.sources();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Outage benchmark')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Replays a drive with GNSS switched off, then measures how far off '
            'each method ends up from the position the phone was denied. Works '
            'on any phone: the truth is its own GNSS.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          _sourceList(),
          if (_running != null) _progressCard(),
          if (_error != null) _errorCard(),
          if (_report != null) ..._results(_report!),
        ],
      ),
    );
  }

  Widget _sourceList() {
    return FutureBuilder<List<BenchmarkSource>>(
      future: _sources,
      builder: (context, snapshot) {
        final sources = snapshot.data;
        if (sources == null) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final recorded = sources.where((s) => !s.simulated).length;
        return StandardCard(
          titleText: 'CHOOSE A DRIVE',
          subtitleText: recorded == 0
              ? 'To score your own drive, record one from Sensors, then '
                  'reopen this screen.'
              : 'Tap a drive to score it. Recordings are saved only on this '
                  'phone; nothing is uploaded unless you share it.',
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Column(
            children: [
              for (final s in sources)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  enabled: _running == null,
                  leading: Icon(
                    s.simulated
                        ? Icons.science_rounded
                        : Icons.directions_car_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text(s.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(s.subtitle),
                  trailing: s.simulated
                      ? const Icon(Icons.play_arrow_rounded)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Share drive',
                              icon: const Icon(Icons.share_rounded),
                              onPressed:
                                  _running == null ? () => _share(s) : null,
                            ),
                            IconButton(
                              tooltip: 'Delete drive',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed:
                                  _running == null ? () => _delete(s) : null,
                            ),
                          ],
                        ),
                  onTap: () => _run(s),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _progressCard() {
    return StandardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Replaying ${_running!.title} with GNSS withheld...'),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return StandardCard(
      child: Text(
        'Could not run the benchmark: $_error',
        style: const TextStyle(color: AppColors.boardError),
      ),
    );
  }

  List<Widget> _results(OutageReport report) {
    return [
      StandardCard(
        titleText: 'RESULT',
        child: Text(
          report.headline,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      for (final d in report.durations) _DurationCard(result: d),
      if (report.durations.isNotEmpty) _ReportCard(report: report),
      _AboutCard(report: report, simulated: _simulated),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy report'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report.toText()));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report copied')),
                );
              },
            ),
          ),
          if (_reportSource != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.verified_user_rounded),
                label: const Text('Share signed evidence'),
                onPressed: () async {
                  try {
                    await widget.backend.shareEvidence(_reportSource!, report);
                  } catch (e) {
                    if (mounted) {
                      setState(() =>
                          _error = 'Could not create signed evidence: $e');
                    }
                  }
                },
              ),
            ),
          ],
        ],
      ),
      if (_reportSource != null && report.durations.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: PopupMenuButton<ReportFormat>(
              tooltip: 'Export report',
              onSelected: (format) async {
                try {
                  await widget.backend
                      .shareReport(_reportSource!, report, format);
                } catch (e) {
                  if (mounted) {
                    setState(() => _error = 'Could not export the report: $e');
                  }
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: ReportFormat.json, child: Text('JSON')),
                PopupMenuItem(value: ReportFormat.csv, child: Text('CSV')),
                PopupMenuItem(value: ReportFormat.pdf, child: Text('PDF')),
              ],
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Export report'),
              ),
            ),
          ),
        ),
    ];
  }
}

/// Headline numbers at a glance, plus the PASS/FAIL chip against the SIH
/// drift target - the same numbers `report.toText()`'s verdict line reports,
/// read at arm's length instead of grepped from the copied text.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final OutageReport report;

  @override
  Widget build(BuildContext context) {
    final d = report.durations.last;
    final passed = d.passed(report.driftTargetPct);
    return StandardCard(
      titleText: 'REPORT',
      trailing: _VerdictChip(passed: passed),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'At ${d.durationS} s: ${d.engine.medianDriftPct.toStringAsFixed(1)}% '
            'drift, cross-track ${d.medianCrossTrackM.isFinite ? d.medianCrossTrackM.toStringAsFixed(1) : '--'} m, '
            'along-track ${d.medianAlongTrackM.isFinite ? d.medianAlongTrackM.toStringAsFixed(1) : '--'} m, '
            'max uncertainty ${d.medianMaxSigmaM.isFinite ? d.medianMaxSigmaM.toStringAsFixed(1) : '--'} m.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Against the SIH26168 target of under '
            '${report.driftTargetPct.toStringAsFixed(0)}% drift.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _VerdictChip extends StatelessWidget {
  const _VerdictChip({required this.passed});

  final bool passed;

  @override
  Widget build(BuildContext context) {
    final color = passed ? AppColors.success : AppColors.boardError;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        passed ? 'PASS' : 'FAIL',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Both methods at one outage length.
class _DurationCard extends StatelessWidget {
  const _DurationCard({required this.result});

  final DurationResult result;

  @override
  Widget build(BuildContext context) {
    final d = result;
    return StandardCard(
      titleText: 'AFTER ${d.durationS} s WITHOUT GNSS',
      trailing: Text('${d.n} outages',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Method(
                  name: 'Hold last velocity',
                  stats: d.hold,
                  color: AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: _Method(
                  name: 'Navigation core',
                  stats: d.engine,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Core closer in ${d.engineWins} of ${d.n}. Its own uncertainty '
            'covered the real error in ${d.engineCovered} of ${d.n}.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Method extends StatelessWidget {
  const _Method({required this.name, required this.stats, required this.color});

  final String name;
  final OutageStats stats;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final small = TextStyle(fontSize: 11, color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${stats.medianM.toStringAsFixed(0)} m',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          Text('median error', style: small),
          Text('worst 5%: ${stats.p95M.toStringAsFixed(0)} m', style: small),
          Text('${stats.medianDriftPct.toStringAsFixed(1)}% of distance',
              style: small),
        ],
      ),
    );
  }
}

/// What the numbers rest on: the phone, the data and the caveats.
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.report, required this.simulated});

  final OutageReport report;
  final bool simulated;

  @override
  Widget build(BuildContext context) {
    final p = report.profile;
    final floor = p.medianTruthAccuracyM.isFinite
        ? '${p.medianTruthAccuracyM.toStringAsFixed(1)} m'
        : 'unknown';
    final lines = <String>[
      'Device: ${p.deviceModel ?? 'unknown'}. Replayed with '
          '${report.vehicleClass == VehicleClass.twoWheeler ? 'two-wheeler' : 'car'} settings.',
      'IMU ${p.imuHz.toStringAsFixed(0)} Hz | GNSS ${p.gnssHz.toStringAsFixed(1)} Hz '
          '| magnetometer ${p.hasMagnetometer ? 'yes' : 'no'} | '
          'barometer ${p.hasBarometer ? 'yes' : 'no'}',
      'Drive ${(p.durationS / 60).toStringAsFixed(1)} min, '
          '${p.truthFixes} trusted GNSS fixes. The truth itself is only good '
          'to about $floor, so nothing smaller than that is resolved.',
      if (report.coreLedFromS != null)
        'The core became healthy enough to lead ${report.coreLedFromS!.toStringAsFixed(0)} s '
            'into the drive; ${report.windowsTried} outage starts were tried.',
      if (report.skipped.isNotEmpty)
        'Not scored: ${report.skipped.entries.map((e) => '${e.value} x ${_reason(e.key)}').join(', ')}.',
      'Replayed on this phone in ${(report.runtimeMs / 1000).toStringAsFixed(1)} s.',
      if (simulated)
        'Simulated sensors: this bounds the engine under modelled error and is '
            'not a field measurement.',
    ];
    return StandardCard(
      titleText: 'ABOUT THIS RESULT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line,
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }

  static String _reason(SkipReason r) => switch (r) {
        SkipReason.engineNotLeading => 'core not yet aligned',
        SkipReason.noRecentFix => 'no recent fix before the outage',
        SkipReason.tooLittleTravel => 'vehicle barely moved',
        SkipReason.noTruthAtEnd => 'no fix near the outage end',
      };
}
