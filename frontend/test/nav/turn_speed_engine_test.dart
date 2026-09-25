import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_benchmark.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_report.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';

import 'support/ai_injection.dart';
import 'support/drive_simulator.dart';
import 'support/engine_drive.dart';
import 'support/reference_drive.dart';

/// A winding road: the turns are where v = a_lat / omega can see the speed.
const _winding = <DriveSegment>[
  DriveSegment(seconds: 6, yawRate: 0.22),
  DriveSegment(seconds: 3),
  DriveSegment(seconds: 6, yawRate: -0.22),
  DriveSegment(seconds: 3),
];

({double errorM, int applied, int appliedWhileGnss}) _run({
  required bool turnSpeed,
  int seed = 7,
}) {
  final engine = NavigationEngine(
    config: NavConfig(features: FeatureFlags(turnSpeed: turnSpeed)),
  );
  final sim = DriveSimulator(mount: PhoneMount.tilted(), seed: seed);
  final d = EngineDrive(engine, sim);

  d.drive(calibrationDrive());
  d.drive(const [DriveSegment(seconds: 8, longitudinalAccel: 1.2)]);
  // Turns while GNSS is live: the turn speed is graded, never applied.
  for (var i = 0; i < 3; i++) {
    d.drive(_winding);
  }
  final appliedWhileGnss = engine.turnSpeedDiagnostics.applied;

  // A long quiet outage on a winding road at constant speed: the accelerometer
  // bias alone would drag the along-track speed away.
  d.loseGnss();
  for (var i = 0; i < 5; i++) {
    d.drive(_winding);
  }
  return (
    errorM: d.errorM(),
    applied: engine.turnSpeedDiagnostics.applied,
    appliedWhileGnss: appliedWhileGnss,
  );
}

void main() {
  test('turn speed is never applied while GNSS is healthy', () {
    final r = _run(turnSpeed: true);
    expect(r.appliedWhileGnss, 0);
  });

  test('turn speed is graded against GNSS before the outage', () {
    final engine = NavigationEngine(
      config: const NavConfig(features: FeatureFlags(turnSpeed: true)),
    );
    final d = EngineDrive(
        engine, DriveSimulator(mount: PhoneMount.tilted(), seed: 3));
    d.drive(calibrationDrive());
    d.drive(const [DriveSegment(seconds: 8, longitudinalAccel: 1.2)]);
    for (var i = 0; i < 3; i++) {
      d.drive(_winding);
    }
    final diag = engine.turnSpeedDiagnostics;
    expect(diag.validationPairs, greaterThan(3));
    expect(diag.trusted, isTrue);
    expect(diag.validationBiasMps!.abs(), lessThan(1.0));
  });

  test('switched off, it does nothing at all', () {
    final r = _run(turnSpeed: false);
    expect(r.applied, 0);
  });

  test('it is offered to the filter in an outage on a winding road', () {
    final r = _run(turnSpeed: true);
    expect(r.applied, greaterThan(10));
  });

  group('quiet winding cruise, outage benchmark (SIMULATED)', () {
    // The failure the turn speed exists for, found first on a real winding
    // route: at constant speed on a quiet IMU the along-track speed slides on
    // the unobservable tilt/bias error. Here the road keeps turning, so the
    // turn speedometer has something to measure. Same method as the AI
    // replay evidence: many withheld-GNSS windows, median error.
    const bench = OutageBenchmarkConfig(
        durationsS: [60, 90, 120], strideS: 60, maxStarts: 5);
    final log = simulateDriveLogWithAi(
      setup: referenceSetupDrive(),
      segments: [
        const DriveSegment(seconds: 8, longitudinalAccel: 1.6),
        for (var i = 0; i < 30; i++) ...const [
          DriveSegment(seconds: 7),
          DriveSegment(seconds: 5, yawRate: 0.2),
          DriveSegment(seconds: 7),
          DriveSegment(seconds: 5, yawRate: -0.2),
        ],
      ],
      accelNoise: 0.01,
      inject: false,
    );

    late OutageReport off;
    late OutageReport on;
    setUpAll(() {
      off = OutageBenchmark.run(log, config: bench);
      on = OutageBenchmark.run(log,
          config: bench,
          engineConfig:
              const NavConfig(features: FeatureFlags(turnSpeed: true)));
      // ignore: avoid_print
      print('SIMULATED quiet winding cruise, median error m (p95):');
      for (final d in bench.durationsS) {
        final a = off.forDuration(d)!.engine, b = on.forDuration(d)!.engine;
        // ignore: avoid_print
        print('  ${d}s  off ${a.medianM.toStringAsFixed(1)} '
            '(${a.p95M.toStringAsFixed(0)})   turn speed on '
            '${b.medianM.toStringAsFixed(1)} (${b.p95M.toStringAsFixed(0)})');
      }
    });

    // The simulator's constant bias is estimated before the outage, so the
    // baseline here is already near-perfect (a few metres at 60 s) and the
    // turn speed has nothing to fix. What this pins is the safety property:
    // with a good baseline the extra, noisier speed source costs at most a
    // little. Whether it *helps* is a real-data question, answered by
    // iovnbd_turn_speed_ab_test.dart, never by this simulation.
    test('it does no real harm where the baseline is already good', () {
      for (final d in bench.durationsS) {
        final a = off.forDuration(d)!.engine.medianM;
        expect(on.forDuration(d)!.engine.medianM, lessThan(a * 1.25 + 2),
            reason: '${d}s');
      }
    });
  });
}
