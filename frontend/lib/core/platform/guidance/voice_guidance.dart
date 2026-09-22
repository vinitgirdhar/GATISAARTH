import 'package:flutter/services.dart';

abstract interface class VoiceGuidance {
  Future<void> speak(String message);
  Future<void> stop();
}

class NoopVoiceGuidance implements VoiceGuidance {
  const NoopVoiceGuidance();
  @override
  Future<void> speak(String message) async {}
  @override
  Future<void> stop() async {}
}

class PlatformVoiceGuidance implements VoiceGuidance {
  const PlatformVoiceGuidance();

  static const MethodChannel _channel =
      MethodChannel('com.gatisaarth.app/device_sensors');

  @override
  Future<void> speak(String message) async {
    if (message.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<void>('speakGuidance', {'message': message});
    } on MissingPluginException {
      // Desktop, web and host-less tests have no Android speech service.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopGuidance');
    } on MissingPluginException {
      // See [speak].
    }
  }
}
