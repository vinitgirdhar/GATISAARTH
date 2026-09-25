import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/benchmark_job.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

/// A/B of the coordinated-turn speed on REAL IO-VNBD trips: the same logs,
/// the same outage windows, the engine with `FeatureFlags.turnSpeed` off and
/// on. IMU = the car's ESP/CAN channels (external-IMU proxy), GNSS = VBOX
/// 1 Hz, truth = the withheld fixes; see iovnbd_outage_benchmark_test.dart.
///
///     IOVNBD_LOG_DIR=ml/data/processed/drive_logs_vehicle EVIDENCE_DIR=docs/evidence \
///         flutter test test/nav/iovnbd_turn_speed_ab_test.dart
void main() {
  final dir = Platform.environment['IOVNBD_LOG_DIR'];
  final out = Platform.environment['EVIDENCE_DIR'];

  test('turn speed on real IO-VNBD drives, off vs on',
      skip:
          dir == null ? 'set IOVNBD_LOG_DIR to a folder of drive logs' : false,
      timeout: const Timeout(Duration(minutes: 90)), () async {
    final files = Directory(dir!)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl') || f.path.endsWith('.jsonl.gz'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);

    const configs = {
      'off': NavConfig(),
      'on': NavConfig(features: FeatureFlags(turnSpeed: true)),
      // Error model matched to the accuracy measured against VBOX speed on
      // real turns while GNSS was live (bias <= 0.4 m/s, RMS 0.95-1.35 m/s).
      'on_matched': NavConfig(
        features: FeatureFlags(turnSpeed: true),
        turnSpeed: TurnSpeedConfig(accelSigma: 0.22, yawRateSigma: 0.008),
      ),
    };
    // trip -> config -> seconds -> (median drift %, median error m, n)
    final perTrip = <String, Map<String, Map<int, (double, double, int)>>>{};
    for (final file in files) {
      final label = file.uri.pathSegments.last;
      for (final entry in configs.entries) {
        try {
          final report = await runBenchmarkJob(BenchmarkJob(
              label: label, path: file.path, engineConfig: entry.value));
          for (final d in report.durations) {
            perTrip
                    .putIfAbsent(label, () => {})
                    .putIfAbsent(entry.key, () => {})[d.durationS] =
                (d.engine.medianDriftPct, d.engine.medianM, d.n);
          }
        } catch (_) {
          // Same skip rule as the main benchmark: a trip that fails is absent.
        }
      }
    }

    final summary = <String, Object?>{
      'what': 'Coordinated-turn speed (v = a_lat / yaw rate) A/B on real '
          'IO-VNBD trips. IMU = vehicle ESP/CAN (external-IMU proxy, 10 Hz), '
          'GNSS = VBOX 1 Hz, truth = withheld fixes. Median over trips of each '
          "trip's median drift; only trips scored (n >= 3) in both runs count.",
    };
    for (final seconds in const [10, 30, 60, 120]) {
      final off = <double>[],
          on = <double>[],
          offM = <double>[],
          onM = <double>[];
      final matched = <double>[], matchedM = <double>[];
      var better = 0, worse = 0;
      for (final trip in perTrip.values) {
        final a = trip['off']?[seconds], b = trip['on']?[seconds];
        if (a == null || b == null || a.$3 < 3 || b.$3 < 3) continue;
        off.add(a.$1);
        on.add(b.$1);
        offM.add(a.$2);
        onM.add(b.$2);
        final c = trip['on_matched']?[seconds];
        if (c != null && c.$3 >= 3) {
          matched.add(c.$1);
          matchedM.add(c.$2);
        }
        if (b.$2 < a.$2 - 0.5) better++;
        if (b.$2 > a.$2 + 0.5) worse++;
      }
      if (off.isEmpty) continue;
      summary['${seconds}s'] = {
        'trips': off.length,
        'off_drift_pct': _r(_median(off)),
        'on_drift_pct': _r(_median(on)),
        'off_error_m': _r(_median(offM)),
        'on_error_m': _r(_median(onM)),
        'trips_better': better,
        'trips_worse': worse,
        if (matched.isNotEmpty) 'matched_drift_pct': _r(_median(matched)),
        if (matchedM.isNotEmpty) 'matched_error_m': _r(_median(matchedM)),
        'matched_trips_under_10_pct': matched.where((d) => d < 10).length,
        'off_trips_under_10_pct': off.where((d) => d < 10).length,
        'on_trips_under_10_pct': on.where((d) => d < 10).length,
      };
    }
    summary['per_trip'] = {
      for (final e in perTrip.entries)
        e.key: {
          for (final c in e.value.entries)
            c.key: {
              for (final d in c.value.entries)
                '${d.key}s': {
                  'drift_pct': _r(d.value.$1),
                  'error_m': _r(d.value.$2),
                  'n': d.value.$3
                },
            },
        },
    };
    final json = const JsonEncoder.withIndent('  ').convert(summary);
    // ignore: avoid_print
    print(json);
    if (out != null) {
      File('$out/iovnbd_turn_speed_ab.json').writeAsStringSync(json);
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
