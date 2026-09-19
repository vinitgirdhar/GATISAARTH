import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/navigation_engine/domain/entities/navigation_state.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

/// The handover contract (P0.10).
///
/// The navigation core takes over the driver-facing position only while it is
/// demonstrably healthy, and hands straight back otherwise. The property worth
/// defending is one-directional: **the app can never be worse than it was
/// before the core existed.**
void main() {
  late FakeSensors sensors;
  late FakeLocationGateway gateway;
  late DateTime now;
  late LiveSessionController controller;

  /// Where the simulated vehicle actually is.
  const startLat = 19.45;
  const startLon = 72.81;

  var _t = 100.0;
  var _speed = 0.0;
  var _north = 0.0;
  var _nextFix = 0.0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sensors = FakeSensors();
    gateway = FakeLocationGateway();
    now = DateTime(2026, 9, 19, 12);
    _t = 100.0;
    _speed = 0.0;
    _north = 0.0;
    _nextFix = 0.0;
    controller = LiveSessionController(
      sensors: sensors,
      alignment: VehicleAlignmentEngine(),
      hardware: FakeHardware(),
      speedEstimator: FakeSpeed(),
      telemetry: FakeTelemetry(),
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

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  GnssFix fixAt(double north, double east, {double speed = 0}) {
    final moved = NavMath.addNed(
      latDeg: startLat,
      lonDeg: startLon,
      altM: 0,
      north: north,
      east: east,
      down: 0,
    );
    return GnssFix(
      latitude: moved[0],
      longitude: moved[1],
      altitude: 12,
      accuracy: 5,
      speed: speed,
    );
  }

  /// Phone flat on the dash, top pointing forward: vehicle forward is phone +y,
  /// vehicle down is phone -z.
  ///
  /// Jitter is not decoration. Real MEMS always moves at the least significant
  /// bit, and the fault detector treats byte-identical readings as a frozen
  /// sensor — correctly. A test feeding perfect zeros gets flagged, which is
  /// the detector doing its job, not a bug.
  final rng = math.Random(1234);
  double n(double scale) => (rng.nextDouble() - 0.5) * 2 * scale;

  List<double> frame(
    double t, {
    double longitudinal = 0,
    double lateral = 0,
  }) {
    // Specific force in the vehicle frame, expressed in phone coordinates.
    return [
      lateral + n(0.02),
      longitudinal + n(0.02),
      NavMath.gravity + n(0.02),
      n(0.001),
      n(0.001),
      n(0.001),
      t,
      n(0.2),
      30 + n(0.2),
      n(0.2),
      double.nan,
      double.nan,
    ];
  }

  /// Drives a calibration pattern: repeated accelerate/brake on a straight
  /// road with GNSS live, which is what the mount alignment needs.
  Future<void> driveCalibration({int cycles = 16}) async {
    for (var cycle = 0; cycle < cycles; cycle++) {
      for (final accel in [1.8, 0.0, -1.8, 0.0]) {
        final seconds = accel == 0 ? 1.0 : 4.0;
        for (var i = 0; i < seconds * 50; i++) {
          _t += 0.02;
          now = now.add(const Duration(milliseconds: 20));
          final applied = (_speed <= 0 && accel < 0) ? 0.0 : accel;
          _speed = math.max(0.0, _speed + applied * 0.02);
          _north += _speed * 0.02;
          sensors.frames.add(frame(_t, longitudinal: applied));
          if (_t >= _nextFix) {
            _nextFix = _t + 1.0;
            gateway.fixController.add(fixAt(_north, 0, speed: _speed));
          }
          // Drained per frame on purpose. Batching the adds and draining
          // afterwards lets the fake clock run seconds ahead of the samples,
          // which no real phone does, and every timestamp the core sees is then
          // wrong.
          await settle();
        }
        controller.tick();
      }
    }
  }

  test('the core does NOT lead until the mount has converged', () async {
    await controller.start();
    gateway.fixController.add(fixAt(0, 0));
    await settle();
    controller.tick();

    // A few seconds of stationary frames teach it nothing about yaw.
    for (var i = 0; i < 200; i++) {
      sensors.frames.add(frame(100 + i * 0.02));
    }
    await settle();
    controller.tick();

    expect(controller.isEngineLeading, isFalse);
    expect(controller.engineHandoverBlocker, isNotNull);
    expect(
      controller.engineHandoverBlocker,
      anyOf(contains('mount'), contains('fix'), contains('core')),
    );
  });

  test('while not leading, the app behaves exactly as it always did', () async {
    await controller.start();
    final fix = fixAt(0, 0, speed: 10);
    gateway.fixController.add(fix);
    await settle();
    controller.tick();

    expect(controller.isEngineLeading, isFalse);
    // The old contract, unchanged: position and speed come from the fix.
    expect(controller.latitude, closeTo(fix.latitude, 1e-9));
    expect(controller.longitude, closeTo(fix.longitude, 1e-9));
    expect(controller.speed, closeTo(10, 1e-9));
    expect(controller.fusionMode, FusionMode.gnssLocked);
    // And the old modelled uncertainty, not a covariance.
    expect(controller.uncertainty!.marginMeters, closeTo(5, 1e-9));
  });

  test('after a calibration drive the core takes over', () async {
    await controller.start();
    await driveCalibration();

    expect(controller.isEngineLeading, isTrue,
        reason: 'blocker: ${controller.engineHandoverBlocker}');
    expect(controller.engineHandoverBlocker, isNull);
    expect(controller.mountConfidence, isNotNull);
    expect(controller.isMountCalibrated, isTrue);
  });

  test('once leading, uncertainty is covariance-derived, not the 5 % formula',
      () async {
    await controller.start();
    await driveCalibration();
    expect(controller.isEngineLeading, isTrue);

    final margin = controller.uncertainty!.marginMeters;
    final sigma = controller.navSnapshot!.horizontalSigmaM!;
    expect(margin, closeTo(math.max(sigma, 3), 1e-9));
  });

  test('once leading, a teleporting fix cannot move the marker', () async {
    await controller.start();
    await driveCalibration();
    expect(controller.isEngineLeading, isTrue);

    final beforeLat = controller.latitude;
    final beforeLon = controller.longitude;

    // 5 km away, claiming 5 m accuracy. The old pipeline would have snapped
    // the marker onto it.
    gateway.fixController.add(fixAt(_north + 5000, 0, speed: 10));
    now = now.add(const Duration(seconds: 1));
    await settle();
    controller.tick();

    final moved = NavMath.horizontalDistance(
      lat0: beforeLat,
      lon0: beforeLon,
      lat1: controller.latitude,
      lon1: controller.longitude,
    );
    expect(moved, lessThan(50),
        reason: 'a single bad fix moved the marker ${moved.round()} m');
  });

  test('losing GNSS keeps the core leading and reports dead reckoning',
      () async {
    await controller.start();
    await driveCalibration();
    expect(controller.isEngineLeading, isTrue);

    // Location switched off mid-drive.
    gateway.serviceEnabled = false;
    gateway.serviceChanges.add(false);
    now = now.add(const Duration(seconds: 10));
    await settle();
    controller.tick();

    expect(controller.inOutage, isTrue);
    expect(controller.fusionMode, FusionMode.deadReckoning);
    // The position is still the core's, and still finite.
    expect(controller.latitude.isFinite, isTrue);
    expect(controller.longitude.isFinite, isTrue);
  });

  test('a sensor failure hands control straight back', () async {
    await controller.start();
    await driveCalibration();
    expect(controller.isEngineLeading, isTrue);

    // The accelerometer freezes: byte-identical readings, which real MEMS
    // never produce.
    var t = 10000.0;
    for (var i = 0; i < 200; i++) {
      t += 0.02;
      // Byte-identical readings: a frozen sensor, which real MEMS never is.
      sensors.frames.add(
          [1.0, 2.0, 3.0, 0, 0, 0, t, 0, 30, 0, double.nan, double.nan]);
    }
    await settle();
    controller.tick();

    expect(controller.isEngineLeading, isFalse);
    expect(controller.engineHandoverBlocker, isNotNull);
    // Still a usable app: the old pipeline is back in charge.
    expect(controller.latitude.isFinite, isTrue);
    expect(controller.navigationState.latitude.isFinite, isTrue);
  });

  test('the position is never NaN, whoever is leading', () async {
    await controller.start();
    expect(controller.latitude.isFinite, isTrue);
    await driveCalibration(cycles: 4);
    expect(controller.latitude.isFinite, isTrue);
    await driveCalibration(cycles: 14);
    expect(controller.latitude.isFinite, isTrue);
    expect(controller.speed.isFinite, isTrue);
    expect(controller.heading.isFinite, isTrue);
    expect(controller.heading, inInclusiveRange(0, 360));
  });

  test('sensor health reports working, not merely present', () async {
    await controller.start();
    // A magnetometer reading 250 uT is present and useless.
    var t = 100.0;
    for (var i = 0; i < 200; i++) {
      t += 0.02;
      sensors.frames.add([
        n(0.02),
        n(0.02),
        9.81 + n(0.02),
        n(0.001),
        n(0.001),
        n(0.001),
        t,
        250 + n(0.5),
        250 + n(0.5),
        250 + n(0.5),
        double.nan,
        double.nan,
      ]);
    }
    await settle();
    controller.tick();

    expect(controller.sensorHealth.magnetometer, isFalse);
    expect(controller.sensorHealth.accelerometer, isTrue);
  });
}
