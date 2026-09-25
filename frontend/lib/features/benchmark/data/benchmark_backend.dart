import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/nav/benchmark/benchmark_job.dart';
import '../../../core/nav/benchmark/field_evidence.dart';
import '../../../core/nav/benchmark/outage_report.dart';
import '../../../core/platform/evidence/android_evidence_signer.dart';
import '../../../core/platform/storage/drive_log_store.dart';
import 'benchmark_report_exporter.dart';

/// A drive the benchmark can be run on.
@immutable
class BenchmarkSource {
  const BenchmarkSource({
    required this.title,
    required this.subtitle,
    required this.simulated,
    this.asset,
    this.path,
  }) : assert(asset != null || path != null);

  final String title;
  final String subtitle;

  /// Simulated sensors: a bound on the engine, never a field measurement.
  final bool simulated;

  /// Bundled log, or
  final String? asset;

  /// a drive recorded on this phone.
  final String? path;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "drive-20260920T155523266723.jsonl" -> "20 Sep 2026, 15:55" (the phone's
/// local time, which is what the recorder stamps). Anything else is returned
/// unchanged.
String friendlyDriveName(String fileName) {
  final m = RegExp(r'^drive-(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})\d{2}')
      .firstMatch(fileName);
  if (m == null) return fileName;
  final month = int.parse(m[2]!);
  if (month < 1 || month > 12) return fileName;
  return '${int.parse(m[3]!)} ${_months[month - 1]} ${m[1]}, ${m[4]}:${m[5]}';
}

String _size(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).round()} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Where the benchmark screen gets its drives and how it scores them. An
/// interface so the screen can be tested without isolates, assets or storage.
abstract class BenchmarkBackend {
  Future<List<BenchmarkSource>> sources();

  Future<OutageReport> run(
    BenchmarkSource source, {
    void Function(double progress)? onProgress,
  });

  /// Opens the phone's share sheet with a compressed copy of a recorded drive.
  Future<void> share(BenchmarkSource source);

  /// Builds and shares a device-key-signed, machine-readable result. The raw
  /// route stays out of the report; only reproducibility metadata and metrics
  /// are included.
  Future<void> shareEvidence(BenchmarkSource source, OutageReport report);

  /// Builds one exportable report (JSON, CSV or PDF - see [ReportFormat]) from
  /// an already-run [report] and hands it to the share sheet. Like
  /// [shareEvidence], the raw route stays out of it.
  Future<void> shareReport(
    BenchmarkSource source,
    OutageReport report,
    ReportFormat format,
  );

  /// Deletes a recorded drive from this phone. False when there was nothing to
  /// delete or it failed.
  Future<bool> delete(BenchmarkSource source);
}

/// The real thing: the bundled reference drive plus every drive this phone has
/// recorded, scored on a background isolate.
class DeviceBenchmarkBackend implements BenchmarkBackend {
  const DeviceBenchmarkBackend();

  static const referenceAsset = 'assets/benchmarks/reference_city_drive.jsonl';

  @override
  Future<List<BenchmarkSource>> sources() async {
    final recorded = await DriveLogStore.list();
    return [
      const BenchmarkSource(
        title: 'Reference city drive',
        subtitle: 'Bundled, identical on every phone. Simulated sensors.',
        simulated: true,
        asset: referenceAsset,
      ),
      for (final log in recorded)
        BenchmarkSource(
          title: friendlyDriveName(log.name),
          subtitle: 'Recorded on this phone, ${_size(log.sizeBytes)}',
          simulated: false,
          path: log.path,
        ),
    ];
  }

  @override
  Future<OutageReport> run(
    BenchmarkSource source, {
    void Function(double progress)? onProgress,
  }) async {
    final job = source.asset != null
        ? BenchmarkJob(
            label: '${source.title} (simulated)',
            text: await rootBundle.loadString(source.asset!),
          )
        : BenchmarkJob(label: source.title, path: source.path);
    return runBenchmarkJobInBackground(job, onProgress: onProgress);
  }

  /// Shares a gzip copy: an hour of riding is ~30 MB of JSON lines, which many
  /// share targets refuse, and it compresses about 5x. The original stays put.
  @override
  Future<void> share(BenchmarkSource source) async {
    final path = source.path;
    if (path == null) return;
    final cache = await getTemporaryDirectory();
    // Earlier exports are only needed while a share is in flight.
    for (final old in cache.listSync().whereType<File>()) {
      if (old.path.endsWith('.jsonl.gz')) old.deleteSync();
    }
    final name = File(path).uri.pathSegments.last;
    final copy = File('${cache.path}/$name.gz');
    await File(path).openRead().transform(gzip.encoder).pipe(copy.openWrite());
    await SharePlus.instance.share(ShareParams(
      files: [XFile(copy.path, mimeType: 'application/gzip')],
      subject: 'GatiSaarth drive log',
      text: 'GatiSaarth drive log $name (gzip-compressed JSONL)',
    ));
  }

  @override
  Future<void> shareEvidence(
    BenchmarkSource source,
    OutageReport report,
  ) async {
    final log = source.asset != null
        ? await rootBundle.loadString(source.asset!)
        : await File(source.path!).readAsString();
    final evidence = await const FieldEvidenceBuilder(
      signer: AndroidEvidenceSigner(),
    ).build(
      report: report,
      driveLog: log,
      simulated: source.simulated,
    );
    final cache = await getTemporaryDirectory();
    final safeName = (source.path == null
            ? 'reference-drive'
            : File(source.path!).uri.pathSegments.last)
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File('${cache.path}/$safeName.evidence.json');
    await file.writeAsString(evidence.toJson(), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: 'GatiSaarth signed field evidence',
      text: source.simulated
          ? 'Signed GatiSaarth simulated benchmark evidence'
          : 'Signed GatiSaarth field-validation evidence',
    ));
  }

  @override
  Future<void> shareReport(
    BenchmarkSource source,
    OutageReport report,
    ReportFormat format,
  ) async {
    final log = source.asset != null
        ? await rootBundle.loadString(source.asset!)
        : await File(source.path!).readAsString();
    const exporter = BenchmarkReportExporter();
    final exported = await exporter.build(
      report: report,
      driveLog: log,
      simulated: source.simulated,
    );
    final cache = await getTemporaryDirectory();
    final safeName = (source.path == null
            ? 'reference-drive'
            : File(source.path!).uri.pathSegments.last)
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final (suffix, mime, bytes) = switch (format) {
      ReportFormat.json => (
          'report.json',
          'application/json',
          utf8.encode(exported.toJsonText()),
        ),
      ReportFormat.csv => (
          'report.csv',
          'text/csv',
          utf8.encode(exporter.toCsv(report, simulated: source.simulated)),
        ),
      ReportFormat.pdf => (
          'report.pdf',
          'application/pdf',
          await exporter.toPdfBytes(report,
              simulated: source.simulated, exported: exported),
        ),
    };
    final file = File('${cache.path}/$safeName.$suffix');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: mime)],
      subject: 'GatiSaarth benchmark report',
      text: 'GatiSaarth benchmark report ($suffix), SHA-256 '
          '${exported.sha256Short}...',
    ));
  }

  @override
  Future<bool> delete(BenchmarkSource source) async {
    final path = source.path;
    return path != null && await DriveLogStore.delete(path);
  }
}
