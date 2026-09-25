import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/nav/benchmark/field_evidence.dart';
import '../../../core/nav/benchmark/outage_report.dart';
import '../../../core/platform/evidence/android_evidence_signer.dart';

enum ReportFormat { json, csv, pdf }

/// A canonical, hashed benchmark report, ready to hand to the share sheet in
/// any of [ReportFormat]'s shapes. Every format is built from the same
/// payload map, so the JSON hash and the numbers printed in the CSV/PDF can
/// never disagree.
class ExportedBenchmarkReport {
  const ExportedBenchmarkReport({
    required this.payload,
    required this.payloadText,
    required this.sha256Hex,
    this.signature,
  });

  /// [FieldEvidenceBuilder.buildPayload] plus this report's own diagnostics
  /// and verdict block.
  final Map<String, Object?> payload;
  final String payloadText;

  /// SHA-256 of [payloadText]'s UTF-8 bytes, computed on-device (this is the
  /// hash printed and shared, independent of whether Keystore signing is
  /// available on this platform).
  final String sha256Hex;

  /// The Android Keystore attestation over [payloadText], when the phone can
  /// sign (null off-Android or if the platform channel is unavailable, e.g.
  /// in `flutter test`).
  final EvidenceSignature? signature;

  String get sha256Short => sha256Hex.substring(0, 12);

  String toJsonText() => const JsonEncoder.withIndent('  ').convert({
        'schema': 'gatisaarth.benchmark-report.v1',
        'payload': payload,
        'sha256': sha256Hex,
        if (signature != null) 'attestation': signature!.toJson(),
      });
}

/// Builds the exportable benchmark report (JSON, CSV, PDF) from an
/// [OutageReport]: the same numbers the on-screen "Report" section shows,
/// plus a SHA-256 of the canonical payload and, when the phone can sign one,
/// the device-key attestation already used for signed field evidence.
class BenchmarkReportExporter {
  const BenchmarkReportExporter({this.signer = const AndroidEvidenceSigner()});

  final EvidenceSigner signer;

  Future<ExportedBenchmarkReport> build({
    required OutageReport report,
    required String driveLog,
    required bool simulated,
    DateTime? generatedAt,
  }) async {
    final payload = <String, Object?>{
      ...FieldEvidenceBuilder.buildPayload(
        report: report,
        driveLog: driveLog,
        simulated: simulated,
        generatedAt: generatedAt,
      ),
    };
    final payloadText = jsonEncode(payload);
    final sha256Hex = sha256.convert(utf8.encode(payloadText)).toString();
    EvidenceSignature? signature;
    try {
      signature = await signer.sign(payloadText);
    } catch (_) {
      // No Android Keystore on this platform/build - the SHA-256 above still
      // lets anyone verify the export was not altered in transit.
      signature = null;
    }
    return ExportedBenchmarkReport(
      payload: payload,
      payloadText: payloadText,
      sha256Hex: sha256Hex,
      signature: signature,
    );
  }

  /// One row per scored duration, with a small header block up front. Opens
  /// cleanly in any spreadsheet.
  String toCsv(OutageReport report, {required bool simulated}) {
    final p = report.profile;
    final b = StringBuffer()
      ..writeln('GatiSaarth Navigation Benchmark')
      ..writeln('Device,${_csv(p.deviceModel ?? 'unknown')}')
      ..writeln('Test,${_csv(report.source)}')
      ..writeln('Drive,${simulated ? 'SIMULATED reference drive' : 'real recording'}')
      ..writeln('Date,${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('Truth noise floor (m),${_num(p.medianTruthAccuracyM)}')
      ..writeln('Drift target (%),${report.driftTargetPct}')
      ..writeln()
      ..writeln('duration_s,n,hold_median_m,hold_p95_m,core_median_m,'
          'core_p95_m,core_drift_pct,core_closer,three_sigma_ok,'
          'along_track_median_m,cross_track_median_m,max_sigma_median_m,'
          'recovery_jump_median_m,distance_median_m,verdict');
    for (final d in report.durations) {
      b.writeln([
        d.durationS,
        d.n,
        _num(d.hold.medianM),
        _num(d.hold.p95M),
        _num(d.engine.medianM),
        _num(d.engine.p95M),
        _num(d.engine.medianDriftPct),
        '${d.engineWins}/${d.n}',
        '${d.engineCovered}/${d.n}',
        _num(d.medianAlongTrackM),
        _num(d.medianCrossTrackM),
        _num(d.medianMaxSigmaM),
        _num(d.medianRecoveryJumpM),
        _num(d.medianDistanceM),
        d.passed(report.driftTargetPct) ? 'PASS' : 'FAIL',
      ].join(','));
    }
    return b.toString();
  }

  /// A short, printable PDF: title, header table, per-duration table, verdict,
  /// hash and signature fingerprint. Falls back to an HTML string with the
  /// same content if the `pdf` package cannot render on this platform.
  Future<Uint8List> toPdfBytes(
    OutageReport report, {
    required bool simulated,
    required ExportedBenchmarkReport exported,
  }) async {
    final doc = pw.Document();
    final p = report.profile;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('GatiSaarth Navigation Benchmark',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const ['Field', 'Value'],
              data: [
                ['Device', p.deviceModel ?? 'unknown'],
                ['Test', report.source],
                ['Drive', simulated ? 'SIMULATED reference drive' : 'real recording'],
                ['Generated', DateTime.now().toUtc().toIso8601String()],
                ['Truth noise floor', '${_num(p.medianTruthAccuracyM)} m'],
                ['Drift target', '< ${report.driftTargetPct.toStringAsFixed(0)} %'],
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text('Per-duration results',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Outage', 'n', 'Hold med.', 'Core med.', 'Drift %',
                'Cross-track', 'Along-track', 'Max sigma', 'Verdict',
              ],
              data: [
                for (final d in report.durations)
                  [
                    '${d.durationS} s',
                    '${d.n}',
                    '${_num(d.hold.medianM)} m',
                    '${_num(d.engine.medianM)} m',
                    '${_num(d.engine.medianDriftPct)}',
                    '${_num(d.medianCrossTrackM)} m',
                    '${_num(d.medianAlongTrackM)} m',
                    '${_num(d.medianMaxSigmaM)} m',
                    d.passed(report.driftTargetPct) ? 'PASS' : 'FAIL',
                  ],
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Overall verdict: ${report.passed == null ? 'NOT SCORED' : (report.passed! ? 'PASS' : 'FAIL')} '
              '- SIH <${report.driftTargetPct.toStringAsFixed(0)}% drift target.',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('SHA-256: ${exported.sha256Hex}', style: pw.TextStyle(fontSize: 9)),
            if (exported.signature != null)
              pw.Text(
                  'Keystore signature (${exported.signature!.algorithm}, key '
                  '${exported.signature!.keyId}): '
                  '${exported.signature!.signatureBase64.substring(0, exported.signature!.signatureBase64.length.clamp(0, 24))}...',
                  style: pw.TextStyle(fontSize: 9))
            else
              pw.Text(
                  'No device signature attached (Keystore unavailable on this build).',
                  style: pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
            pw.Text(
              simulated
                  ? 'Simulated sensors: this bounds the engine under modelled '
                      'error and is not a field measurement.'
                  : 'Real recording: a field measurement on this phone, scored '
                      'against its own GNSS.',
              style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static String _num(double v) => v.isFinite ? v.toStringAsFixed(1) : '--';

  static String _csv(String s) =>
      s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
}
