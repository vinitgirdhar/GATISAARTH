import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/replay/replay_engine.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/platform/storage/drive_log_store.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

/// In-memory storage, so the wiring can be tested without a file system.
class FakeLogSink implements DriveLogSink {
  final List<String> lines = [];
  bool open_ = false;
  bool failToOpen = false;
  int closes = 0;
  int flushes = 0;

  @override
  Future<void> flush() async => flushes++;

  @override
  Object? lastError;

  @override
  Future<String?> open(String sessionId) async {
    if (failToOpen) {
      lastError = 'no storage';
      return null;
    }
    open_ = true;
    return '/fake/$sessionId.jsonl';
  }

  @override
  void write(String line) {
    if (open_) lines.add(line);
  }

  @override
  Future<DriveLogFile?> close() async {
    closes++;
    if (!open_) return null;
    open_ = false;
    return DriveLogFile(
      path: '/fake/drive.jsonl',
      name: 'drive.jsonl',
      sizeBytes: lines.join('\n').length,
      modified: DateTime(2026, 9, 19),
    );
  }
}

const _fix = GnssFix(
  latitude: 19.45,
  longitude: 72.81,
  altitude: 12,
  accuracy: 5,
  speed: 10,
);

/// Frame layout: [ax, ay, az, gx, gy, gz, t, mx, my, mz, pressure, altitude].
List<double> _frame(double t, {double ax = 0, double az = 9.81}) =>
    [ax, 0, az, 0, 0, 0, t, 0, 30, 0, 1013.2, 0];

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// Recording a real drive is what makes the P0.10 handover decision possible:
/// the engine can only take over the position once a replay of recorded phone
/// data shows it beating the heuristic.
void main() {
  late FakeSensors sensors;
  late FakeHardware hardware;
  late FakeLogSink logSink;
  late FakeLocationGateway gateway;
  late DateTime now;
  late LiveSessionController controller;
  late FakeSpeed speedModel;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sensors = FakeSensors();
    hardware = FakeHardware();
    logSink = FakeLogSink();
    gateway = FakeLocationGateway();
    now = DateTime(2026, 9, 19, 12);
    speedModel = FakeSpeed();
    controller = LiveSessionController(
      sensors: sensors,
      alignment: VehicleAlignmentEngine(),
      hardware: hardware,
      speedEstimator: speedModel,
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

  Future<void> feed(int count, {double from = 100, double dt = 0.02}) async {
    for (var i = 0; i < count; i++) {
      sensors.frames.add(_frame(from + i * dt));
    }
    await settle();
  }

  test('fresh neural outputs reach the recorded engine input once', () async {
    await controller.start();
    await controller.startRecording();
    await feed(60);
    speedModel.inferences = 1;
    await feed(10, from: 102);
    final ai = logSink.lines.where((line) => line.contains('"t":"a"')).toList();
    expect(ai, hasLength(1));
    await feed(10, from: 103);
    expect(
        logSink.lines.where((line) => line.contains('"t":"a"')), hasLength(1));
  });

  test('recording is off until the driver asks for it', () async {
    await controller.start();
    await feed(50);
    expect(controller.isRecording, isFalse);
    expect(logSink.lines, isEmpty);
    expect(controller.recordingPath, isNull);
  });

  test('starting a recording writes a header then the drive', () async {
    await controller.start();
    final path = await controller.startRecording(
      mountDescription: 'windscreen cradle',
    );
    expect(path, isNotNull);
    expect(controller.isRecording, isTrue);

    await feed(60);
    gateway.fixController.add(_fix);
    await settle();
    controller.tick();

    expect(logSink.lines.first, contains('"t":"m"'));
    expect(logSink.lines.first, contains('windscreen cradle'));
    expect(logSink.lines.any((l) => l.contains('"t":"i"')), isTrue);
    expect(logSink.lines.any((l) => l.contains('"t":"g"')), isTrue);
    expect(controller.recordedLines, greaterThan(60));
  });

  test('the header names the phone and the vehicle it was recorded on',
      () async {
    await controller.start();
    controller.setVehicleProfile(VehicleProfile.twoWheeler);
    await controller.startRecording();
    final header = logSink.lines.first;
    expect(header, contains('"dev":"Test Phone"'));
    expect(header, contains('"os":"Android 15 (API 35)"'));
    expect(header, contains('"veh":"twoWheeler"'));
  });

  test('the chosen vehicle survives an app restart', () async {
    await controller.start();
    controller.setVehicleProfile(VehicleProfile.twoWheeler);
    await settle();

    // A second session over the same preferences, as after the app is killed.
    final restarted = LiveSessionController(
      sensors: FakeSensors(),
      alignment: VehicleAlignmentEngine(),
      hardware: FakeHardware(),
      speedEstimator: speedModel,
      telemetry: FakeTelemetry(),
      location: LiveLocationService(
        gateway: FakeLocationGateway(),
        clock: () => now,
        errorRetryDelay: Duration.zero,
      ),
      clock: () => now,
      autoTick: false,
      logStore: FakeLogSink(),
    );
    addTearDown(restarted.dispose);
    await restarted.start();
    expect(restarted.vehicleProfile, VehicleProfile.twoWheeler);
  });

  test('starting and stopping each give one confirmation, nothing else',
      () async {
    await controller.start();
    await controller.startRecording();
    await settle();
    expect(hardware.vibrations, [60]);

    await feed(100); // recording a moving phone must not buzz it further
    now = now.add(const Duration(seconds: 5));
    await controller.stopRecording();
    await settle();
    expect(hardware.vibrations, [60, 60, 60]);
  });

  test('a GNSS outage during a recording does not shake the recorded IMU',
      () async {
    await controller.start();
    gateway.fixController.add(_fix);
    await settle();
    controller.tick();
    await controller.startRecording();
    await settle();
    hardware.vibrations.clear();

    now = now.add(const Duration(seconds: 7));
    controller.tick();
    await settle();
    expect(controller.inOutage, isTrue);
    expect(hardware.vibrations, isEmpty);
  });

  test('going to the background flushes the recording to disk', () async {
    await controller.start();
    await controller.startRecording();
    await feed(30);
    expect(logSink.flushes, 0);
    await controller.pause();
    expect(logSink.flushes, 1);
  });

  test('pausing without a recording does not touch storage', () async {
    await controller.start();
    await controller.pause();
    expect(logSink.flushes, 0);
  });

  test('a recorded drive replays back through the engine', () async {
    await controller.start();
    await controller.startRecording();
    await feed(200);
    gateway.fixController.add(_fix);
    await settle();
    controller.tick();
    await controller.stopRecording();

    // The point of the whole exercise: what the phone saw can be re-run.
    final replay = ReplayEngine.fromLines(logSink.lines);
    final summary = replay.runToEnd();
    expect(replay.skippedLines, 0);
    expect(replay.meta, isNotNull);
    expect(summary.records, logSink.lines.length);
    expect(replay.engine.snapshot, isNotNull);
  });

  test('the barometer reading is captured when the phone has one', () async {
    await controller.start();
    await controller.startRecording();
    await feed(30);
    expect(logSink.lines.any((l) => l.contains('"p":1013.2')), isTrue);
  });

  test('stopping closes the file and reports its size', () async {
    await controller.start();
    await controller.startRecording();
    await feed(100);
    final file = await controller.stopRecording();
    expect(file, isNotNull);
    expect(file!.sizeBytes, greaterThan(0));
    expect(controller.isRecording, isFalse);
    expect(logSink.closes, 1);
  });

  test('nothing is recorded after stopping', () async {
    await controller.start();
    await controller.startRecording();
    await feed(50);
    final before = logSink.lines.length;
    await controller.stopRecording();
    await feed(50, from: 200);
    expect(logSink.lines.length, before);
  });

  test('a driver marker lands in the log', () async {
    await controller.start();
    await controller.startRecording();
    await feed(30);
    controller.markEvent('tunnel entry');
    expect(
      logSink.lines.any((l) => l.contains('tunnel entry')),
      isTrue,
    );
  });

  test('a marker outside a recording is simply ignored', () async {
    await controller.start();
    await feed(10);
    controller.markEvent('pothole');
    expect(logSink.lines, isEmpty);
  });

  test('storage failure is reported, not swallowed', () async {
    logSink.failToOpen = true;
    await controller.start();
    final path = await controller.startRecording();
    expect(path, isNull);
    expect(controller.isRecording, isFalse);
    expect(controller.recordingError, isNotNull);
  });

  test('starting twice does not open a second log', () async {
    await controller.start();
    final first = await controller.startRecording();
    final second = await controller.startRecording();
    expect(second, first);
  });

  test('recording does not change what the driver sees', () async {
    await controller.start();
    gateway.fixController.add(_fix);
    await settle();
    controller.tick();
    final beforeLat = controller.latitude;

    await controller.startRecording();
    await feed(100);
    expect(controller.latitude, beforeLat);
    expect(controller.hasLiveGnss, isTrue);
  });
}
