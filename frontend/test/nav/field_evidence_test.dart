import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/field_evidence.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_report.dart';

class _Signer implements EvidenceSigner {
  @override
  Future<EvidenceSignature> sign(String payload) async =>
      const EvidenceSignature(
        algorithm: 'SHA256withECDSA',
        keyId: 'test-device-key',
        payloadSha256: 'abc123',
        publicKeyBase64: 'public-key',
        signatureBase64: 'signature',
      );
}

OutageReport report() => const OutageReport(
      source: 'field-drive.jsonl',
      profile: LogProfile(
        durationS: 180,
        imuHz: 50,
        gnssHz: 1,
        gnssFixes: 170,
        truthFixes: 160,
        medianTruthAccuracyM: 4.5,
        hasMagnetometer: true,
        hasBarometer: true,
        deviceModel: 'Test Phone',
        vehicle: 'car',
      ),
      config: OutageBenchmarkConfig(),
      durations: [],
      windowsTried: 3,
      skipped: {},
      coreLedFromS: 25,
      runtimeMs: 120,
    );

void main() {
  test('builds a signed, receiver-aware and reproducible field report', () async {
    const log = '''
{"t":"m","u":0,"sid":"drive-1","start":1,"dev":"Test Phone","mount":"dashboard cradle","road":"tunnel"}
{"t":"s","u":1000000,"raw":true,"rm":9,"adr":4,"vis":5,"used":3,"sv":[[7,3,41.0,true,1176450000.0],[1,8,35.0,true,1575420000.0]]}
{"t":"s","u":2000000,"raw":true,"rm":8,"adr":3,"vis":4,"used":2,"sv":[[7,3,38.0,true,1176450000.0]]}
{"t":"k","u":2100000,"l":"tunnel entry"}
''';

    final evidence = await FieldEvidenceBuilder(signer: _Signer()).build(
      report: report(),
      driveLog: log,
      simulated: false,
      generatedAt: DateTime.utc(2026, 9, 22, 12),
    );
    final json = jsonDecode(evidence.toJson()) as Map<String, dynamic>;
    final payload = json['payload'] as Map<String, dynamic>;
    final receiver = payload['receiverEvidence'] as Map<String, dynamic>;
    final attestation = json['attestation'] as Map<String, dynamic>;

    expect(payload['fieldMeasurement'], isTrue);
    expect(payload['sessionId'], 'drive-1');
    expect(payload['mount'], 'dashboard cradle');
    expect(receiver['samples'], 2);
    expect(receiver['navicObserved'], isTrue);
    expect(receiver['rawMeasurementsObserved'], isTrue);
    expect(receiver['maxVisibleSatellites'], 5);
    expect(receiver['maxRawMeasurements'], 9);
    expect(receiver['maxAdrMeasurements'], 4);
    expect((payload['benchmark'] as Map)['config'], isNotNull);
    expect(attestation['algorithm'], 'SHA256withECDSA');
    expect(attestation['signatureBase64'], 'signature');
    expect(json['signedPayloadBase64'], isNotEmpty);
  });

  test('simulated evidence is explicitly not a field measurement', () async {
    final evidence = await FieldEvidenceBuilder(signer: _Signer()).build(
      report: report(),
      driveLog: '',
      simulated: true,
      generatedAt: DateTime.utc(2026, 9, 22),
    );
    final json = jsonDecode(evidence.toJson()) as Map<String, dynamic>;
    expect((json['payload'] as Map)['fieldMeasurement'], isFalse);
  });
}
