import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/motion/turn_speed.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

/// Feeds [seconds] of a steady turn at 50 Hz into [estimator] and returns the
/// last observation it produced.
TurnSpeedObservation? _turn(
  TurnSpeedEstimator estimator, {
  required double speed,
  required double yawRate,
  double seconds = 2,
  int startUs = 0,
  double lateralOffset = 0,
  double Function(int i)? yawJitter,
}) {
  TurnSpeedObservation? last;
  final n = (seconds * 50).round();
  for (var i = 0; i < n; i++) {
    final us = startUs + i * 20000;
    final w = yawRate + (yawJitter?.call(i) ?? 0);
    estimator.add(
      lateralAccel: speed * yawRate + lateralOffset,
      yawRate: w,
      monotonicUs: us,
    );
    last = estimator.poll(us) ?? last;
  }
  return last;
}

void main() {
  group('coordinated-turn speed (v = a_lat / yaw rate)', () {
    test('recovers the speed of a steady right turn', () {
      final e = TurnSpeedEstimator();
      final obs = _turn(e, speed: 12, yawRate: 0.3);
      expect(obs, isNotNull);
      expect(obs!.speedMps, closeTo(12, 0.05));
      expect(obs.sigmaMps, greaterThan(0));
      expect(obs.sigmaMps, lessThan(2));
    });

    test('a left turn gives the same positive speed', () {
      final obs = _turn(TurnSpeedEstimator(), speed: 12, yawRate: -0.3);
      expect(obs!.speedMps, closeTo(12, 0.05));
    });

    test('says nothing on a straight road, where the ratio is meaningless', () {
      final obs = _turn(TurnSpeedEstimator(), speed: 15, yawRate: 0.01);
      expect(obs, isNull);
    });

    test('refuses a lateral force on the wrong side of the turn', () {
      // A sideways force pointing out of the turn is a sensor or frame
      // problem, not a speed.
      final obs = _turn(TurnSpeedEstimator(),
          speed: 10, yawRate: 0.3, lateralOffset: -6);
      expect(obs, isNull);
    });

    test('refuses an unsteady yaw rate (not a coordinated turn)', () {
      final obs = _turn(TurnSpeedEstimator(),
          speed: 10, yawRate: 0.2, yawJitter: (i) => i.isEven ? 0.25 : -0.25);
      expect(obs, isNull);
    });

    test('a tighter turn is a more precise witness', () {
      final gentle = _turn(TurnSpeedEstimator(), speed: 10, yawRate: 0.15);
      final tight = _turn(TurnSpeedEstimator(), speed: 10, yawRate: 0.5);
      expect(tight!.sigmaMps, lessThan(gentle!.sigmaMps));
    });

    test('speaks at most once per update interval', () {
      final e = TurnSpeedEstimator();
      var count = 0;
      for (var i = 0; i < 250; i++) {
        final us = i * 20000;
        e.add(lateralAccel: 3.6, yawRate: 0.3, monotonicUs: us);
        if (e.poll(us) != null) count++;
      }
      // 5 s of turning, one observation per second after the first window.
      final interval = NavConfig.defaults.turnSpeed.updateInterval;
      expect(count,
          lessThanOrEqualTo((5 / (interval.inMilliseconds / 1000)).ceil()));
      expect(count, greaterThanOrEqualTo(3));
    });
  });

  group('validation against GNSS', () {
    test('agreeing turns keep it trusted', () {
      final e = TurnSpeedEstimator();
      for (var k = 0; k < 8; k++) {
        final obs = _turn(e, speed: 12, yawRate: 0.3, startUs: k * 3000000);
        e.grade(obs!, gnssSpeedMps: 12.2);
      }
      expect(e.trusted, isTrue);
      expect(e.diagnostics.validationPairs, 8);
    });

    test('a consistent disagreement with GNSS switches it off', () {
      final e = TurnSpeedEstimator();
      for (var k = 0; k < 8; k++) {
        final obs = _turn(e, speed: 12, yawRate: 0.3, startUs: k * 3000000);
        e.grade(obs!, gnssSpeedMps: 18);
      }
      expect(e.trusted, isFalse);
    });

    test('a few pairs are not enough evidence to condemn it', () {
      final e = TurnSpeedEstimator();
      final obs = _turn(e, speed: 12, yawRate: 0.3);
      e.grade(obs!, gnssSpeedMps: 25);
      expect(e.trusted, isTrue);
    });
  });

  group('level frame', () {
    test('a leaning two-wheeler still shows its centripetal force', () {
      // In a coordinated turn a bike leans so the resultant force lies along
      // its own vertical axis: the body-frame lateral reading is ~0. Only the
      // levelled frame, via the filter attitude, recovers v * omega.
      const v = 10.0, w = 0.35;
      final lean = math.atan(v * w / NavMath.gravity);
      // Level-frame specific force (FRD): centripetal to the right, gravity up.
      final fLevel = Vector3(0, v * w, -NavMath.gravity);
      final q = NavMath.quaternionFromEuler(roll: lean, pitch: 0, yaw: 0.7);
      final qYaw = NavMath.quaternionFromEuler(roll: 0, pitch: 0, yaw: 0.7);
      final fNav = NavMath.rotateBodyToNav(qYaw, fLevel);
      final fBody = NavMath.rotateNavToBody(q, fNav);
      final omegaNav = Vector3(0, 0, w);
      final omegaBody = NavMath.rotateNavToBody(q, omegaNav);

      expect(fBody.y.abs(), lessThan(0.05), reason: 'body sees no side force');
      final level = TurnSpeedEstimator.levelFrame(
        qBodyToNav: q,
        specificForceBody: fBody,
        angularRateBody: omegaBody,
      );
      expect(level.lateralAccel, closeTo(v * w, 1e-6));
      expect(level.yawRate, closeTo(w, 1e-9));
    });
  });
}
