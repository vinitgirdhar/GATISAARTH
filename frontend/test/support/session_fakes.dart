import 'dart:async';

import 'package:gatisaarth/core/platform/hardware/device_hardware.dart';
import 'package:gatisaarth/core/platform/hardware/sensor_api.dart';
import 'package:gatisaarth/core/platform/network/backend_telemetry_client.dart'
    show BackendSyncState;
import 'package:gatisaarth/core/platform/network/telemetry_sink.dart';
import 'package:gatisaarth/features/ai_motion/domain/speed_estimator.dart';

class FakeSensors implements HardwareSensorInterface {
  final frames = StreamController<List<double>>.broadcast();
  int starts = 0;
  int stops = 0;

  @override
  Stream<List<double>> get imuStream => frames.stream;
  @override
  void start() => starts++;
  @override
  void stop() => stops++;
}

class FakeHardware implements DeviceHardware {
  final temps = StreamController<double>.broadcast();
  int anomalyVibrations = 0;
  int outageAlarms = 0;

  @override
  void start() {}
  @override
  void stop() {}
  @override
  double get currentTemperature => 30;
  @override
  double get thermalBiasCorrection => 0.002;
  @override
  Stream<double> get temperatureStream => temps.stream;
  @override
  Future<void> vibrate({int durationMs = 200, int amplitude = 255}) async {}
  @override
  Future<void> triggerOutageAlarmVibration() async => outageAlarms++;
  @override
  Future<void> triggerRoadAnomalyVibration(bool isPothole) async =>
      anomalyVibrations++;
}

class FakeSpeed implements SpeedEstimator {
  double speed = 0;
  int frames = 0;
  int resets = 0;

  /// Last frame fed to the model, to assert what the model actually sees.
  Map<String, double> lastFrame = const {};

  @override
  Future<void> initialize() async {}
  @override
  double addImuFrame({
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required double pitch,
    required double roll,
  }) {
    frames++;
    lastFrame = {'ax': ax, 'ay': ay, 'az': az, 'pitch': pitch, 'roll': roll};
    return speed;
  }

  @override
  double get estimatedSpeed => speed;
  @override
  double get confidence => 0.9;
  @override
  int get latencyMs => 3;
  @override
  bool get hasModelInference => true;
  @override
  bool get isModelLoaded => true;
  @override
  void reset() => resets++;
}

class FakeTelemetry implements TelemetrySink {
  final sent = <Map<String, Object?>>[];

  @override
  Future<bool> send({
    required double latitude,
    required double longitude,
    required double heading,
    required double speed,
    required double confidence,
    required bool gnssAvailable,
    required String mode,
    double? altitude,
  }) async {
    sent.add({
      'lat': latitude,
      'lon': longitude,
      'speed': speed,
      'confidence': confidence,
      'gnss': gnssAvailable,
      'mode': mode,
      'altitude': altitude,
    });
    return true;
  }

  @override
  BackendSyncState get syncState => BackendSyncState.offline;
  @override
  int get recordsSent => sent.length;
  @override
  Future<void> stop() async {}
}
