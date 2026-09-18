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

  /// Triggers real physical vibration on the phone
  @override
  Future<void> vibrate({int durationMs = 200, int amplitude = 255}) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('vibrateDevice', {
          'durationMs': durationMs,
          'amplitude': amplitude,
        });
      } else {
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }

  /// Triggers a double-pulse vibration pattern for emergency / severe events
  @override
  Future<void> triggerOutageAlarmVibration() async {
    await vibrate(durationMs: 250, amplitude: 255);
    await Future.delayed(const Duration(milliseconds: 150));
    await vibrate(durationMs: 350, amplitude: 255);
  }

  /// Triggers a brief haptic bump for road anomalies (speed breakers, potholes)
  @override
  Future<void> triggerRoadAnomalyVibration(bool isPothole) async {
    if (isPothole) {
      await vibrate(durationMs: 300, amplitude: 255);
    } else {
      await vibrate(durationMs: 120, amplitude: 180);
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
