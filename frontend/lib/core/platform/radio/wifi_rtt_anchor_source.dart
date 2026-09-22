import 'dart:async';

import 'package:flutter/services.dart';

import '../../nav/anchors/radio_anchor.dart';

abstract interface class WifiRttAnchorSource {
  Future<RadioAnchorObservation?> range(String radioId);
}

/// User-triggered Android Wi-Fi RTT ranging. No AP connection or scan result
/// leaves the phone; unsupported hardware and unavailable APs return null.
class PlatformWifiRttAnchorSource implements WifiRttAnchorSource {
  const PlatformWifiRttAnchorSource();

  static const _channel = MethodChannel('com.gatisaarth.app/wifi_rtt');

  @override
  Future<RadioAnchorObservation?> range(String radioId) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'range',
        {'radioId': radioId},
      ).timeout(const Duration(seconds: 8));
      if (result == null) return null;
      final measuredId = result['radioId'];
      final range = result['rangeM'];
      final sigma = result['rangeSigmaM'];
      final ageMs = result['ageMs'];
      if (measuredId != radioId ||
          range is! num ||
          sigma is! num ||
          ageMs is! num ||
          !range.isFinite ||
          !sigma.isFinite ||
          ageMs < 0) {
        return null;
      }
      return RadioAnchorObservation(
        radioId: radioId,
        rangeM: range.toDouble(),
        rangeSigmaM: sigma.toDouble(),
        age: Duration(milliseconds: ageMs.toInt()),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}

class NoopWifiRttAnchorSource implements WifiRttAnchorSource {
  const NoopWifiRttAnchorSource();

  @override
  Future<RadioAnchorObservation?> range(String radioId) async => null;
}
