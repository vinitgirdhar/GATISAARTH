import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_quality.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/model/nav_snapshot.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';
import 'package:gatisaarth/core/nav/sensors/sensor_sample.dart';

import 'support/drive_simulator.dart';

/// Accelerates to about 15 m/s and holds it, with GNSS still live.
const cruiseUp = [
  DriveSegment(seconds: 10, longitudinalAccel: 1.5),
  DriveSegment(seconds: 5),
];

/// Result of running a drive through the engine.
class RunResult {
  RunResult(this.engine, this.simulator);

  final NavigationEngine engine;
  final DriveSimulator simulator;

  TruthSample get truth => simulator.truth;

  /// Distance between the engine's estimate and ground truth (m), or null
  /// when the engine has no position.
  double? get positionError {
    final s = engine.snapshot;
    if (s == null || !s.hasPosition) return null;
    return NavMath.horizontalDistance(
      lat0: truth.latitude,
      lon0: truth.longitude,
      lat1: s.latitude!,
      lon1: s.longitude!,
    );
  }
}

/// Runs [segments] through the engine, feeding GNSS at 1 Hz unless the clock
/// falls inside [outage].
RunResult run(
  List<DriveSegment> segments, {
  NavigationEngine? engine,
  DriveSimulator? simulator,
  bool Function(double seconds)? gnssAvailable,
}) {
  final e = engine ?? NavigationEngine();
  final sim = simulator ??
      DriveSimulator(mount: PhoneMount.tilted(yawDeg: 35, tiltDeg: 20));

  var nextGnssUs = 0;
  for (final segment in segments) {
    final steps = (segment.seconds * sim.imuHz).round();
    for (var i = 0; i < steps; i++) {
      final frame = sim.step(segment);
      e.onImu(
        accelPhone: frame.accelPhone,
        gyroPhone: frame.gyroPhone,
        monotonicUs: frame.truth.monotonicUs,
      );
      if (frame.truth.monotonicUs >= nextGnssUs) {
        nextGnssUs = frame.truth.monotonicUs + 1000000;
        final seconds = frame.truth.monotonicUs / 1e6;
        if (gnssAvailable == null || gnssAvailable(seconds)) {
          e.onGnss(sim.gnss());
        } else {
          e.onGnssLost(frame.truth.monotonicUs);
        }
      }
    }
  }
  return RunResult(e, sim);
}

void main() {
  group('start-up honesty', () {
    test('a fresh engine has no position and says so', () {
      final e = NavigationEngine();
      expect(e.snapshot, isNull);
      expect(e.mode, NavMode.boot);
      expect(e.alignment, isNull);
    });

    test('before the mount is known it reports calibrating, not a position',
        () {
      final sim = DriveSimulator(mount: PhoneMount.flatTopForward());
      final e = NavigationEngine();
      for (var i = 0; i < 100; i++) {
        final frame = sim.step(const DriveSegment(seconds: 0.02));
        e.onImu(
          accelPhone: frame.accelPhone,
          gyroPhone: frame.gyroPhone,
          monotonicUs: frame.truth.monotonicUs,
        );
      }
      expect(e.mode, NavMode.calibrating);
      expect(e.snapshot?.hasPosition ?? false, isFalse);
      expect(
        e.snapshot?.notes.any((n) => n.contains('alignment')) ?? false,
        isTrue,
      );
    });

    test('AI and map match report unavailable, never a fabricated number', () {
      final result = run(calibrationDrive());
      final s = result.engine.snapshot!;
      expect(s.ai.available, isFalse);
      expect(s.ai.source, DataSource.unavailable);
      expect(s.mapMatch.available, isFalse);
      expect(s.mapMatch.detail, 'No road graph');
      expect(s.contribution.ai, 0);
      expect(s.contribution.map, 0);
    });
  });

  group('alignment and lock', () {
    test('a calibration drive converges the mount and locks GNSS', () {
      final result = run(calibrationDrive());
      final e = result.engine;
      expect(e.alignment, isNotNull);
      expect(e.snapshot!.isMountCalibrated, isTrue);
      expect(e.mode, NavMode.gnssLocked);
      expect(e.snapshot!.integrity, NavIntegrity.high);
    });

    test('the recovered mount matches the real one', () {
      final mount = PhoneMount.tilted(yawDeg: 35, tiltDeg: 20);
      final result = run(
        calibrationDrive(),
        simulator: DriveSimulator(mount: mount),
      );
      final forward = result.engine.alignment!.forwardInPhone;
      final angleDeg = NavMath.radToDeg *
          (forward.dot(mount.forward).clamp(-1.0, 1.0) < 1
              ? (forward - mount.forward).length
              : 0);
      expect(forward.dot(mount.forward), greaterThan(0.99),
          reason: 'forward axis off by about $angleDeg deg');
    });

    test('while locked, the position tracks truth to GNSS accuracy', () {
      final result = run(calibrationDrive());
      expect(result.positionError, isNotNull);
      expect(result.positionError!, lessThan(8));
    });

    test('mode transitions are logged with reasons', () {
      final result = run(calibrationDrive());
      final transitions = result.engine.transitions;
      expect(transitions, isNotEmpty);
      expect(transitions.every((t) => t.reason.isNotEmpty), isTrue);
      expect(transitions.map((t) => t.to), contains(NavMode.gnssLocked));
      for (final t in transitions) {
        expect(t.from, isNot(t.to));
      }
    });
  });

  group('GNSS outage', () {
    test('losing GNSS switches to dead reckoning with an estimated source',
        () {
      // Calibrate, then lose GNSS for the rest of the drive.
      final e = NavigationEngine();
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      run(calibrationDrive(), engine: e, simulator: sim);
      run(cruiseUp, engine: e, simulator: sim);
      expect(e.mode, NavMode.gnssLocked);

      run(
        const [DriveSegment(seconds: 20, longitudinalAccel: 0)],
        engine: e,
        simulator: sim,
        gnssAvailable: (_) => false,
      );
      expect(e.mode, NavMode.deadReckoning);
      expect(e.snapshot!.positionSource, DataSource.estimated);
      expect(e.snapshot!.outageDuration.inSeconds, greaterThan(5));
    });

    test('uncertainty grows during the outage and shrinks on reacquisition',
        () {
      final e = NavigationEngine();
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      run(calibrationDrive(), engine: e, simulator: sim);
      run(cruiseUp, engine: e, simulator: sim);
      final locked = e.snapshot!.horizontalSigmaM!;

      run(
        const [DriveSegment(seconds: 45)],
        engine: e,
        simulator: sim,
        gnssAvailable: (_) => false,
      );
      final duringOutage = e.snapshot!.horizontalSigmaM!;
      expect(duringOutage, greaterThan(locked));

      run(
        const [DriveSegment(seconds: 10)],
        engine: e,
        simulator: sim,
      );
      expect(e.snapshot!.horizontalSigmaM!, lessThan(duringOutage));
      expect(
        e.mode,
        anyOf(NavMode.gnssLocked, NavMode.reacquiring),
      );
    });

    test('a 60 s outage at cruising speed stays inside the 10 % drift bar',
        () {
      final e = NavigationEngine();
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      run(calibrationDrive(), engine: e, simulator: sim);
      run(cruiseUp, engine: e, simulator: sim);

      final distanceAtLoss = sim.truth.distanceM;
      // 60 s of ordinary driving: cruise, a turn, cruise, a gentle stop.
      run(
        const [
          DriveSegment(seconds: 20),
          DriveSegment(seconds: 8, yawRate: 0.1),
          DriveSegment(seconds: 20),
          DriveSegment(seconds: 6, longitudinalAccel: -1.0),
          DriveSegment(seconds: 6),
        ],
        // 60 s at roughly 15 m/s is about 850 m of tunnel.
        engine: e,
        simulator: sim,
        gnssAvailable: (_) => false,
      );

      final travelled = sim.truth.distanceM - distanceAtLoss;
      final error = RunResult(e, sim).positionError!;
      final driftPercent = 100 * error / travelled;

      // This is a synthetic drive with modelled sensor error, NOT a field
      // measurement — it bounds the engine, not the product (§76, §83).
      expect(travelled, greaterThan(200));
      expect(driftPercent, lessThan(10),
          reason: 'drift ${driftPercent.toStringAsFixed(1)} % over '
              '${travelled.toStringAsFixed(0)} m');
    });

    test('dead reckoning beats holding the last known position', () {
      final e = NavigationEngine();
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      run(calibrationDrive(), engine: e, simulator: sim);
      run(cruiseUp, engine: e, simulator: sim);

      final frozenLat = e.snapshot!.latitude!;
      final frozenLon = e.snapshot!.longitude!;

      run(
        const [DriveSegment(seconds: 40)],
        engine: e,
        simulator: sim,
        gnssAvailable: (_) => false,
      );

      final drError = RunResult(e, sim).positionError!;
      final frozenError = NavMath.horizontalDistance(
        lat0: sim.truth.latitude,
        lon0: sim.truth.longitude,
        lat1: frozenLat,
        lon1: frozenLon,
      );
      expect(drError, lessThan(frozenError / 4));
    });
  });

  group('GNSS rejection in the loop', () {
    test('a teleporting fix does not move the position', () {
      final e = NavigationEngine();
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      run(calibrationDrive(), engine: e, simulator: sim);
      run(cruiseUp, engine: e, simulator: sim);

      final before = e.snapshot!;
      final good = sim.gnss();
      final jumped = NavMath.addNed(
        latDeg: good.latitudeDeg,
        lonDeg: good.longitudeDeg,
        altM: 0,
        north: 3000,
        east: 0,
        down: 0,
      );
      e.onGnss(GnssObservationFactory.at(
        lat: jumped[0],
        lon: jumped[1],
        us: good.monotonicUs + 1000000,
      ));

      final after = e.snapshot!;
      final moved = NavMath.horizontalDistance(
        lat0: before.latitude!,
        lon0: before.longitude!,
        lat1: after.latitude!,
        lon1: after.longitude!,
      );
      expect(moved, lessThan(5));
    });

    test('a stream of rejected fixes drives the mode to dead reckoning', () {
      final e = NavigationEngine();
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      run(calibrationDrive(), engine: e, simulator: sim);
      run(cruiseUp, engine: e, simulator: sim);

      var us = sim.truth.monotonicUs;
      for (var i = 0; i < 12; i++) {
        us += 1000000;
        e.onGnss(GnssObservationFactory.at(
          lat: 0,
          lon: 0,
          us: us,
        ));
      }
      expect(
        e.mode,
        anyOf(NavMode.deadReckoning, NavMode.gnssUnreliable),
      );
    });
  });

  group('snapshot contract', () {
    test('sequence numbers only ever increase', () {
      final e = NavigationEngine();
      final sim = DriveSimulator(mount: PhoneMount.flatTopForward());
      var last = 0;
      for (final segment in calibrationDrive()) {
        final steps = (segment.seconds * sim.imuHz).round();
        for (var i = 0; i < steps; i++) {
          final frame = sim.step(segment);
          final s = e.onImu(
            accelPhone: frame.accelPhone,
            gyroPhone: frame.gyroPhone,
            monotonicUs: frame.truth.monotonicUs,
          );
          if (s != null) {
            expect(s.sequence, greaterThan(last));
            last = s.sequence;
          }
        }
      }
      expect(last, greaterThan(10));
    });

    test('snapshots are rate limited to the configured UI rate', () {
      final e = NavigationEngine();
      final sim = DriveSimulator(mount: PhoneMount.flatTopForward());
      var emitted = 0;
      var frames = 0;
      for (final segment in calibrationDrive()) {
        final steps = (segment.seconds * sim.imuHz).round();
        for (var i = 0; i < steps; i++) {
          final frame = sim.step(segment);
          frames++;
          if (e.onImu(
                accelPhone: frame.accelPhone,
                gyroPhone: frame.gyroPhone,
                monotonicUs: frame.truth.monotonicUs,
              ) !=
              null) {
            emitted++;
          }
        }
      }
      // 50 Hz of samples must not produce 50 Hz of snapshots.
      expect(emitted, lessThan(frames / 3));
    });

    test('sensor statistics report measured rates, not nominal ones', () {
      final result = run(calibrationDrive());
      final stats =
          result.engine.snapshot!.sensorStats[SensorType.accelerometer]!;
      expect(stats.available, isTrue);
      expect(stats.effectiveHz, isNotNull);
      expect(stats.effectiveHz!, closeTo(50, 1));
    });

    test('fusion contribution is populated and sums to one while locked', () {
      final s = run(calibrationDrive()).engine.snapshot!;
      final c = s.contribution;
      expect(c.isEmpty, isFalse);
      expect(c.gnss + c.inertial + c.ai + c.map, closeTo(1.0, 1e-9));
      expect(c.gnss, greaterThan(0));
      expect(c.inertial, greaterThan(0));
    });

    test('reset returns the engine to its start state', () {
      final result = run(calibrationDrive());
      result.engine.reset();
      expect(result.engine.snapshot, isNull);
      expect(result.engine.mode, NavMode.boot);
      expect(result.engine.alignment, isNull);
      expect(result.engine.transitions, isEmpty);
    });
  });
}

/// Small helper so tests can build a fix without repeating every field.
class GnssObservationFactory {
  static GnssObservation at({
    required double lat,
    required double lon,
    required int us,
    double accuracy = 5,
  }) =>
      GnssObservation(
        latitudeDeg: lat,
        longitudeDeg: lon,
        accuracyM: accuracy,
        monotonicUs: us,
      );
}
