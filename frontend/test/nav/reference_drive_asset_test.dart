import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_benchmark.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

import 'support/reference_drive.dart';

/// The drive every phone benchmarks against, so results are comparable across
/// devices. It is generated, not hand-edited: this test fails if the bundled
/// file drifts from the generator, and regenerates it on request:
///
///     UPDATE_REFERENCE_DRIVE=1 flutter test test/nav/reference_drive_asset_test.dart
const _asset = 'assets/benchmarks/reference_city_drive.jsonl';

String _generate() => '${simulateDriveLog(segments: referenceCityDrive()).map((r) => r.toJsonLine()).join('\n')}\n';

void main() {
  test('the bundled reference drive is exactly what the generator produces', () {
    final file = File(_asset);
    if (Platform.environment['UPDATE_REFERENCE_DRIVE'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(_generate());
    }
    expect(file.existsSync(), isTrue, reason: 'run with UPDATE_REFERENCE_DRIVE=1');
    expect(file.readAsStringSync(), _generate());
  });

  test('the bundled drive replays and scores end to end', () {
    final records = File(_asset)
        .readAsLinesSync()
        .map(DriveRecord.fromJsonLine)
        .whereType<DriveRecord>()
        .toList();
    final report = OutageBenchmark.run(records, source: 'reference city drive (simulated)');
    // ignore: avoid_print
    print(report.toText());
    expect(report.durations, isNotEmpty);
    expect(report.coreLedFromS, isNotNull);
  });
}
