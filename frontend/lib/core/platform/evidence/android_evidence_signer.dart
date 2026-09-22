import 'package:flutter/services.dart';

import '../../nav/benchmark/field_evidence.dart';

class AndroidEvidenceSigner implements EvidenceSigner {
  const AndroidEvidenceSigner();

  static const MethodChannel _channel =
      MethodChannel('com.gatisaarth.app/device_sensors');

  @override
  Future<EvidenceSignature> sign(String payload) async {
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'signEvidence',
      {'payload': payload},
    );
    String required(String key) {
      final value = response?[key];
      if (value is! String || value.isEmpty) {
        throw StateError('Android evidence signer omitted $key');
      }
      return value;
    }

    return EvidenceSignature(
      algorithm: required('algorithm'),
      keyId: required('keyId'),
      payloadSha256: required('payloadSha256'),
      publicKeyBase64: required('publicKeyBase64'),
      signatureBase64: required('signatureBase64'),
    );
  }
}
