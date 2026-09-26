import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/platform/storage/drive_log_store.dart';
import 'package:gatisaarth/features/navigation_engine/domain/entities/navigation_state.dart';
import 'package:gatisaarth/features/navigation_engine/domain/navigation_safety.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';

import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

/// In-memory drive log, so recording can be asserted without a file system
/// (mirrors `test/drive_recording_test.dart`'s fake).
class _FakeLogSink implements DriveLogSink {
  final List<String> lines = [];
  bool _open = false;

  @override
  Future<void> flush() async {}

  @override
  Object? lastError;

  @override
  Future<String?> open(String sessionId) async {
    _open = true;
    return '/fake/$sessionId.jsonl';
  }

  @override
  void write(String line) {
    if (_open) lines.add(line);
  }

  @override
  Future<DriveLogFile?> close() async {
    if (!_open) return null;
    _open = false;
    return DriveLogFile(
      path: '/fake/drive.jsonl',
      name: 'drive.jsonl',
      sizeBytes: lines.join('\n').length,
      modified: DateTime(2026, 9, 25),
    );
  }
}

const _homeFix = GnssFix(
  latitude: 19.45,
  longitude: 72.81,
  altitude: 12,
  accuracy: 5,
  speed: 10,
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// Frame layout: [ax, ay, az, gx, gy, gz, t, mx, my, mz, pressure, altitude].
List<double> _frame(double t) =>
    [0, 0, 9.81, 0, 0, 0, t, 0, 30, 0, double.nan, double.nan];

void main() {
  late FakeSensors sensors;
  late FakeHardware hardware;
  late FakeLocationGateway gateway;
  late _FakeLogSink logSink;
  late DateTime now;
  late LiveSessionController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sensors = FakeSensors();
    hardware = FakeHardware();
    gateway = FakeLocationGateway();
    logSink = _FakeLogSink();
    now = DateTime(2026, 9, 25, 14, 32, 18);
    controller = LiveSessionController(
      sensors: sensors,
      alignment: VehicleAlignmentEngine(),
      hardware: hardware,
      speedEstimator: FakeSpeed(),
      telemetry: FakeTelemetry(),
      location: LiveLocationService(
        gateway: gateway,
        clock: () => now,
        errorRetryDelay: Duration.zero,
      ),
      clock: () => now,
      autoTick: false,
      logStore: logSink,
      haptics: Haptics(hardware, clock: () => now, pause: (_) async {}),
    );
  });

  tearDown(() => controller.dispose());

  Future<void> goLive([GnssFix fix = _homeFix]) async {
    await controller.start();
    gateway.fixController.add(fix);
    await settle();
    controller.tick();
  }

  test('refuses to start without a live fix, giving a reason', () async {
    await controller.start();
    final reason = controller.startSimulatedOutage(const Duration(seconds: 10));
    expect(reason, isNotNull);
    expect(controller.isSimulatingOutage, isFalse);
  });

  test('withholds real fixes from the map while running, recording them as '
      'truth instead of applying them', () async {
    await goLive();
    await controller.startRecording();
    // The engine needs one IMU sample before it has a shared timeline to
    // stamp a fix on (see `_engineNowUs`); without it nothing is recordable.
    sensors.frames.add(_frame(100));
    await settle();
    expect(controller.startSimulatedOutage(const Duration(seconds: 10)), isNull);
    expect(controller.isSimulatingOutage, isTrue);
    expect(controller.fusionMode, FusionMode.deadReckoning);
    expect(controller.hasLiveGnss, isFalse);

    final beforeLat = controller.latitude;
    gateway.fixController.add(const GnssFix(
      latitude: 20,
      longitude: 73,
      altitude: 1,
      accuracy: 5,
      speed: 12,
    ));
    await settle();
    controller.tick();

    // The map never moved to the withheld fix...
    expect(controller.latitude, closeTo(beforeLat, 1e-9));
    // ...but it was still written to the drive log as ground truth.
    expect(logSink.lines.any((l) => l.contains('"t":"g"') && l.contains('20.0')),
        isTrue);
  });

  test('ends on its own after the planned duration and scores a result',
      () async {
    await goLive();
    expect(controller.startSimulatedOutage(const Duration(seconds: 10)), isNull);

    // A little travel and a withheld fix while it runs.
    for (var i = 0; i < 5; i++) {
      sensors.frames.add(_frame(100 + i * 0.02));
    }
    await settle();
    gateway.fixController.add(const GnssFix(
      latitude: 19.46,
      longitude: 72.81,
      altitude: 12,
      accuracy: 5,
      speed: 10,
    ));
    await settle();
    controller.tick();
    expect(controller.isSimulatingOutage, isTrue);
    expect(controller.lastSimulatedOutageResult, isNull);

    now = now.add(const Duration(seconds: 11));
    controller.tick();

    expect(controller.isSimulatingOutage, isFalse);
    final result = controller.lastSimulatedOutageResult;
    expect(result, isNotNull);
    expect(result!.coreLed, isFalse); // heuristic pipeline in this fixture
    // Logged only once the first restored fix is fused (the recovery jump).
    expect(result.recoveryJumpM, isNull);
    expect(controller.outageLog.isEmpty, isTrue);

    gateway.fixController.add(const GnssFix(
      latitude: 19.461,
      longitude: 72.81,
      altitude: 12,
      accuracy: 5,
      speed: 10,
    ));
    await settle();
    controller.tick();

    expect(controller.hasLiveGnss, isTrue);
    expect(controller.lastSimulatedOutageResult!.recoveryJumpM, isNotNull);
    // Exactly one entry: the simulator's, never a duplicate "real" one from
    // the engine recovering from the same blackout.
    expect(controller.outageLog.entries, hasLength(1));
    expect(controller.outageLog.entries.single.isSimulated, isTrue);
    expect(controller.outageLog.entries.single.recoveryJumpM, isNotNull);

    // More fixes later never add the engine's recovery of it after all.
    for (var i = 1; i <= 3; i++) {
      now = now.add(const Duration(seconds: 1));
      gateway.fixController.add(GnssFix(
        latitude: 19.461 + i * 1e-5,
        longitude: 72.81,
        altitude: 12,
        accuracy: 5,
        speed: 10,
      ));
      await settle();
      controller.tick();
    }
    expect(controller.outageLog.entries, hasLength(1));
  });

  test('with no fix after the blackout it is logged with the jump unmeasured',
      () async {
    await goLive();
    expect(controller.startSimulatedOutage(const Duration(seconds: 10)), isNull);
    now = now.add(const Duration(seconds: 11));
    controller.tick();
    expect(controller.outageLog.isEmpty, isTrue);
    now = now.add(const Duration(seconds: 11));
    controller.tick();
    expect(controller.outageLog.entries, hasLength(1));
    expect(controller.outageLog.entries.single.recoveryJumpM, isNull);
  });

  test('the safety level treats a simulated blackout as dead reckoning, and '
      'steps back to reliable only after the fix returns', () async {
    await goLive();
    controller.tick();
    expect(controller.trust.level, TrustLevel.green);
    expect(controller.startSimulatedOutage(const Duration(seconds: 10)), isNull);
    // Real fixes keep arriving underneath; the badge must not say GREEN.
    gateway.fixController.add(_homeFix);
    await settle();
    controller.tick();
    // Dead reckoning, not a false "filter failed": the core has not aligned
    // in this fixture, and that must not read as RED.
    expect(controller.trust.level, TrustLevel.amber);

    now = now.add(const Duration(seconds: 11));
    controller.tick();
    gateway.fixController.add(_homeFix);
    await settle();
    controller.tick();
    // De-escalation waits out the hysteresis before saying GREEN again.
    expect(controller.trust.level, isNot(TrustLevel.green));
    for (var i = 0; i < 6; i++) {
      now = now.add(const Duration(seconds: 1));
      gateway.fixController.add(_homeFix);
      await settle();
      controller.tick();
    }
    expect(controller.trust.level, TrustLevel.green);
  });

  test('cancelling early produces no result and no log entry', () async {
    await goLive();
    expect(controller.startSimulatedOutage(const Duration(seconds: 30)), isNull);
    controller.cancelSimulatedOutage();
    expect(controller.isSimulatingOutage, isFalse);
    expect(controller.lastSimulatedOutageResult, isNull);
    expect(controller.outageLog.isEmpty, isTrue);
  });

  test('a second start while one is already running is refused', () async {
    await goLive();
    expect(controller.startSimulatedOutage(const Duration(seconds: 30)), isNull);
    final reason = controller.startSimulatedOutage(const Duration(seconds: 10));
    expect(reason, isNotNull);
  });

  test('pausing the app cancels a running blackout', () async {
    await goLive();
    expect(controller.startSimulatedOutage(const Duration(seconds: 30)), isNull);
    await controller.pause();
    expect(controller.isSimulatingOutage, isFalse);
    expect(controller.lastSimulatedOutageResult, isNull);
  });

  test('the hidden tunnel-test hook still works unchanged', () async {
    await goLive();
    controller.startTunnelTest();
    await settle();
    expect(controller.isSimulatingTunnel, isTrue);
    expect(controller.fusionMode, FusionMode.deadReckoning);

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
  });
}
