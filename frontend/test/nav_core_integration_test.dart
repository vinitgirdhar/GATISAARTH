import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/model/nav_snapshot.dart';
import 'package:gatisaarth/core/nav/sensors/sensor_sample.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/navigation_engine/domain/entities/navigation_state.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

const _fix = GnssFix(
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
  double ay = 0,
  double az = 9.81,
  double gz = 0,
  double mx = 0,
  double my = 30,
}) =>
    [ax, ay, az, 0, 0, gz, t, mx, my, 0, double.nan, double.nan];

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// The navigation core runs alongside the shipping pipeline (step 0.10 of
/// docs/architecture/EVOLUTION_PLAN.md).
///
/// These tests pin two things: that it is genuinely being fed real frames, and
/// that it has not taken over anything the driver sees. The handover happens
/// only once a replay of recorded phone data shows it beating the heuristic.
void main() {
  late FakeSensors sensors;
  late FakeHardware hardware;
  late FakeSpeed speedFake;
  late FakeTelemetry telemetry;
  late FakeLocationGateway gateway;
  late DateTime now;
  late LiveSessionController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sensors = FakeSensors();
    hardware = FakeHardware();
    speedFake = FakeSpeed();
    telemetry = FakeTelemetry();
    gateway = FakeLocationGateway();
    now = DateTime(2026, 9, 19, 12);
    controller = LiveSessionController(
      sensors: sensors,
      alignment: VehicleAlignmentEngine(),
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

  Future<void> feed(int count, {double from = 100, double dt = 0.02}) async {
    for (var i = 0; i < count; i++) {
      sensors.frames.add(_frame(from + i * dt));
    }
    await settle();
  }

  test('the core is fed real sensor frames and publishes a snapshot',
      () async {
    await controller.start();
    expect(controller.navSnapshot, isNull);

    await feed(60);
    final snapshot = controller.navSnapshot;
    expect(snapshot, isNotNull);
    expect(snapshot!.sequence, greaterThan(0));
    expect(
      snapshot.sensorStats[SensorType.accelerometer]?.received,
      greaterThan(50),
    );
  });

  test('it reports calibrating, not a position, before the mount is known',
      () async {
    await controller.start();
    await feed(80);
    expect(controller.engineMode, NavMode.calibrating);
    expect(controller.isMountCalibrated, isFalse);
    expect(controller.navSnapshot!.hasPosition, isFalse);
  });

  test('fixes reach the core', () async {
    await controller.start();
    // A sensor frame first: until one arrives there is no shared timeline to
    // stamp a fix on, so the core cannot use it and does not pretend to.
    await feed(5);
    gateway.fixController.add(_fix);
    await settle();
    controller.tick();
    expect(controller.engineFixCount, greaterThan(0));
  });

  test('a fix before the first sensor frame is not fabricated a timestamp',
      () async {
    await controller.start();
    gateway.fixController.add(_fix);
    await settle();
    controller.tick();
    expect(controller.engineFixCount, 0);
    // The old pipeline still shows it, so the driver sees a position.
    expect(controller.latitude, closeTo(_fix.latitude, 1e-9));
  });

  test('mount confidence is null until there is evidence, never zero-dressed-'
      'up-as-a-number', () async {
    await controller.start();
    await feed(40);
    expect(controller.mountConfidence, isNull);
    expect(controller.isMountCalibrated, isFalse);
  });

  test('the core does NOT drive anything the driver sees', () async {
    await controller.start();
    gateway.fixController.add(_fix);
    await settle();
    controller.tick();
    await feed(100);

    // The map marker, speed and confidence still come from the existing
    // pipeline: the fix, not the filter.
    expect(controller.latitude, closeTo(_fix.latitude, 1e-9));
    expect(controller.longitude, closeTo(_fix.longitude, 1e-9));
    expect(controller.speed, closeTo(_fix.speed, 1e-9));
    expect(controller.hasLiveGnss, isTrue);
    expect(controller.fusionMode, FusionMode.gnssLocked);
  });

  test('a two-wheeler profile reaches the core', () async {
    await controller.start();
    controller.setVehicleProfile(VehicleProfile.twoWheeler);
    await feed(30);
    // No exception, and the old engine still got it too.
    expect(controller.vehicleProfile, VehicleProfile.twoWheeler);
  });

  test('a corrupt sensor frame cannot take the app down', () async {
    await controller.start();
    sensors.frames.add(_frame(10, ax: double.nan));
    sensors.frames.add(_frame(10.02, az: double.infinity));
    await settle();
    await feed(20, from: 11);
    expect(controller.navSnapshot, isNotNull);
    expect(controller.engineMode, isNot(NavMode.sensorFailure));
  });

  test('per-frame cost is measured, not guessed', () async {
    await controller.start();
    await feed(200);
    final mean = controller.engineMeanMicros;
    expect(mean, isNotNull);
    // A real bound, not a target: 15x15 matrix work at 50 Hz has to stay well
    // inside a frame budget or it belongs on another isolate (§45, §46).
    // ignore: avoid_print
    print('navigation core: ${mean!.toStringAsFixed(0)} us/frame mean, '
        '${controller.enginePeakMicros} us peak, over 200 frames');
    expect(mean, lessThan(2000),
        reason: 'navigation core mean ${mean.toStringAsFixed(0)} us/frame');
    expect(controller.enginePeakMicros, isNotNull);
  });

  test('mode transitions carry reasons', () async {
    await controller.start();
    await feed(60);
    final transitions = controller.engineTransitions;
    expect(transitions, isNotEmpty);
    expect(transitions.every((t) => t.reason.isNotEmpty), isTrue);
  });
}
