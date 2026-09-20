import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/benchmark_job.dart';

/// Scores a drive recorded on any phone, headless, with the same code the app
/// runs on the phone:
///
///     DRIVE_LOG=C:\path\to\drive-2026....jsonl flutter test test/nav/score_drive_test.dart
///
/// Skipped when DRIVE_LOG is not set, so it never fails a normal test run.
void main() {
  final path = Platform.environment['DRIVE_LOG'];

  test('scores the drive named by DRIVE_LOG', () {
    final report = runBenchmarkJob(BenchmarkJob(label: path!, path: path));
    // ignore: avoid_print
    print(report.toText());
    // ignore: avoid_print
    print(report.headline);
  }, skip: path == null ? 'set DRIVE_LOG to a .jsonl drive log' : false);
}
