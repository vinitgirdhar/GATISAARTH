import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/field_evidence.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_report.dart';
import 'package:gatisaarth/features/benchmark/data/benchmark_report_exporter.dart';

class _FailingSigner implements EvidenceSigner {
  @override
  Future<EvidenceSignature> sign(String payload) async {
    throw UnimplementedError('no Keystore in this test environment');
  }
}

class _WorkingSigner implements EvidenceSigner {
  @override
  Future<EvidenceSignature> sign(String payload) async =>
      const EvidenceSignature(
        algorithm: 'SHA256withECDSA',
        keyId: 'test-key',
        payloadSha256: 'ignored',
        publicKeyBase64: 'pk',
        signatureBase64: 'sig',
      );
}

OutageReport _report({double engineErrorM = 25}) => OutageReport(
      source: 'Reference city drive (simulated)',
      profile: const LogProfile(
        durationS: 320,
        imuHz: 50,
        gnssHz: 1,
        gnssFixes: 316,
        truthFixes: 316,
        medianTruthAccuracyM: 5,
        hasMagnetometer: false,
        hasBarometer: false,
        deviceModel: 'Pixel 9',
      ),
      config: const OutageBenchmarkConfig(),
      durations: [
        DurationResult.of(30, [
          OutageSample(
            startUs: 0,
            holdErrorM: 190,
            engineErrorM: engineErrorM,
            engineSigmaM: 9,
            distanceM: 350,
            alongTrackErrorM: 20,
            crossTrackErrorM: 5,
            maxSigmaM: 11,
            recoveryJumpM: 2.5,
          ),
        ]),
      ],
      windowsTried: 1,
      skipped: const {},
      coreLedFromS: 40,
      runtimeMs: 500,
    );

void main() {
  group('BenchmarkReportExporter JSON', () {
    test('the same report hashes the same way every time', () async {
      final exporter = BenchmarkReportExporter(signer: _FailingSigner());
      final a = await exporter.build(
        report: _report(),
        driveLog: '',
        simulated: true,
        generatedAt: DateTime.utc(2026, 9, 25),
      );
      final b = await exporter.build(
        report: _report(),
        driveLog: '',
        simulated: true,
        generatedAt: DateTime.utc(2026, 9, 25),
      );
      expect(a.sha256Hex, b.sha256Hex);
      expect(a.sha256Hex.length, 64);
    });

    test('changing a scored number changes the hash', () async {
      final exporter = BenchmarkReportExporter(signer: _FailingSigner());
      final a = await exporter.build(
        report: _report(engineErrorM: 25),
        driveLog: '',
        simulated: true,
        generatedAt: DateTime.utc(2026, 9, 25),
      );
      final b = await exporter.build(
        report: _report(engineErrorM: 26),
        driveLog: '',
        simulated: true,
        generatedAt: DateTime.utc(2026, 9, 25),
      );
      expect(a.sha256Hex, isNot(b.sha256Hex));
    });

    test('signs when a Keystore signer is available', () async {
      final exporter = BenchmarkReportExporter(signer: _WorkingSigner());
      final exported = await exporter.build(
        report: _report(),
        driveLog: '',
        simulated: true,
      );
      expect(exported.signature, isNotNull);
      expect(exported.signature!.algorithm, 'SHA256withECDSA');
      final json = jsonDecode(exported.toJsonText()) as Map<String, dynamic>;
      expect(json['attestation'], isNotNull);
      expect(json['sha256'], exported.sha256Hex);
    });

    test('falls back to unsigned, still hashed, when the signer fails',
        () async {
      final exporter = BenchmarkReportExporter(signer: _FailingSigner());
      final exported = await exporter.build(
        report: _report(),
        driveLog: '',
        simulated: true,
      );
      expect(exported.signature, isNull);
      final json = jsonDecode(exported.toJsonText()) as Map<String, dynamic>;
      expect(json.containsKey('attestation'), isFalse);
      expect(json['sha256'], exported.sha256Hex);
    });
  });

  group('BenchmarkReportExporter CSV', () {
    test('carries a header block and one row per duration', () {
      const exporter = BenchmarkReportExporter();
      final csv = exporter.toCsv(_report(), simulated: true);
      expect(csv, contains('GatiSaarth Navigation Benchmark'));
      expect(csv, contains('Device,Pixel 9'));
      expect(csv, contains('SIMULATED reference drive'));
      expect(csv, contains('duration_s,n,hold_median_m'));
      final rows = const LineSplitter().convert(csv);
      final dataRow = rows.firstWhere((r) => r.startsWith('30,'));
      expect(dataRow, contains('PASS'));
    });

    test('a failing drive is marked FAIL in its row', () {
      const exporter = BenchmarkReportExporter();
      final csv = exporter.toCsv(_report(engineErrorM: 200), simulated: true);
      final rows = const LineSplitter().convert(csv);
      final dataRow = rows.firstWhere((r) => r.startsWith('30,'));
      expect(dataRow, contains('FAIL'));
    });
  });

  group('BenchmarkReportExporter PDF', () {
    test('produces bytes that start with the PDF magic header', () async {
      final exporter = BenchmarkReportExporter(signer: _FailingSigner());
      final report = _report();
      final exported = await exporter.build(
        report: report,
        driveLog: '',
        simulated: true,
      );
      final bytes = await exporter.toPdfBytes(
        report,
        simulated: true,
        exported: exported,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
