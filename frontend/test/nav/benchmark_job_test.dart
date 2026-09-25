import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/benchmark_job.dart';

import 'support/drive_simulator.dart';
import 'support/reference_drive.dart';

void main() {
  late Directory dir;
  late String jsonl;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('benchmark_job_test');
    jsonl = simulateDriveLog(
      setup: referenceSetupDrive(),
      segments: const [
        DriveSegment(seconds: 8, longitudinalAccel: 2.0),
        DriveSegment(seconds: 120),
      ],
    ).map((r) => r.toJsonLine()).join('\n');
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  test('a compressed drive scores exactly like the plain one', () async {
    final plain = File('${dir.path}/drive.jsonl')..writeAsStringSync(jsonl);
    final packed = File('${dir.path}/drive.jsonl.gz')
      ..writeAsBytesSync(gzip.encode(utf8.encode(jsonl)));

    final a =
        await runBenchmarkJob(BenchmarkJob(label: 'drive', path: plain.path));
    final b = await runBenchmarkJob(
        BenchmarkJob(label: 'drive', path: packed.path));

    expect(b.durations, isNotEmpty);
    expect(b.toText(), a.toText());
  });

  test('a file with nothing readable in it is an error, not an empty result',
      () async {
    final junk = File('${dir.path}/junk.jsonl')..writeAsStringSync('not json\n');
    await expectLater(
      () => runBenchmarkJob(BenchmarkJob(label: 'junk', path: junk.path)),
      throwsA(isA<FormatException>()),
    );
  });
}
