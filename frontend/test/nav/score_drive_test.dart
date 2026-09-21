import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/benchmark_job.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

/// Scores a drive recorded on any phone, headless, with the same code the app
/// runs on the phone:
///
///     DRIVE_LOG=C:\path\to\drive-2026....jsonl flutter test test/nav/score_drive_test.dart
///
/// Set NAV_AI=1 to replay with the AI path on (`AiConfig.enabled`): the `ai`
/// records in the log (model outputs a phone recorded, or a Python job
/// injected) are then used, and the report is the drive scored with them.
///
/// Skipped when DRIVE_LOG is not set, so it never fails a normal test run.
void main() {
  final path = Platform.environment['DRIVE_LOG'];
  final ai = Platform.environment['NAV_AI'] == '1';

  test('scores the drive named by DRIVE_LOG', () {
    final report = runBenchmarkJob(BenchmarkJob(
      label: ai ? '$path (AI on)' : path!,
      path: path!,
      engineConfig: NavConfig(ai: AiConfig(enabled: ai)),
    ));
    // ignore: avoid_print
    print(report.toText());
    // ignore: avoid_print
    print(report.headline);
  }, skip: path == null ? 'set DRIVE_LOG to a .jsonl drive log' : false);
}
