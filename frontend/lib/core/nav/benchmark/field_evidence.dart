import 'dart:convert';
import 'dart:math' as math;

import 'outage_report.dart';

abstract interface class EvidenceSigner {
  Future<EvidenceSignature> sign(String payload);
}

class EvidenceSignature {
  const EvidenceSignature({
    required this.algorithm,
    required this.keyId,
    required this.payloadSha256,
    required this.publicKeyBase64,
    required this.signatureBase64,
  });

  final String algorithm;
  final String keyId;
  final String payloadSha256;
  final String publicKeyBase64;
  final String signatureBase64;

  Map<String, Object> toJson() => {
        'algorithm': algorithm,
        'keyId': keyId,
        'payloadSha256': payloadSha256,
        'publicKeyBase64': publicKeyBase64,
        'signatureBase64': signatureBase64,
      };
}

class SignedFieldEvidence {
  const SignedFieldEvidence({
    required this.payload,
    required this.payloadText,
    required this.signature,
  });

  final Map<String, Object?> payload;
  final String payloadText;
  final EvidenceSignature signature;

  String toJson() => const JsonEncoder.withIndent('  ').convert({
        'schema': 'gatisaarth.field-evidence.v1',
        'payload': payload,
        // Verifiers sign these exact UTF-8 bytes; no JSON canonicalisation is
        // required and the readable payload remains alongside it.
        'signedPayloadBase64': base64Encode(utf8.encode(payloadText)),
        'attestation': signature.toJson(),
      });
}

class FieldEvidenceBuilder {
  const FieldEvidenceBuilder({required this.signer});

  final EvidenceSigner signer;

  Future<SignedFieldEvidence> build({
    required OutageReport report,
    required String driveLog,
    required bool simulated,
    DateTime? generatedAt,
  }) async {
    final receiver = _ReceiverEvidence.fromLog(driveLog);
    final payload = <String, Object?>{
      'generatedAt': (generatedAt ?? DateTime.now().toUtc()).toIso8601String(),
      'fieldMeasurement': !simulated,
      'source': report.source,
      if (receiver.sessionId != null) 'sessionId': receiver.sessionId,
      if (receiver.device != null) 'device': receiver.device,
      if (receiver.mount != null) 'mount': receiver.mount,
      if (receiver.roadType != null) 'roadType': receiver.roadType,
      'receiverEvidence': receiver.toJson(),
      'benchmark': _benchmarkJson(report),
    };
    final payloadText = jsonEncode(payload);
    final signature = await signer.sign(payloadText);
    return SignedFieldEvidence(
      payload: payload,
      payloadText: payloadText,
      signature: signature,
    );
  }

  static Map<String, Object?> _benchmarkJson(OutageReport report) => {
        'engine': 'GatiSaarth ES-EKF replay',
        'vehicleProfile': report.vehicleClass.name,
        'durationSeconds': report.profile.durationS,
        'imuHz': report.profile.imuHz,
        'gnssHz': report.profile.gnssHz,
        'truthFixes': report.profile.truthFixes,
        'medianTruthAccuracyM': _finite(report.profile.medianTruthAccuracyM),
        'windowsTried': report.windowsTried,
        'coreLedFromSeconds': _finite(report.coreLedFromS),
        'config': {
          'durationsSeconds': report.config.durationsS,
          'strideSeconds': report.config.strideS,
          'maxStarts': report.config.maxStarts,
          'settleAfterLeadSeconds': report.config.settleAfterLeadS,
          'maxTruthAccuracyM': report.config.maxTruthAccuracyM,
          'maxFixAgeSeconds': report.config.maxFixAgeS,
          'minDistanceM': report.config.minDistanceM,
        },
        'results': [
          for (final result in report.durations)
            {
              'outageSeconds': result.durationS,
              'samples': result.n,
              'holdMedianM': _finite(result.hold.medianM),
              'holdP95M': _finite(result.hold.p95M),
              'coreMedianM': _finite(result.engine.medianM),
              'coreP95M': _finite(result.engine.p95M),
              'coreMedianDriftPercent': _finite(result.engine.medianDriftPct),
              'coreCloser': result.engineWins,
              'threeSigmaCovered': result.engineCovered,
            },
        ],
        'skipped': {
          for (final entry in report.skipped.entries)
            entry.key.name: entry.value,
        },
      };

  static num? _finite(num? value) =>
      value == null || !value.isFinite ? null : value;
}

class _ReceiverEvidence {
  _ReceiverEvidence({
    this.sessionId,
    this.device,
    this.mount,
    this.roadType,
    required this.samples,
    required this.rawMeasurementsObserved,
    required this.navicObserved,
    required this.maxVisibleSatellites,
    required this.maxRawMeasurements,
    required this.maxAdrMeasurements,
    required this.meanCn0DbHz,
    required this.markers,
  });

  factory _ReceiverEvidence.fromLog(String log) {
    String? sessionId;
    String? device;
    String? mount;
    String? roadType;
    var samples = 0;
    var raw = false;
    var navic = false;
    var maxVisible = 0;
    var maxRaw = 0;
    var maxAdr = 0;
    final cn0 = <double>[];
    final markers = <String>[];
    for (final line in const LineSplitter().convert(log)) {
      try {
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic>) continue;
        switch (value['t']) {
          case 'm':
            sessionId = value['sid'] as String?;
            device = value['dev'] as String?;
            mount = value['mount'] as String?;
            roadType = value['road'] as String?;
          case 's':
            samples++;
            raw = raw || value['raw'] == true;
            maxVisible = math.max(
              maxVisible,
              (value['vis'] as num?)?.toInt() ?? 0,
            );
            maxRaw = math.max(maxRaw, (value['rm'] as num?)?.toInt() ?? 0);
            maxAdr = math.max(maxAdr, (value['adr'] as num?)?.toInt() ?? 0);
            final satellites = value['sv'];
            if (satellites is List) {
              for (final satellite in satellites.whereType<List>()) {
                if (satellite.length < 3) continue;
                navic = navic || (satellite[0] as num?)?.toInt() == 7;
                final strength = (satellite[2] as num?)?.toDouble();
                if (strength != null && strength.isFinite) cn0.add(strength);
              }
            }
          case 'k':
            final label = value['l'];
            if (label is String) markers.add(label);
        }
      } catch (_) {
        // A field log may end mid-line after power loss. Preserve all valid
        // evidence before it rather than rejecting the complete session.
      }
    }
    return _ReceiverEvidence(
      sessionId: sessionId,
      device: device,
      mount: mount,
      roadType: roadType,
      samples: samples,
      rawMeasurementsObserved: raw,
      navicObserved: navic,
      maxVisibleSatellites: maxVisible,
      maxRawMeasurements: maxRaw,
      maxAdrMeasurements: maxAdr,
      meanCn0DbHz:
          cn0.isEmpty ? null : cn0.reduce((a, b) => a + b) / cn0.length,
      markers: List.unmodifiable(markers),
    );
  }

  final String? sessionId;
  final String? device;
  final String? mount;
  final String? roadType;
  final int samples;
  final bool rawMeasurementsObserved;
  final bool navicObserved;
  final int maxVisibleSatellites;
  final int maxRawMeasurements;
  final int maxAdrMeasurements;
  final double? meanCn0DbHz;
  final List<String> markers;

  Map<String, Object?> toJson() => {
        'samples': samples,
        'rawMeasurementsObserved': rawMeasurementsObserved,
        'navicObserved': navicObserved,
        'maxVisibleSatellites': maxVisibleSatellites,
        'maxRawMeasurements': maxRawMeasurements,
        'maxAdrMeasurements': maxAdrMeasurements,
        'meanCn0DbHz': meanCn0DbHz,
        'markers': markers,
      };
}
