import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_hardware.dart';

/// [DeviceHardware] backed by `MainActivity`'s method channel. Every call is a
/// no-op off Android, and every failure is logged and swallowed: a missing
/// temperature or vibration must never take the session down.
class DeviceHardwareService implements DeviceHardware {
  factory DeviceHardwareService() => _shared;
  DeviceHardwareService._();
  static final DeviceHardwareService _shared = DeviceHardwareService._();

  static const MethodChannel _channel =
      MethodChannel('com.gatisaarth.app/device_sensors');

  /// Battery temperature changes slowly; a poll every few seconds is plenty.
  static const Duration _pollEvery = Duration(seconds: 2);

  final StreamController<double> _temperatures =
      StreamController<double>.broadcast();
  Timer? _poll;
  double? _temperature;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  @override
  double? get currentTemperature => _temperature;

  @override
  Stream<double> get temperatureStream => _temperatures.stream;

  @override
  void start() {
    if (_poll != null) return;
    unawaited(_readTemperature());
    _poll = Timer.periodic(_pollEvery, (_) => _readTemperature());
  }

  @override
  void stop() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _readTemperature() async {
    if (!_android) return;
    try {
      final value = await _channel.invokeMethod<num>('getDeviceTemperature');
      if (value == null) return;
      _temperature = value.toDouble();
      if (!_temperatures.isClosed) _temperatures.add(_temperature!);
    } catch (e) {
      debugPrint('[DeviceHardwareService] temperature unavailable: $e');
    }
  }

  @override
  Future<void> vibrate({int durationMs = 200, int amplitude = 255}) =>
      _call('vibrateDevice', {'durationMs': durationMs, 'amplitude': amplitude});

  @override
  Future<void> setKeepScreenOn(bool on) => _call('setKeepScreenOn', {'on': on});

  @override
  Future<DeviceInfo?> deviceInfo() async {
    if (!_android) return null;
    try {
      final info =
          await _channel.invokeMapMethod<String, String>('getDeviceInfo');
      final model = info?['model'], os = info?['os'];
      return model == null || os == null
          ? null
          : DeviceInfo(model: model, os: os);
    } catch (e) {
      debugPrint('[DeviceHardwareService] device info unavailable: $e');
      return null;
    }
  }

  Future<void> _call(String method, Map<String, Object> args) async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('[DeviceHardwareService] $method failed: $e');
    }
  }

  void dispose() {
    stop();
    _temperatures.close();
  }
}
