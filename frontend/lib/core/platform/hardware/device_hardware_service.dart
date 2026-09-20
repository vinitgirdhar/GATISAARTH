import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'device_hardware.dart';

/// Real Hardware Device Service
/// Communicates with Android native layer to read:
/// 1. Real physical device temperature (from BatteryManager / hardware thermal sensors)
/// 2. Real physical device vibrator / haptic motor
class DeviceHardwareService implements DeviceHardware {
  static const MethodChannel _channel =
      MethodChannel('com.gatisaarth.app/device_sensors');

  static final DeviceHardwareService _instance =
      DeviceHardwareService._internal();
  factory DeviceHardwareService() => _instance;
  DeviceHardwareService._internal();

  double _currentTemperature = 35.0;
  bool _isRunning = false;
  Timer? _tempPollTimer;
  final StreamController<double> _tempController =
      StreamController<double>.broadcast();

  @override
  double get currentTemperature => _currentTemperature;
  @override
  Stream<double> get temperatureStream => _tempController.stream;

  /// Calculates physical MEMS gyroscope thermal bias correction (deg/s)
  /// using semiconductor temperature polynomial:
  /// Bias(T) = Base_Bias + Alpha * (T - 25°C) + Beta * (T - 25°C)^2
  @override
  double get thermalBiasCorrection {
    final deltaT = _currentTemperature - 25.0;
    return 0.0015 + (0.000085 * deltaT) + (0.0000012 * deltaT * deltaT);
  }

  @override
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _pollTemperature();
    _tempPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollTemperature();
    });
  }

  Future<void> _pollTemperature() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final dynamic result =
            await _channel.invokeMethod('getDeviceTemperature');
        if (result != null && result is num) {
          _currentTemperature = result.toDouble();
          _tempController.add(_currentTemperature);
          return;
        }
      }
    } catch (e) {
      debugPrint('[DeviceHardwareService] Temp read failed, using fallback: $e');
    }
    // Fallback baseline temperature for desktop/web simulator
    _currentTemperature = 35.2;
    _tempController.add(_currentTemperature);
  }

  /// One vibration on the phone's motor. A failure is swallowed: a missing
  /// vibration must never turn into a different, stronger one.
  @override
  Future<void> vibrate({int durationMs = 200, int amplitude = 255}) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('vibrateDevice', {
          'durationMs': durationMs,
          'amplitude': amplitude,
        });
      }
    } catch (e) {
      debugPrint('[DeviceHardwareService] vibrate failed: $e');
    }
  }

  @override
  Future<void> setKeepScreenOn(bool on) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('setKeepScreenOn', {'on': on});
      }
    } catch (e) {
      debugPrint('[DeviceHardwareService] keep-screen-on failed: $e');
    }
  }

  @override
  Future<DeviceInfo?> deviceInfo() async {
    try {
      if (defaultTargetPlatform != TargetPlatform.android) return null;
      final info = await _channel.invokeMapMethod<String, String>('getDeviceInfo');
      final model = info?['model'];
      final os = info?['os'];
      return model == null || os == null
          ? null
          : DeviceInfo(model: model, os: os);
    } catch (e) {
      debugPrint('[DeviceHardwareService] device info failed: $e');
      return null;
    }
  }

  @override
  void stop() {
    _isRunning = false;
    _tempPollTimer?.cancel();
    _tempPollTimer = null;
  }

  void dispose() {
    stop();
    _tempController.close();
  }
}
