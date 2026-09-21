import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/alignment/mount_alignment.dart';
import 'package:gatisaarth/core/nav/ai/ai_types.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/motion/motion_classifier.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';
import 'package:gatisaarth/core/nav/replay/replay_engine.dart';

import '../support/ai_injection.dart';
import '../support/drive_simulator.dart';

Vector3 get _rest => Vector3(0, 0, -NavMath.gravity);

/// Feeds [seconds] of a stopped vehicle at 50 Hz starting at [fromUs], with a
/// vertical impulse of [impulse] m/s^2 for 3 samples at [shockUs] when given.
/// Returns the stationary flag after every sample and the time it was taken.
List<({int us, bool stationary})> _stopped(
  MotionClassifier motion, {
  required double seconds,
  int fromUs = 0,
  int? shockUs,
  double impulse = 9.5,
  bool Function(int us)? hold,
}) {
  final out = <({int us, bool stationary})>[];
  final n = (seconds * 50).round();
  for (var i = 0; i < n; i++) {
    final us = fromUs + i * 20000;
    var accel = _rest;
    if (shockUs != null && us >= shockUs && us < shockUs + 60000) {
      accel = accel + Vector3(0, 0, -impulse);
    }
    final s = motion.addSample(
      accelBody: accel,
      gyroBody: Vector3.zero(),
      monotonicUs: us,
      shockHold: hold?.call(us) ?? false,
    );
    out.add((us: us, stationary: s.isStationary));
  }
  return out;
}

int _stationarySamples(List<({int us, bool stationary})> run, int from, int to) =>
    run.where((r) => r.us >= from && r.us < to && r.stationary).length;

void main() {
  const shock = 5 * 1000000;
  const holdUs = 1200000;
  bool holding(int us) => us >= shock && us < shock + 60000 + holdUs;

  group('the stillness test through a shock', () {
    test('without a hold a pothole at a red light drops the stop for over a '
        'second', () {
      final run = _stopped(MotionClassifier(), seconds: 10, shockUs: shock);
      expect(_stationarySamples(run, shock - 1000000, shock), 50);
      // Of the 60 samples in the 1.2 s after the impulse, only the first few
      // (the exit delay) are still stopped.
      expect(_stationarySamples(run, shock + 60000, shock + 1260000),
          lessThan(20));
    });

    test('with the hold the stop survives the shock', () {
      final run = _stopped(MotionClassifier(),
          seconds: 10, shockUs: shock, hold: holding);
      expect(_stationarySamples(run, shock + 60000, shock + 1260000), 60);
    });

    test('a hold never starts a stop: it only keeps one', () {
      // Held from the first sample, but the vehicle has to be quiet on its own
      // merits before it counts as stopped: the shock at 0.2 s keeps the
      // one-second variance up until 1.2 s, and the stop then needs 0.6 s of
      // quiet, so nothing is stationary before 1.8 s. Without the rule the hold
      // would skip the variance test and declare a stop at once.
      final motion = MotionClassifier();
      final run =
          _stopped(motion, seconds: 1.7, shockUs: 200000, hold: (_) => true);
      expect(run.every((r) => !r.stationary), isTrue);
    });

    test('a vehicle that really sets off is released quickly, hold or not', () {
      final motion = MotionClassifier();
      _stopped(motion, seconds: 4);
      var releasedAtUs = -1;
      for (var i = 0; i < 100; i++) {
        final us = 4000000 + i * 20000;
        final s = motion.addSample(
          // 1.5 m/s^2 forward: pulling away, while a shock is being held.
          accelBody: Vector3(1.5, 0, -NavMath.gravity),
          gyroBody: Vector3.zero(),
          monotonicUs: us,
          shockHold: true,
        );
        if (!s.isStationary && releasedAtUs < 0) releasedAtUs = us;
      }
      expect(releasedAtUs, isNot(-1));
      // The 250 ms exit delay, the horizontal-force test's first five samples.
      expect(releasedAtUs - 4000000, lessThan(500000));
    });

    test('the default is the old behaviour: no argument, no hold', () {
      final a = _stopped(MotionClassifier(), seconds: 10, shockUs: shock);
      final b = _stopped(MotionClassifier(),
          seconds: 10, shockUs: shock, hold: (_) => false);
      expect([for (final r in a) r.stationary],
          [for (final r in b) r.stationary]);
    });
  });

  group('tilt learning through a shock', () {
    Vector3 up(MountAlignmentEstimator e) => e.upInPhone!;

    MountAlignmentEstimator settled() {
      final e = MountAlignmentEstimator();
      for (var i = 0; i < 200; i++) {
        e.add(
            accelPhone: Vector3(0.1, 0.2, 9.8),
            gyroPhone: Vector3.zero(),
            monotonicUs: i * 20000);
      }
      return e;
    }

    test('a shocked sample can move the gravity estimate; a held one cannot',
        () {
      final free = settled();
      final held = settled();
      final before = up(free);
      for (var i = 200; i < 205; i++) {
        final shocked = Vector3(0.1, 0.2, 9.8) + Vector3(6, -5, 4);
        free.add(
            accelPhone: shocked,
            gyroPhone: Vector3.zero(),
            monotonicUs: i * 20000);
        held.add(
            accelPhone: shocked,
            gyroPhone: Vector3.zero(),
            monotonicUs: i * 20000,
            hold: true);
      }
      expect((up(held) - before).length, 0.0);
      expect((up(free) - before).length, greaterThan(1e-4));
    });
  });

  group('through the whole engine', () {
    const shockAt = 158 * 1000000;
    late PhoneMount mount;
    late List<DriveRecord> log;

    setUpAll(() {
      mount = PhoneMount.tilted();
      // The calibration drive, which ends stopped, then 40 s standing still with
      // a pothole 15 s in.
      log = simulateDriveLogWithAi(
        setup: calibrationDrive(),
        segments: const [DriveSegment(seconds: 40)],
        mount: mount,
        inject: false,
        disturb: (i, us, accel, gyro) => us >= shockAt && us < shockAt + 60000
            ? (accel: accel + mount.down * -9.5, gyro: gyro)
            : (accel: accel, gyro: gyro),
      );
    });

    /// Which constraint the engine applied after each IMU sample from just
    /// before the shock to just after the hold: 'zupt', 'zaru' or 'nhc'.
    List<String?> constraints(AiConfig ai) {
      final replay =
          ReplayEngine(records: log, config: NavConfig(ai: ai));
      final names = <String?>[];
      while (!replay.isFinished) {
        final step = replay.stepOnce()!;
        final us = step.record.monotonicUs;
        if (step.record.type != DriveRecordType.imu) continue;
        if (us < shockAt + 60000 || us >= shockAt + 60000 + 1200000) continue;
        final m = replay.engine.recentMeasurements;
        names.add(m.isEmpty ? null : m.last.name);
      }
      return names;
    }

    test('with the AI off, ZARU keeps learning from the shaken gyro and the '
        'stop is dropped, so NHC takes over', () {
      final names = constraints(const AiConfig());
      expect(names, hasLength(60));
      expect(names.where((n) => n == 'nhc').length, greaterThan(20));
    });

    test('with disturbance adaptation on, ZUPT holds through the shock and '
        'ZARU is suspended for it', () {
      final names = constraints(
          const AiConfig(enabled: true, speedMeasurement: false));
      expect(names, hasLength(60));
      expect(names.where((n) => n == 'nhc'), isEmpty);
      expect(names.where((n) => n == 'zaru'), isEmpty);
      expect(names.where((n) => n == 'zupt').length, 60);
    });

    test('and it is released afterwards: ZARU resumes once the hold is over',
        () {
      final replay = ReplayEngine(
          records: log,
          config: const NavConfig(
              ai: AiConfig(enabled: true, speedMeasurement: false)));
      String? last;
      var held = false;
      while (!replay.isFinished) {
        final step = replay.stepOnce()!;
        if (step.record.type != DriveRecordType.imu) continue;
        final us = step.record.monotonicUs;
        if (us > shockAt && us < shockAt + 1000000) {
          held |= replay.engine.aiDiagnostics.shockHeld;
        }
        if (us > shockAt + 4000000 && replay.engine.recentMeasurements.isNotEmpty) {
          last = replay.engine.recentMeasurements.last.name;
        }
      }
      expect(held, isTrue);
      expect(last, 'zaru');
    });

    test('a pothole is reported as one in the diagnostics while it is held',
        () {
      final replay = ReplayEngine(
          records: log,
          config: const NavConfig(
              ai: AiConfig(enabled: true, speedMeasurement: false)));
      ShockKind? seen;
      while (!replay.isFinished) {
        final step = replay.stepOnce()!;
        if (step.record.type != DriveRecordType.imu) continue;
        final us = step.record.monotonicUs;
        if (us > shockAt + 100000 && us < shockAt + 500000) {
          seen ??= replay.engine.aiDiagnostics.disturbance?.shock;
        }
      }
      expect(seen, ShockKind.pothole);
    });
  });
}
