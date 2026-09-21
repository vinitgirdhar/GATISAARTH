import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_benchmark.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_report.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

void main() {
  final path = Platform.environment['AI_DRIVE_LOG'];
  test('real IO-VNBD replay with AI off and conservative assistance on',
      skip: path == null ? 'set AI_DRIVE_LOG for real-data ablation' : false,
      timeout: const Timeout(Duration(minutes: 15)), () {
    final records = File(path!)
        .readAsLinesSync()
        .map(DriveRecord.fromJsonLine)
        .whereType<DriveRecord>()
        .toList();
    const bench = OutageBenchmarkConfig(
        durationsS: [10, 30, 60, 120], strideS: 120, maxStarts: 12);
    final rows = <String, Object?>{};
    for (final enabled in [false, true]) {
      final report = OutageBenchmark.run(records,
          config: bench,
          engineConfig:
              NavConfig(ai: AiConfig(enabled: enabled, fusionTrust: false)));
      rows[enabled ? 'on' : 'off'] = [
        for (final d in report.durations)
          {
            'seconds': d.durationS,
            'windows': d.n,
            'median_drift_pct': d.engine.medianDriftPct,
            'median_error_m': d.engine.medianM,
            'p95_error_m': d.engine.p95M,
          }
      ];
    }
    final out = Platform.environment['AI_EVIDENCE'];
    if (out != null)
      File(out)
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
    // This is evidence collection, not an assertion that real data meets the target.
    expect(rows.length, 2);
  });
}
