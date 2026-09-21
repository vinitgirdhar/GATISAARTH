import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/ekf/navigation_filter.dart';
import 'package:gatisaarth/core/nav/math/matrix.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

const double _lat0 = 28.6139;
const double _lon0 = 77.2090;

NavigationFilter _seeded({double? velocitySigma, double positionSigma = 5}) {
  final f = NavigationFilter();
  f.initialise(
    latitudeDeg: _lat0,
    longitudeDeg: _lon0,
    altitudeM: 216,
    positionSigma: positionSigma,
    velocitySigma: velocitySigma,
  );
  return f;
}

Vector3 get _rest => Vector3(0, 0, -NavMath.gravity);

void _predict(NavigationFilter f, int steps,
    {Vector3? accel, double dt = 0.02, double scale = 1.0}) {
  for (var i = 0; i < steps; i++) {
    f.predict(
      accelBody: accel ?? _rest,
      gyroBody: Vector3.zero(),
      dt: dt,
      processNoiseScale: scale,
    );
  }
}

void main() {
  group('process noise scaling (Q)', () {
    test('a scale of 1 is the same filter as before, bit for bit', () {
      final a = _seeded();
      final b = _seeded();
      for (var i = 0; i < 500; i++) {
        a.predict(accelBody: _rest, gyroBody: Vector3.zero(), dt: 0.02);
        b.predict(
          accelBody: _rest,
          gyroBody: Vector3.zero(),
          dt: 0.02,
          processNoiseScale: 1.0,
        );
      }
      final pa = a.covariance;
      final pb = b.covariance;
      for (var r = 0; r < ErrorState.size; r++) {
        for (var c = 0; c < ErrorState.size; c++) {
          expect(pb.at(r, c), pa.at(r, c));
        }
      }
    });

    test('one step adds exactly scale x the nominal process noise', () {
      // P(s) = F P0 F' + s Q, so the difference between two scales is
      // (s2 - s1) Q and Q can be read straight off the covariance.
      Matrix covarianceAfterOneStep(double scale) {
        final f = _seeded(velocitySigma: 0.5);
        _predict(f, 1, scale: scale);
        return f.covariance;
      }

      final one = covarianceAfterOneStep(1);
      final two = covarianceAfterOneStep(2);
      final five = covarianceAfterOneStep(5);
      const dt = 0.02;
      const ekf = EkfConfig();
      final expectedQ = <int, double>{
        for (var i = 0; i < 3; i++) ...{
          ErrorState.positionN + i:
              ekf.accelNoiseDensity * ekf.accelNoiseDensity * dt * dt * dt / 3,
          ErrorState.velocityN + i:
              ekf.accelNoiseDensity * ekf.accelNoiseDensity * dt,
          ErrorState.attitudeN + i:
              ekf.gyroNoiseDensity * ekf.gyroNoiseDensity * dt,
          ErrorState.accelBiasN + i:
              ekf.accelBiasRandomWalk * ekf.accelBiasRandomWalk * dt,
          ErrorState.gyroBiasN + i:
              ekf.gyroBiasRandomWalk * ekf.gyroBiasRandomWalk * dt,
        },
      };
      for (final entry in expectedQ.entries) {
        final q = entry.value;
        expect(two.at(entry.key, entry.key) - one.at(entry.key, entry.key),
            closeTo(q, q * 1e-6),
            reason: 'state ${entry.key}');
        expect(five.at(entry.key, entry.key) - one.at(entry.key, entry.key),
            closeTo(4 * q, 4 * q * 1e-6),
            reason: 'state ${entry.key}');
      }
    });

    test('a scale inflates position uncertainty too, so a noisy stretch is '
        'reported as one', () {
      double positionSigma(double scale) {
        final f = _seeded();
        _predict(f, 1000, scale: scale);
        return f.horizontalPositionSigma!;
      }

      expect(positionSigma(6), greaterThan(positionSigma(1)));
    });

    test('a non-positive or non-finite scale is ignored, never a way to break '
        'the covariance', () {
      for (final bad in [0.0, -3.0, double.nan, double.infinity]) {
        final f = _seeded();
        _predict(f, 200, scale: bad);
        expect(f.hasFailed, isFalse, reason: 'scale $bad');
        expect(f.covariance.isFinite, isTrue, reason: 'scale $bad');
        final reference = _seeded();
        _predict(reference, 200);
        expect(f.speedSigma, reference.speedSigma, reason: 'scale $bad');
      }
    });
  });

  group('forward speed as the filter sees it', () {
    test('forwardSpeed is the body-frame forward velocity', () {
      final f = _seeded();
      _predict(f, 250, accel: Vector3(2, 0, -NavMath.gravity)); // 5 s at 2 m/s^2
      expect(f.forwardSpeed, closeTo(10, 0.05));
      expect(_seeded().forwardSpeed, closeTo(0, 1e-12));
      expect(NavigationFilter().forwardSpeed, isNull);
    });

    test('forwardSpeedVariance is H P H^T for the forward axis', () {
      final f = _seeded(velocitySigma: 0.5);
      _predict(f, 250, accel: Vector3(2, 0, -NavMath.gravity));
      // Heading north, moving north: the forward axis is the nav north axis, and
      // the attitude does not couple into it, so the variance is P[vN, vN].
      final p = f.covariance;
      expect(f.forwardSpeedVariance,
          closeTo(p.at(ErrorState.velocityN, ErrorState.velocityN), 1e-9));
      expect(NavigationFilter().forwardSpeedVariance, isNull);
    });

    test('forwardSpeedVariance drops when a forward measurement is folded in',
        () {
      final f = _seeded(velocitySigma: 1.0);
      final before = f.forwardSpeedVariance!;
      final r = f.updateForwardSpeed(speedMps: 0, sigma: 0.3);
      expect(r.accepted, isTrue);
      expect(f.forwardSpeedVariance!, lessThan(before / 3));
    });
  });

  group('pre-gated forward-speed updates', () {
    test('the filter\'s own chi-square gate refuses a 3.5-sigma innovation; a '
        'caller that has done its own gating can still apply it', () {
      MeasurementResult push({required bool preGated}) {
        final f = _seeded(velocitySigma: 1.0);
        final s = math.sqrt(f.forwardSpeedVariance! + 0.5 * 0.5);
        return f.updateForwardSpeed(
          speedMps: 3.5 * s,
          sigma: 0.5,
          preGated: preGated,
        );
      }

      expect(push(preGated: false).outcome, MeasurementOutcome.rejectedByGate);
      final applied = push(preGated: true);
      expect(applied.accepted, isTrue);
      // The NIS is still reported honestly.
      expect(applied.nis, closeTo(3.5 * 3.5, 0.1));
    });

    test('a pre-gated update pulls the speed towards the measurement by the '
        'Kalman gain', () {
      final f = _seeded(velocitySigma: 1.0);
      final p = f.forwardSpeedVariance!;
      const sigma = 0.5;
      f.updateForwardSpeed(speedMps: 2.0, sigma: sigma, preGated: true);
      final gain = p / (p + sigma * sigma);
      expect(f.forwardSpeed, closeTo(gain * 2.0, 0.02));
    });

    test('a refused measurement feeds the reject streak that inflates the '
        'covariance: why a biased model must be stopped before the filter', () {
      final refused = _seeded(velocitySigma: 0.2);
      final untouched = _seeded(velocitySigma: 0.2);
      for (var i = 0; i < 43; i++) {
        refused.updateForwardSpeed(speedMps: 25, sigma: 0.4);
      }
      // Never applied, and yet the filter has widened its velocity covariance
      // on every eighth refusal. Left to itself the filter would let a wrong
      // model make it less certain and eventually give in to it.
      expect(refused.correctionCount, 0);
      expect(refused.rejectStreakFor('forward_speed'), 3);
      expect(refused.forwardSpeedVariance!,
          greaterThan(untouched.forwardSpeedVariance! * 100));
    });

    test('a pre-gated update never feeds a streak: the caller has already '
        'decided, so the contract is that it must have gated first', () {
      final f = _seeded(velocitySigma: 0.2);
      for (var i = 0; i < 40; i++) {
        final r = f.updateForwardSpeed(
          speedMps: 25,
          sigma: 0.4,
          preGated: true,
          name: 'ai_speed',
        );
        expect(r.accepted, isTrue);
      }
      expect(f.rejectStreakFor('ai_speed'), 0);
      expect(f.correctionCount, 40);
    });

    test('the default is unchanged: no argument means the gate is on', () {
      final f = _seeded(velocitySigma: 0.2);
      final result = f.updateForwardSpeed(speedMps: 30, sigma: 0.3);
      expect(result.outcome, MeasurementOutcome.rejectedByGate);
      expect(f.correctionCount, 0);
    });
  });

  test('the configured defaults did not move', () {
    // The AI path is behind a flag; the constants every existing result rests
    // on must be exactly what they were.
    const ekf = EkfConfig();
    expect(ekf.accelNoiseDensity, 0.08);
    expect(ekf.zuptVelocitySigma, 0.02);
    expect(ekf.nhcSigmaCar, 0.15);
    expect(NavConfig.defaults.ai.enabled, isFalse);
  });
}
