import 'package:flutter/material.dart';

import '../../../core/nav/benchmark/fault_injection.dart';
import '../../../core/nav/benchmark/fault_lab.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/standard_card.dart';
import '../data/fault_lab_backend.dart';

/// Developer/benchmark tool: injects one synthetic fault into a replayed
/// drive and shows whether the navigation core noticed it and what it did.
///
/// Never a claim about the live app on a live drive - this replays a log
/// twice (clean, then faulted) through the same engine, so it can only ever
/// say what the *engine* does with the fault, honestly, including when it
/// does not notice at all.
class FaultLabScreen extends StatefulWidget {
  const FaultLabScreen({super.key, this.backend = const DeviceFaultLabBackend()});

  final FaultLabBackend backend;

  @override
  State<FaultLabScreen> createState() => _FaultLabScreenState();
}

class _FaultLabScreenState extends State<FaultLabScreen> {
  late Future<List<FaultLabSource>> _sources = widget.backend.sources()
    ..then((sources) {
      if (mounted && sources.isNotEmpty) setState(() => _source ??= sources.first);
    });
  FaultLabSource? _source;
  FaultPreset _preset = kFaultPresets.first;

  bool _running = false;
  double _progress = 0;
  String? _error;
  FaultLabResult? _result;
  List<FaultLabResult>? _allResults;

  Future<void> _run() async {
    final source = _source;
    if (source == null) return;
    setState(() {
      _running = true;
      _error = null;
      _result = null;
      _allResults = null;
    });
    try {
      final result = await widget.backend.run(source, _preset.spec);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runAll() async {
    final source = _source;
    if (source == null) return;
    setState(() {
      _running = true;
      _progress = 0;
      _error = null;
      _result = null;
      _allResults = null;
    });
    try {
      final results = await widget.backend.runAll(
        source,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() => _allResults = results);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Fault Injection Lab')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Developer tool. Injects one fault into a replayed drive and '
            'reports, honestly, whether the navigation core noticed it and '
            'what it did - never a live measurement.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          _sourcePicker(),
          const SizedBox(height: AppSpacing.md),
          _faultPicker(),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _running || _source == null ? null : _run,
                  child: const Text('Run'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _running || _source == null ? null : _runAll,
                  child: const Text('Run all faults'),
                ),
              ),
            ],
          ),
          if (_running) _progressCard(),
          if (_error != null) _errorCard(),
          if (_result != null) _resultCard(_result!),
          if (_allResults != null) _allResultsTable(_allResults!),
        ],
      ),
    );
  }

  Widget _sourcePicker() {
    return FutureBuilder<List<FaultLabSource>>(
      future: _sources,
      builder: (context, snapshot) {
        final sources = snapshot.data;
        if (sources == null) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return StandardCard(
          titleText: 'SOURCE',
          child: DropdownButton<FaultLabSource>(
            isExpanded: true,
            value: _source,
            items: [
              for (final s in sources)
                DropdownMenuItem(value: s, child: Text(s.title)),
            ],
            onChanged: _running
                ? null
                : (s) => setState(() {
                      _source = s;
                      _result = null;
                      _allResults = null;
                    }),
          ),
        );
      },
    );
  }

  Widget _faultPicker() {
    return StandardCard(
      titleText: 'FAULT',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in kFaultPresets)
            ChoiceChip(
              label: Text(preset.label),
              selected: identical(_preset, preset),
              onSelected: _running
                  ? null
                  : (_) => setState(() {
                        _preset = preset;
                        _result = null;
                      }),
            ),
        ],
      ),
    );
  }

  Widget _progressCard() {
    return StandardCard(
      child: LinearProgressIndicator(value: _progress > 0 ? _progress : null),
    );
  }

  Widget _errorCard() {
    return StandardCard(
      child: Text('Could not run the lab: $_error',
          style: const TextStyle(color: AppColors.boardError)),
    );
  }

  Widget _resultCard(FaultLabResult r) {
    return StandardCard(
      titleText: 'RESULT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _block('Injected', r.injected),
          const SizedBox(height: AppSpacing.sm),
          _block(
            'Detected',
            r.detected
                ? 'Yes, after ${r.detectionLatencyS!.toStringAsFixed(1)} s '
                    '- ${r.mechanism}'
                : 'No',
          ),
          const SizedBox(height: AppSpacing.sm),
          _block('Action', r.action),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Impact vs. a clean replay: max ${r.maxErrorM.toStringAsFixed(0)} m, '
            'end ${r.endErrorM.toStringAsFixed(0)} m. '
            '${r.keptLeading ? 'The engine kept leading throughout.' : 'The engine handed back at some point during the fault.'}',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _block(String title, String body) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(body, style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
        ],
      );

  Widget _allResultsTable(List<FaultLabResult> results) {
    return StandardCard(
      titleText: 'ALL FAULTS',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Fault')),
            DataColumn(label: Text('Detected?')),
            DataColumn(label: Text('Latency')),
            DataColumn(label: Text('Action')),
            DataColumn(label: Text('Max error')),
          ],
          rows: [
            for (var i = 0; i < results.length; i++)
              DataRow(cells: [
                DataCell(SizedBox(
                    width: 160, child: Text(kFaultPresets[i].label))),
                DataCell(Text(results[i].detected ? 'Yes' : 'No')),
                DataCell(Text(results[i].detectionLatencyS == null
                    ? '--'
                    : '${results[i].detectionLatencyS!.toStringAsFixed(1)} s')),
                DataCell(SizedBox(
                    width: 220, child: Text(results[i].action))),
                DataCell(Text('${results[i].maxErrorM.toStringAsFixed(0)} m')),
              ]),
          ],
        ),
      ),
    );
  }
}
