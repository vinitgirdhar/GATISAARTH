import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../motion/motion_classifier.dart' show VehicleClass;
import '../nav_config.dart';
import '../replay/drive_log.dart';
import 'fault_injection.dart';
import 'fault_lab.dart';

/// One Fault Injection Lab run: a drive log (bundled text or a file on this
/// phone) and the faults to inject into it, one result each. Plain data, so
/// it can cross to a background isolate the same way [BenchmarkJob] does.
class FaultLabJob {
  const FaultLabJob({
    required this.label,
    this.text,
    this.path,
    required this.specs,
    this.engineConfig = NavConfig.defaults,
    this.vehicleClass = VehicleClass.car,
  }) : assert(text != null || path != null),
       assert(specs.length > 0);

  final String label;
  final String? text;
  final String? path;

  /// One fault per requested run - a single pick, or every preset for
  /// "Run all faults".
  final List<FaultSpec> specs;

  final NavConfig engineConfig;
  final VehicleClass vehicleClass;
}

/// Parses the log and runs every fault in [job.specs] against it, clean vs.
/// faulted. Throws [FormatException] when nothing in the log is readable.
Future<List<FaultLabResult>> runFaultLabJob(
  FaultLabJob job, {
  void Function(double progress)? onProgress,
}) async {
  final lines = job.text != null
      ? job.text!.split('\n')
      : job.path!.endsWith('.gz')
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

  final results = <FaultLabResult>[];
  for (var i = 0; i < job.specs.length; i++) {
    results.add(FaultLab.run(
      records,
      job.specs[i],
      config: job.engineConfig,
      vehicleClass: job.vehicleClass,
    ));
    onProgress?.call((i + 1) / job.specs.length);
  }
  return results;
}

/// Runs [job] on a background isolate: replaying a drive twice per fault
/// takes real seconds and must not freeze the screen showing progress.
Future<List<FaultLabResult>> runFaultLabJobInBackground(
  FaultLabJob job, {
  void Function(double progress)? onProgress,
}) async {
  final port = ReceivePort();
  final done = Completer<List<FaultLabResult>>();
  late final StreamSubscription<dynamic> subscription;
  subscription = port.listen((message) {
    if (message is double) {
      onProgress?.call(message);
    } else if (message is List<FaultLabResult>) {
      done.complete(message);
    } else if (!done.isCompleted) {
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

void _entry((SendPort, FaultLabJob) args) async {
  final (port, job) = args;
  try {
    port.send(await runFaultLabJob(job, onProgress: port.send));
  } catch (e) {
    port.send(e.toString());
  }
}
