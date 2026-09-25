import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/model/outage_recovery.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';

import 'support/drive_simulator.dart';
import 'support/engine_drive.dart';

EngineDrive _cruising({int seed = 5}) {
  final d = EngineDrive(
    NavigationEngine(),
    DriveSimulator(mount: PhoneMount.tilted(), seed: seed),
  );
  d.drive(calibrationDrive());
  d.drive(const [
    DriveSegment(seconds: 8, longitudinalAccel: 1.2),
    DriveSegment(seconds: 10),
  ]);
  return d;
}

void main() {
  test('no recovery is reported while GNSS never dropped', () {
    final d = _cruising();
    expect(d.engine.snapshot?.lastRecovery, isNull);
  });

  test('a returning fix scores the outage it ends', () {
    final d = _cruising();
    final distanceAtLoss = d.sim.truth.distanceM;
    final lastFixUs = d.sim.truth.monotonicUs;
    d.loseGnss();
    d.drive(const [
      DriveSegment(seconds: 12),
      DriveSegment(seconds: 6, yawRate: 0.1),
      DriveSegment(seconds: 12),
    ]);

    // What the core believes just before the fix comes back.
    final before = d.engine.filter.state!;
    d.restoreGnss();
    final fix = d.sim.gnss();
    d.engine.onGnss(fix);

    final r = d.engine.snapshot!.lastRecovery;
    expect(r, isNotNull);
    final expectedError = NavMath.horizontalDistance(
      lat0: before.latitudeDeg,
      lon0: before.longitudeDeg,
      lat1: fix.latitudeDeg,
      lon1: fix.longitudeDeg,
    );
    expect(r!.errorM, closeTo(expectedError, 1e-6));
    expect(r.durationS, closeTo((fix.monotonicUs - lastFixUs) / 1e6, 1.1));
    final truthDistance = d.sim.truth.distanceM - distanceAtLoss;
    expect(r.distanceM, closeTo(truthDistance, truthDistance * 0.15));
    expect(r.driftPct, closeTo(100 * r.errorM / r.distanceM, 1e-9));
    expect(r.fixAccuracyM, fix.accuracyM);
    expect(r.endedAtUs, fix.monotonicUs);
    expect(r.coreLed, isTrue);
  });

  test('a blip shorter than the reporting threshold is not an outage', () {
    final d = _cruising();
    d.loseGnss();
    d.drive(const [DriveSegment(seconds: 3)]);
    d.restoreGnss();
    d.drive(const [DriveSegment(seconds: 2)]);
    expect(d.engine.snapshot?.lastRecovery, isNull);
  });

  test('the recovery survives until the next outage replaces it', () {
    final d = _cruising();
    d.loseGnss();
    d.drive(const [DriveSegment(seconds: 20)]);
    d.restoreGnss();
    d.drive(const [DriveSegment(seconds: 15)]);
    final first = d.engine.snapshot!.lastRecovery!;

    d.loseGnss();
    d.drive(const [DriveSegment(seconds: 30)]);
    d.restoreGnss();
    d.drive(const [DriveSegment(seconds: 2)]);
    final second = d.engine.snapshot!.lastRecovery!;
    expect(second.endedAtUs, greaterThan(first.endedAtUs));
    expect(second.durationS, greaterThan(first.durationS));
  });

  test('reset forgets the last recovery', () {
    final d = _cruising();
    d.loseGnss();
    d.drive(const [DriveSegment(seconds: 20)]);
    d.restoreGnss();
    d.drive(const [DriveSegment(seconds: 2)]);
    expect(d.engine.snapshot!.lastRecovery, isNotNull);
    d.engine.reset();
    d.drive(const [DriveSegment(seconds: 1)]);
    expect(d.engine.snapshot?.lastRecovery, isNull);
  });

  group('OutageRecovery', () {
    const r = OutageRecovery(
      durationS: 42,
      distanceM: 610,
      errorM: 18.3,
      fixAccuracyM: 5,
      endedAtUs: 100000000,
      coreLed: true,
    );

    test('drift is error over distance', () {
      expect(r.driftPct, closeTo(3.0, 0.01));
      expect(r.meetsTarget(10), isTrue);
      expect(r.meetsTarget(2), isFalse);
    });

    test('is recent only inside the window', () {
      expect(
          r.isRecent(
              nowUs: 100000000 + 29000000, window: const Duration(seconds: 30)),
          isTrue);
      expect(
          r.isRecent(
              nowUs: 100000000 + 31000000, window: const Duration(seconds: 30)),
          isFalse);
    });
  });
}
