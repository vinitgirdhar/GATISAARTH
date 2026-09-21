import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../nav_config.dart';
import '../replay/drive_log.dart';
import 'outage_benchmark.dart';
import 'outage_report.dart';

/// One benchmark run: a drive log (as text or as a file on this phone) and how
/// to score it. Plain data, so it can cross to a background isolate.
class BenchmarkJob {
  const BenchmarkJob({
    required this.label,
    this.text,
    this.path,
    this.config = const OutageBenchmarkConfig(),
    this.engineConfig = NavConfig.defaults,
  }) : assert(text != null || path != null);

  final String label;

  /// The whole JSONL log, for bundled drives.
  final String? text;

  /// A JSONL log on disk, for drives recorded on this phone.
  final String? path;

  final OutageBenchmarkConfig config;

  /// The navigation core's configuration for the replay (AI on or off).
  final NavConfig engineConfig;
}

/// Parses the log and scores it. Throws [FormatException] when nothing in it is
/// readable, rather than reporting an empty result as if it were a finding.
OutageReport runBenchmarkJob(
  BenchmarkJob job, {
  void Function(double progress)? onProgress,
}) {
  final lines = job.text != null
      ? job.text!.split('\n')
      : job.path!.endsWith('.gz')
          // What the app's Share action sends: the same JSONL, compressed.
          ? utf8
              .decode(gzip.decode(File(job.path!).readAsBytesSync()))
              .split('\n')
          : File(job.path!).readAsLinesSync();
  final records = <DriveRecord>[];
  for (final line in lines) {
    final record = DriveRecord.fromJsonLine(line);
    if (record != null) records.add(record);
  }
  if (records.isEmpty) {
    throw FormatException('${job.label} has no readable drive records');
  }
  return OutageBenchmark.run(
    records,
    config: job.config,
    engineConfig: job.engineConfig,
    source: job.label,
    onProgress: onProgress,
  );
}

/// Runs [job] on a background isolate: a replay takes seconds on a phone and
/// must not freeze the screen it is reporting progress on.
Future<OutageReport> runBenchmarkJobInBackground(
  BenchmarkJob job, {
  void Function(double progress)? onProgress,
}) async {
  final port = ReceivePort();
  final done = Completer<OutageReport>();
  late final StreamSubscription<dynamic> subscription;
  subscription = port.listen((message) {
    if (message is double) {
      onProgress?.call(message);
    } else if (message is OutageReport) {
      done.complete(message);
    } else if (!done.isCompleted) {
      // Anything else is an error: a String from our own catch, or the
      // [error, stack] list the isolate reports if it dies outright.
      done.completeError(message is List ? message.first : message);
    }
  });

  try {
    await Isolate.spawn(
      _entry,
      (port.sendPort, job),
      onError: port.sendPort,
    );
    return await done.future;
  } finally {
    await subscription.cancel();
    port.close();
  }
}

void _entry((SendPort, BenchmarkJob) args) {
  final (port, job) = args;
  try {
    port.send(runBenchmarkJob(job, onProgress: port.send));
  } catch (e) {
    port.send(e.toString());
  }
}
