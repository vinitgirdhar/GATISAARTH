import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/nav/benchmark/fault_injection.dart';
import '../../../core/nav/benchmark/fault_lab.dart';
import '../../../core/nav/benchmark/fault_lab_job.dart';
import '../../../core/platform/storage/drive_log_store.dart';
import '../../benchmark/data/benchmark_backend.dart' show friendlyDriveName;

/// A drive the Fault Injection Lab can replay - the same bundled simulated
/// reference drive the Outage Benchmark uses, or any drive recorded on this
/// phone.
@immutable
class FaultLabSource {
  const FaultLabSource({
    required this.title,
    required this.subtitle,
    required this.simulated,
    this.asset,
    this.path,
  }) : assert(asset != null || path != null);

  final String title;
  final String subtitle;
  final bool simulated;
  final String? asset;
  final String? path;
}

/// Where the lab gets its drives and how it runs faults on them. An interface
/// so the screen can be tested without isolates or storage.
abstract class FaultLabBackend {
  Future<List<FaultLabSource>> sources();

  Future<FaultLabResult> run(FaultLabSource source, FaultSpec spec);

  /// Runs every preset in [kFaultPresets] against [source], in order.
  Future<List<FaultLabResult>> runAll(
    FaultLabSource source, {
    void Function(double progress)? onProgress,
  });
}

/// The real thing: the bundled reference drive plus every drive this phone
/// has recorded, replayed twice per fault on a background isolate.
class DeviceFaultLabBackend implements FaultLabBackend {
  const DeviceFaultLabBackend();

  static const referenceAsset = 'assets/benchmarks/reference_city_drive.jsonl';

  @override
  Future<List<FaultLabSource>> sources() async {
    final recorded = await DriveLogStore.list();
    return [
      const FaultLabSource(
        title: 'Simulated reference drive',
        subtitle: 'Bundled, identical on every phone. Simulated sensors.',
        simulated: true,
        asset: referenceAsset,
      ),
      for (final log in recorded)
        FaultLabSource(
          title: friendlyDriveName(log.name),
          subtitle: 'Recorded on this phone',
          simulated: false,
          path: log.path,
        ),
    ];
  }

  @override
  Future<FaultLabResult> run(FaultLabSource source, FaultSpec spec) async {
    final results = await runFaultLabJobInBackground(await _job(source, [spec]));
    return results.single;
  }

  @override
  Future<List<FaultLabResult>> runAll(
    FaultLabSource source, {
    void Function(double progress)? onProgress,
  }) async {
    return runFaultLabJobInBackground(
      await _job(source, [for (final p in kFaultPresets) p.spec]),
      onProgress: onProgress,
    );
  }

  Future<FaultLabJob> _job(FaultLabSource source, List<FaultSpec> specs) async {
    return source.asset != null
        ? FaultLabJob(
            label: source.title,
            specs: specs,
            text: await rootBundle.loadString(source.asset!))
        : FaultLabJob(label: source.title, specs: specs, path: source.path);
  }
}
