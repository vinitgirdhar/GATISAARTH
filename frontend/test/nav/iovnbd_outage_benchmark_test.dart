import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/benchmark_job.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_report.dart';

/// Scores the app's own navigation engine on REAL IO-VNBD trips, with the same
/// outage benchmark the phone runs on its own recordings.
///
/// The drive logs are made by `ml/src/dataset/iovnbd_to_drive_log.py`:
///
///     python ml/src/dataset/iovnbd_to_drive_log.py --imu vehicle --all \
///         --out ml/data/processed/drive_logs_vehicle
///     IOVNBD_LOG_DIR=ml/data/processed/drive_logs_vehicle EVIDENCE_DIR=docs/evidence \
///         flutter test test/nav/iovnbd_outage_benchmark_test.dart
///
/// IMU = the car's own ESP/CAN channels standing in for an external IMU
/// (planar, vehicle frame); GNSS = the VBOX at 1 Hz; truth = the fixes withheld
/// during each simulated blackout. Skipped when the folder is not set.
void main() {
  final dir = Platform.environment['IOVNBD_LOG_DIR'];
  final out = Platform.environment['EVIDENCE_DIR'];

  test('the navigation core on real IO-VNBD drives',
      skip: dir == null ? 'set IOVNBD_LOG_DIR to a folder of drive logs' : false,
      timeout: const Timeout(Duration(minutes: 40)), () async {
    final files = Directory(dir!)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl') || f.path.endsWith('.jsonl.gz'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);

    final trips = <Map<String, Object?>>[];
    // Every scored window of every trip, per duration: (hold error, core error, distance).
    final pooled = <int, List<(double, double, double)>>{};
    for (final file in files) {
      final label = file.uri.pathSegments.last;
      final OutageReport report;
      try {
        report = await runBenchmarkJob(BenchmarkJob(label: label, path: file.path));
      } catch (e) {
        trips.add({'trip': label, 'error': '$e'});
        continue;
      }
      final row = <String, Object?>{
        'trip': label,
        'minutes': double.parse((report.profile.durationS / 60).toStringAsFixed(1)),
        'core_led_from_s': report.coreLedFromS?.round(),
        'windows_tried': report.windowsTried,
      };
      for (final d in report.durations) {
        row['${d.durationS}s'] = {
          'n': d.n,
          'core_median_m': _r(d.engine.medianM),
          'core_drift_median_pct': _r(d.engine.medianDriftPct),
          'hold_median_m': _r(d.hold.medianM),
          'hold_drift_median_pct': _r(d.hold.medianDriftPct),
          'core_closer_than_hold': '${d.engineWins}/${d.n}',
        };
      }
      trips.add(row);
    }

    final summary = <String, Object?>{
      'what': 'The app\'s navigation core replayed on real IO-VNBD trips: '
          'IMU = vehicle ESP/CAN channels (external-IMU proxy, 10 Hz), '
          'GNSS = VBOX 1 Hz, blackouts withheld at many start times, error = '
          'distance to the withheld fix. Not a phone-IMU result.',
      'trips_scored': trips.where((t) => !t.containsKey('error')).length,
      'trips': trips,
    };
    // Median over trips of each trip's median, per duration.
    for (final seconds in const [10, 30, 60, 120]) {
      final drifts = <double>[];
      final holds = <double>[];
      for (final t in trips) {
        final d = t['${seconds}s'];
        if (d is Map && (d['n'] as int) >= 3) {
          drifts.add((d['core_drift_median_pct'] as num).toDouble());
          holds.add((d['hold_drift_median_pct'] as num).toDouble());
        }
      }
      if (drifts.isEmpty) continue;
      summary['median_over_trips_${seconds}s'] = {
        'trips': drifts.length,
        'core_drift_pct': _r(_median(drifts)),
        'hold_velocity_drift_pct': _r(_median(holds)),
        'core_trips_under_10_percent':
            drifts.where((d) => d < 10).length,
      };
    }
    pooled.clear();

    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(summary));
    if (out != null) {
      File('$out/iovnbd_outage_benchmark.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(summary));
    }
  });
}

double _r(double v) => double.parse(v.toStringAsFixed(2));

double _median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[math.min(mid, sorted.length - 1)]) / 2;
}
