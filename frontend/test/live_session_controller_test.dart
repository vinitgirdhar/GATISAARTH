import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/navigation_engine/domain/entities/navigation_state.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';

import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

const _homeFix = GnssFix(
  latitude: 19.45,
  longitude: 72.81,
  altitude: 12,
  accuracy: 5,
  speed: 10,
);

/// Frame layout: [ax, ay, az, gx, gy, gz, t, mx, my, mz, pressure, altitude].
List<double> _frame(
  double t, {
  double ax = 0,
  double az = 9.81,
  double mx = 0,
  double my = 30,
}) =>
    [ax, 0, az, 0, 0, 0, t, mx, my, 0, double.nan, double.nan];

void main() {
  late FakeSensors sensors;
  late FakeHardware hardware;
  late FakeSpeed speedFake;
  late FakeTelemetry telemetry;
  late FakeLocationGateway gateway;
  late VehicleAlignmentEngine alignment;
  late DateTime now;
  late LiveSessionController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sensors = FakeSensors();
    hardware = FakeHardware();
    speedFake = FakeSpeed();
    telemetry = FakeTelemetry();
    gateway = FakeLocationGateway();
    alignment = VehicleAlignmentEngine();
    now = DateTime(2026, 9, 18, 12);
    controller = LiveSessionController(
      sensors: sensors,
      alignment: alignment,
      hardware: hardware,
      speedEstimator: speedFake,
      telemetry: telemetry,
      location: LiveLocationService(
        gateway: gateway,
        clock: () => now,
        errorRetryDelay: Duration.zero,
      ),
      clock: () => now,
      autoTick: false,
    );
  });

  tearDown(() => controller.dispose());

  Future<void> goLive([GnssFix fix = _homeFix]) async {
    await controller.start();
    gateway.fixController.add(fix);
    await settle();
    controller.tick();
  }

  Future<void> feed(int count, {double from = 100, double dt = 0.02}) async {
    for (var i = 0; i < count; i++) {
      sensors.frames.add(_frame(from + i * dt));
    }
    await settle();
  }

  test('counts IMU frames and reports sensor liveness from real timestamps',
      () async {
    await controller.start();
    expect(controller.isSensorLive, isFalse);
    sensors.frames.add(_frame(1));
    await settle();
    expect(controller.sampleCount, 1);
    expect(controller.isSensorLive, isTrue);
    now = now.add(const Duration(seconds: 1));
    expect(controller.isSensorLive, isFalse);
  });

  test('starts with no fabricated anomalies', () async {
    await controller.start();
    expect(controller.anomalies, isEmpty);
  });

  test('a live fix drives position, speed and an honest uncertainty margin',
      () async {
    await goLive();
    expect(controller.fusionMode, FusionMode.gnssLocked);
    expect(controller.hasLiveGnss, isTrue);
    expect(controller.latitude, closeTo(19.45, 1e-9));
    expect(controller.longitude, closeTo(72.81, 1e-9));
    expect(controller.speed, 10);
    final u = controller.uncertainty!;
    expect(u.marginMeters, 5);
    expect(u.confidence, closeTo(0.967, 0.001));
  });

  test('without any fix there is no confidence to claim', () async {
    await controller.start();
    expect(controller.uncertainty, isNull);
    expect(controller.fusionMode, FusionMode.deadReckoning);
    expect(controller.hasLiveGnss, isFalse);
  });

  test('the neural model runs while GNSS is live but never overrides its speed',
      () async {
    await goLive();
    speedFake.speed = 3; // the model disagrees with the fix (10 m/s)
    await feed(30);
    expect(speedFake.frames, greaterThan(0)); // the AI panel has real output
    expect(controller.speed, 10); // the live fix still owns the speed
  });

  test('cached position is shown before the first fix', () async {
    SharedPreferences.setMockInitialValues({
      'last_known_lat': 12.5,
      'last_known_lon': 77.5,
    });
    await controller.start();
    expect(controller.latitude, 12.5);
    expect(controller.longitude, 77.5);
    expect(controller.hasLiveGnss, isFalse);
  });

  test(
      'losing GNSS starts an outage that dead-reckons north and grows the '
      'margin', () async {
    await goLive();
    now = now.add(const Duration(seconds: 7));
    controller.tick();
    expect(controller.gnssStatus, LocationStatus.stale);
    expect(controller.inOutage, isTrue);
    expect(controller.fusionMode, FusionMode.deadReckoning);

    // The 7 s nobody noticed are extrapolated at the last GNSS speed (10 m/s).
    expect(controller.outageDistanceMeters, closeTo(70, 0.01));

    speedFake.speed = 10;
    await feed(60); // heading 0 (north), 60 frames * 0.02 s * 10 m/s
    controller.tick();

    expect(controller.outageDistanceMeters, closeTo(82, 0.01));
    expect(controller.latitude, closeTo(19.45 + 82 / 111000, 1e-7));
    expect(controller.longitude, closeTo(72.81, 1e-7));

    final early = controller.uncertainty!.marginMeters;
    now = now.add(const Duration(seconds: 30));
    expect(controller.uncertainty!.marginMeters, greaterThan(early + 4));
  });

  test('an outage is noticed late, but the unobserved seconds still count',
      () async {
    await goLive();
    now = now.add(const Duration(seconds: 7));
    controller.tick();
    expect(controller.outageElapsed, const Duration(seconds: 7));
    // 5 m accuracy + 5 % of 70 m + 0.15 m/s * 7 s.
    expect(controller.uncertainty!.marginMeters, closeTo(9.55, 0.01));
  });

  test(
      'a long gap (e.g. app in background) widens the margin without moving '
      'the marker', () async {
    await goLive();
    now = now.add(const Duration(minutes: 2));
    controller.tick();
    expect(controller.latitude, closeTo(19.45, 1e-9));
    expect(controller.outageDistanceMeters, closeTo(1200, 0.01));
    // 5 + 0.05 * 1200 + 0.15 * 120 = 83 m.
    expect(controller.uncertainty!.marginMeters, closeTo(83, 0.01));
    expect(controller.uncertainty!.confidence, lessThan(0.5));
  });

  test('location switched off mid-drive is an outage, not a silent freeze',
      () async {
    await goLive();
    gateway.serviceEnabled = false;
    gateway.serviceChanges.add(false);
    await settle();
    controller.tick();
    expect(controller.gnssStatus, LocationStatus.serviceOff);
    expect(controller.inOutage, isTrue);
    expect(controller.fusionMode, FusionMode.deadReckoning);
    expect(controller.uncertainty, isNotNull);
  });

  test('returning from the background blends in instead of jumping', () async {
    await goLive();
    await controller.pause();
    now = now.add(const Duration(seconds: 20));
    await controller.resume();
    gateway.fixController.add(_homeFix);
    await settle();
    controller.tick();
    expect(controller.gnssStatus, LocationStatus.live);
    expect(controller.fusionMode, FusionMode.reacquiring);
  });

  test('the model is fed at its 10 Hz training rate, with gravity restored',
      () async {
    await goLive();
    now = now.add(const Duration(seconds: 7));
    controller.tick();
    await feed(100); // 2 s of 50 Hz sensor frames
    expect(speedFake.frames, 20);
    expect(speedFake.lastFrame['az'], closeTo(9.81, 0.05));
    expect(speedFake.lastFrame['pitch'], 0);
    expect(speedFake.lastFrame['roll'], 0);
  });

  test('integration follows sensor timestamps, including stalls', () async {
    await goLive();
    now = now.add(const Duration(seconds: 7));
    controller.tick();
    speedFake.speed = 10;
    final before = controller.outageDistanceMeters;
    sensors.frames.add(_frame(100));
    sensors.frames.add(_frame(100.5)); // a 0.5 s stall, not clipped to 0.1 s
    await settle();
    expect(
        controller.outageDistanceMeters - before, closeTo(0.02 * 10 + 5, 0.01));
  });

  test('speed keeps the last GNSS value until the model has a full window',
      () async {
    await goLive();
    now = now.add(const Duration(seconds: 7));
    controller.tick();
    speedFake.speed = 0;
    await feed(5);
    expect(controller.speed, 10, reason: 'model not warm yet');
  });

  test('zero-velocity update stops integration after sustained stillness',
      () async {
    await goLive();
    now = now.add(const Duration(seconds: 7));
    controller.tick();
    speedFake.speed = 0;
    await feed(250); // 5 s: warm-up (1 s) + 3 s still needed at speed
    controller.tick();
    expect(controller.speed, 0);
    final before = controller.outageDistanceMeters;
    await feed(20, from: 200);
    expect(controller.outageDistanceMeters, before);
  });

  test('a brief smooth patch does not zero a fast speed (cruise != stop)',
      () async {
    await goLive();
    now = now.add(const Duration(seconds: 7));
    controller.tick();
    speedFake.speed = 10;
    await feed(60); // model warm, reporting 10 m/s
    speedFake.speed = 0;
    await feed(100, from: 200); // 2 s "still" < 3 s needed at 10 m/s
    expect(controller.speed, 10);
    speedFake.speed = 10; // motion resumes: the stillness clock restarts
    await feed(25, from: 300);
    speedFake.speed = 0;
    await feed(100, from: 400);
    expect(controller.speed, 10);
  });

  test('a slow vehicle is zeroed after one second of stillness', () async {
    await goLive(const GnssFix(
      latitude: 19.45,
      longitude: 72.81,
      altitude: 12,
      accuracy: 5,
      speed: 1,
    ));
    now = now.add(const Duration(seconds: 7));
    controller.tick();
    speedFake.speed = 0;
    await feed(100); // 1 s warm-up + 1 s still
    expect(controller.speed, 0);
  });

  test('reacquisition blends in smoothly instead of jumping', () async {
    await goLive();
    now = now.add(const Duration(seconds: 7));
    controller.tick();
    speedFake.speed = 10;
    await feed(60);
    controller.tick();
    final drLat = controller.latitude;
    expect(drLat, greaterThan(19.45));

    gateway.fixController.add(_homeFix);
    await settle();
    controller.tick();
    expect(controller.gnssStatus, LocationStatus.live);
    expect(controller.fusionMode, FusionMode.reacquiring);
    expect(controller.latitude, closeTo(drLat, 1e-9),
        reason: 'no instant snap on the frame the fix returns');

    now = now.add(const Duration(milliseconds: 500));
    controller.tick();
    expect(controller.latitude, lessThan(drLat));
    expect(controller.latitude, greaterThan(19.45));

    for (var i = 0; i < 60; i++) {
      now = now.add(const Duration(milliseconds: 100));
      if (i % 10 == 0) {
        gateway.fixController.add(_homeFix); // GNSS delivers 1 fix / second
        await settle();
      }
      controller.tick();
    }
    expect(controller.latitude, closeTo(19.45, 1e-7));
    expect(controller.fusionMode, FusionMode.gnssLocked);
    expect(controller.inOutage, isFalse);
    expect(controller.outageDistanceMeters, 0);
  });

  test('a large jump (new city) snaps instead of gliding for minutes',
      () async {
    await goLive();
    gateway.fixController.add(const GnssFix(
      latitude: 28.6,
      longitude: 77.2,
      altitude: 200,
      accuracy: 8,
      speed: 0,
    ));
    await settle();
    controller.tick();
    expect(controller.latitude, closeTo(28.6, 1e-9));
  });

  test(
      'tunnel simulation ignores real fixes for position and reacquires '
      'on reset', () async {
    await goLive();
    controller.startTunnelTest();
    expect(hardware.outageAlarms, 1);
    expect(controller.isSimulatingTunnel, isTrue);
    expect(controller.fusionMode, FusionMode.deadReckoning);
    expect(controller.hasLiveGnss, isFalse);

    gateway.fixController.add(const GnssFix(
      latitude: 20,
      longitude: 73,
      altitude: 1,
      accuracy: 5,
      speed: 3,
    ));
    await settle();
    controller.tick();
    expect(controller.latitude, closeTo(19.45, 1e-9));

    controller.resetSimulation();
    expect(controller.isSimulatingTunnel, isFalse);
    expect(controller.fusionMode, FusionMode.reacquiring);
  });

  test('urban canyon simulation degrades the mode and confidence', () async {
    await goLive();
    final clean = controller.uncertainty!;
    controller.startUrbanCanyon();
    expect(controller.fusionMode, FusionMode.gnssDegraded);
    expect(controller.uncertainty!.marginMeters, closeTo(15, 1e-9));
    expect(controller.uncertainty!.confidence, lessThan(clean.confidence));
  });

  test('telemetry reports the real mode, fix availability and confidence',
      () async {
    await goLive();
    await controller.sendTelemetryNow();
    final frame = telemetry.sent.single;
    expect(frame['mode'], 'GNSS_LOCKED');
    expect(frame['gnss'], isTrue);
    expect(frame['confidence'] as double, closeTo(0.967, 0.001));
    expect(frame['altitude'], 12);
  });

  test('telemetry never reports the placeholder map centre as a position',
      () async {
    await controller.start();
    await controller.sendTelemetryNow();
    expect(telemetry.sent, isEmpty);
  });

  test('a cached position is reported, but without GNSS or altitude claims',
      () async {
    SharedPreferences.setMockInitialValues({
      'last_known_lat': 12.5,
      'last_known_lon': 77.5,
    });
    await controller.start();
    await controller.sendTelemetryNow();
    final frame = telemetry.sent.single;
    expect(frame['lat'], 12.5);
    expect(frame['gnss'], isFalse);
    expect(frame['confidence'], 0);
    expect(frame['altitude'], isNull);
  });

  test('negative altitudes (below sea level) are reported, zero is not',
      () async {
    await goLive(const GnssFix(
      latitude: 19.45,
      longitude: 72.81,
      altitude: -4,
      accuracy: 5,
      speed: 0,
    ));
    await controller.sendTelemetryNow();
    expect(telemetry.sent.single['altitude'], -4);
  });

  test('heading follows the magnetometer', () async {
    await controller.start();
    for (var i = 0; i < 30; i++) {
      sensors.frames.add(_frame(1 + i * 0.02, mx: -30, my: 0));
    }
    await settle();
    expect(controller.heading, closeTo(90, 1));
  });

  test('real barometer availability is reflected, never assumed', () async {
    await controller.start();
    sensors.frames.add(_frame(1));
    await settle();
    expect(controller.sensorHealth.barometer, isFalse);
    expect(controller.pressureHpa.isNaN, isTrue);
    sensors.frames.add([0, 0, 9.81, 0, 0, 0, 1.02, 0, 30, 0, 1009.5, 30.0]);
    await settle();
    expect(controller.sensorHealth.barometer, isTrue);
    expect(controller.pressureHpa, 1009.5);
  });

  test('a big bump is logged once and triggers haptics once', () async {
    await controller.start();
    sensors.frames.add(_frame(1, az: 25));
    sensors.frames.add(_frame(1.02, az: 25));
    await settle();
    expect(controller.anomalies, hasLength(1));
    expect(controller.anomalies.single.type, 'pothole');
    expect(hardware.anomalyVibrations, 1);
  });

  test('pause releases sensors and GPS; resume restores them', () async {
    await goLive();
    expect(sensors.starts, 1);
    await controller.pause();
    expect(sensors.stops, greaterThanOrEqualTo(1));
    expect(gateway.hasFixListener, isFalse);

    sensors.frames.add(_frame(9));
    await settle();
    expect(controller.sampleCount, 0, reason: 'frames ignored while paused');

    await controller.resume();
    expect(sensors.starts, 2);
    expect(gateway.hasFixListener, isTrue);
  });

  test('vehicle profile reaches the alignment engine', () async {
    await controller.start();
    controller.setVehicleProfile(VehicleProfile.twoWheeler);
    expect(controller.vehicleProfile, VehicleProfile.twoWheeler);
    expect(alignment.vehicleProfile, VehicleProfile.twoWheeler);
  });

  test('listeners are notified by tick, not by every sensor frame', () async {
    await controller.start();
    var notifications = 0;
    controller.addListener(() => notifications++);
    for (var i = 0; i < 50; i++) {
      sensors.frames.add(_frame(1 + i * 0.02));
    }
    await settle();
    expect(notifications, 0, reason: '50 sensor frames must not rebuild UI');
    controller.tick();
    expect(notifications, 1);
  });

  test('position easing never overshoots the target', () async {
    await goLive();
    gateway.fixController.add(const GnssFix(
      latitude: 19.4504,
      longitude: 72.81,
      altitude: 12,
      accuracy: 5,
      speed: 0,
    ));
    await settle();
    var previous = controller.latitude;
    for (var i = 0; i < 60; i++) {
      now = now.add(const Duration(milliseconds: 100));
      controller.tick();
      expect(controller.latitude, greaterThanOrEqualTo(previous));
      expect(controller.latitude, lessThanOrEqualTo(19.4504 + 1e-12));
      previous = controller.latitude;
    }
    expect(controller.latitude, closeTo(19.4504, 1e-6));
    expect(sqrt(pow(controller.longitude - 72.81, 2)), lessThan(1e-9));
  });
}
