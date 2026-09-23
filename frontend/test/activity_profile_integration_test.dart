import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/motion/activity_mode.dart';
import 'package:gatisaarth/core/platform/activity/activity_mode_source.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

class _ActivitySource implements ActivityModeSource {
  final controller = StreamController<ActivityObservation>.broadcast();

  @override
  Stream<ActivityObservation> get observations => controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('walking transition selects pedestrian profile and disables car mode',
      () async {
    SharedPreferences.setMockInitialValues({});
    final activity = _ActivitySource();
    final hardware = FakeHardware();
    final session = LiveSessionController(
      sensors: FakeSensors(),
      alignment: VehicleAlignmentEngine(),
      hardware: hardware,
      speedEstimator: FakeSpeed(),
      telemetry: FakeTelemetry(),
      location: LiveLocationService(
        gateway: FakeLocationGateway(),
        errorRetryDelay: Duration.zero,
      ),
      activityModes: activity,
      autoTick: false,
      haptics: Haptics(hardware, pause: (_) async {}),
    );
    addTearDown(() async {
      session.dispose();
      await activity.controller.close();
    });
    await session.start();

    activity.controller.add(ActivityObservation.walking);
    await Future<void>.delayed(Duration.zero);
    expect(session.vehicleProfile, VehicleProfile.car);

    await session.setAutomaticActivityEnabled(true);
    activity.controller.add(ActivityObservation.walking);
    await Future<void>.delayed(Duration.zero);

    expect(session.activityMode, ActivityMode.pedestrian);
    expect(session.vehicleProfile, VehicleProfile.pedestrian);

    session.setVehicleProfile(VehicleProfile.car);
    expect(session.automaticActivityEnabled, isFalse);
    activity.controller.add(ActivityObservation.bicycle);
    await Future<void>.delayed(Duration.zero);
    expect(session.vehicleProfile, VehicleProfile.car);
  });

  test('automatic car, two-wheeler and walking transitions select profiles',
      () async {
    SharedPreferences.setMockInitialValues({});
    final activity = _ActivitySource();
    final session = LiveSessionController(
      sensors: FakeSensors(),
      alignment: VehicleAlignmentEngine(),
      hardware: FakeHardware(),
      speedEstimator: FakeSpeed(),
      telemetry: FakeTelemetry(),
      location: LiveLocationService(
        gateway: FakeLocationGateway(),
        errorRetryDelay: Duration.zero,
      ),
      activityModes: activity,
      autoTick: false,
    );
    addTearDown(() async {
      session.dispose();
      await activity.controller.close();
    });
    await session.start();
    await session.setAutomaticActivityEnabled(true);

    activity.controller.add(ActivityObservation.bicycle);
    await Future<void>.delayed(Duration.zero);
    expect(session.vehicleProfile, VehicleProfile.twoWheeler);
    expect(session.activityMode, ActivityMode.bicycle);

    activity.controller.add(ActivityObservation.inVehicle);
    await Future<void>.delayed(Duration.zero);
    expect(session.vehicleProfile, VehicleProfile.car);
    expect(session.activityMode, ActivityMode.car);

    activity.controller.add(ActivityObservation.walking);
    await Future<void>.delayed(Duration.zero);
    expect(session.vehicleProfile, VehicleProfile.pedestrian);
    expect(session.activityMode, ActivityMode.pedestrian);
  });
}
