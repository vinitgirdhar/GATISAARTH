import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/ekf/navigation_filter.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

const double lat0 = 28.6139;
const double lon0 = 77.2090;

/// Specific force a level, stationary vehicle-frame IMU reports: x forward,
/// y right, z down, so gravity shows up as -g on the down axis.
Vector3 levelGravity() => Vector3(0, 0, -NavMath.gravity);

NavigationFilter seeded({
  NavConfig? config,
  double headingRad = 0,
  double positionSigma = 5,
}) {
  final f = NavigationFilter(config: config ?? NavConfig.defaults);
  f.initialise(
    latitudeDeg: lat0,
    longitudeDeg: lon0,
    altitudeM: 216,
    headingRad: headingRad,
    positionSigma: positionSigma,
  );
  return f;
}

void run(
  NavigationFilter f, {
  required double seconds,
  required Vector3 accel,
  required Vector3 gyro,
  double dt = 0.01,
  void Function(NavigationFilter f, double t)? each,
}) {
  final steps = (seconds / dt).round();
  for (var i = 0; i < steps; i++) {
    f.predict(accelBody: accel, gyroBody: gyro, dt: dt);
    each?.call(f, i * dt);
  }
}

void main() {
  group('initialisation', () {
    test('an uninitialised filter reports null, never a placeholder', () {
      final f = NavigationFilter();
      expect(f.state, isNull);
      expect(f.isInitialised, isFalse);
      expect(f.horizontalPositionSigma, isNull);
      expect(f.speedSigma, isNull);
      expect(f.headingSigmaDeg, isNull);
    });

    test('seeding sets position and an honest initial uncertainty', () {
      final f = seeded(positionSigma: 7);
      expect(f.state!.latitudeDeg, closeTo(lat0, 1e-12));
      expect(f.horizontalPositionSigma, closeTo(7, 1e-9));
      expect(f.state!.groundSpeed, closeTo(0, 1e-12));
      // Yaw is not observable at rest, so it starts far wider than roll/pitch.
      expect(f.headingSigmaDeg!, greaterThan(45));
    });

    test('gravity seeds roll and pitch', () {
      final f = NavigationFilter();
      // Vehicle nose pitched 10 degrees up: gravity leaks onto the forward axis.
      const pitch = 10 * NavMath.degToRad;
      f.initialise(
        latitudeDeg: lat0,
        longitudeDeg: lon0,
        gravityBody: Vector3(
          math.sin(pitch) * NavMath.gravity,
          0,
          -math.cos(pitch) * NavMath.gravity,
        ),
      );
      final euler = NavMath.eulerFromQuaternion(f.state!.qBodyToNav);
      expect(euler[1] * NavMath.radToDeg, closeTo(10, 0.01));
    });
  });

  group('strapdown mechanization', () {
    test('a level stationary vehicle does not move', () {
      final f = seeded();
      run(f, seconds: 60, accel: levelGravity(), gyro: Vector3.zero());
      expect(f.state!.groundSpeed, closeTo(0, 1e-9));
      expect(
        NavMath.horizontalDistance(
          lat0: lat0,
          lon0: lon0,
          lat1: f.state!.latitudeDeg,
          lon1: f.state!.longitudeDeg,
        ),
        lessThan(0.001),
      );
    });

    test('constant forward acceleration integrates to the right speed and '
        'distance', () {
      final f = seeded();
      // 2 m/s² forward for 10 s => 20 m/s, 100 m travelled.
      run(
        f,
        seconds: 10,
        accel: Vector3(2, 0, -NavMath.gravity),
        gyro: Vector3.zero(),
      );
      expect(f.state!.groundSpeed, closeTo(20, 0.01));
      expect(
        NavMath.horizontalDistance(
          lat0: lat0,
          lon0: lon0,
          lat1: f.state!.latitudeDeg,
          lon1: f.state!.longitudeDeg,
        ),
        closeTo(100, 0.05),
      );
      // Travelling due north.
      expect(f.state!.headingDeg, closeTo(0, 0.01));
    });

    test('a constant yaw rate turns the heading, not the speed', () {
      final f = seeded();
      run(
        f,
        seconds: 2,
        accel: Vector3(1, 0, -NavMath.gravity),
        gyro: Vector3(0, 0, 0.5),
      );
      // Attitude has turned 1 rad = 57.3 degrees.
      expect(
        NavMath.headingFromQuaternion(f.state!.qBodyToNav) * NavMath.radToDeg,
        closeTo(57.3, 0.2),
      );
      // Speed is NOT 2 m/s: the acceleration vector rotates with the vehicle,
      // so the velocity integral follows a curve. |v| = |int (cos.5t, sin.5t) dt|
      // over 0..2 = sqrt((2sin1)^2 + (2-2cos1)^2) = 1.918.
      expect(f.state!.groundSpeed, closeTo(1.918, 0.01));
    });

    test('an uncorrected accelerometer bias drifts quadratically — this is '
        'the error dead reckoning has to fight', () {
      final f = seeded();
      // 0.05 m/s² of bias for 60 s => 0.5*a*t² = 90 m of position error.
      run(
        f,
        seconds: 60,
        accel: Vector3(0.05, 0, -NavMath.gravity),
        gyro: Vector3.zero(),
      );
      final drift = NavMath.horizontalDistance(
        lat0: lat0,
        lon0: lon0,
        lat1: f.state!.latitudeDeg,
        lon1: f.state!.longitudeDeg,
      );
      expect(drift, closeTo(90, 1));
    });

    test('an implausible dt is refused rather than integrated', () {
      final f = seeded();
      expect(
        f.predict(accelBody: levelGravity(), gyroBody: Vector3.zero(), dt: 5),
        isFalse,
      );
      expect(
        f.predict(accelBody: levelGravity(), gyroBody: Vector3.zero(), dt: 0),
        isFalse,
      );
      expect(
        f.predict(
            accelBody: levelGravity(),
            gyroBody: Vector3.zero(),
            dt: double.nan),
        isFalse,
      );
      expect(f.predictionCount, 0);
      expect(f.hasFailed, isFalse);
    });

    test('a NaN or absurd sample is refused and does not poison the state', () {
      final f = seeded();
      run(f, seconds: 1, accel: levelGravity(), gyro: Vector3.zero());
      final before = f.state!.groundSpeed;

      expect(
        f.predict(
          accelBody: Vector3(double.nan, 0, -9.8),
          gyroBody: Vector3.zero(),
          dt: 0.01,
        ),
        isFalse,
      );
      // 500 m/s² is not a vehicle manoeuvre, it is a sensor fault.
      expect(
        f.predict(
          accelBody: Vector3(500, 0, -9.8),
          gyroBody: Vector3.zero(),
          dt: 0.01,
        ),
        isFalse,
      );
      expect(f.state!.groundSpeed, closeTo(before, 1e-12));
      expect(f.state!.isFinite, isTrue);
      expect(f.hasFailed, isFalse);
    });

    test('the quaternion stays unit over a long run', () {
      final f = seeded();
      run(
        f,
        seconds: 100,
        accel: Vector3(0.4, 0.2, -NavMath.gravity),
        gyro: Vector3(0.05, -0.03, 0.2),
      );
      expect(f.state!.qBodyToNav.length, closeTo(1.0, 1e-9));
    });
  });

  group('covariance', () {
    test('stays symmetric with a positive diagonal over 10000 steps', () {
      final f = seeded();
      run(
        f,
        seconds: 100,
        accel: Vector3(0.3, 0, -NavMath.gravity),
        gyro: Vector3(0, 0, 0.05),
      );
      final p = f.covariance;
      expect(p.isFinite, isTrue);
      expect(p.isSymmetricPositiveDiagonal(tolerance: 1e-6), isTrue);
    });

    test('grows monotonically while nothing is measured', () {
      final f = seeded();
      var last = f.horizontalPositionSigma!;
      for (var i = 0; i < 500; i++) {
        f.predict(
          accelBody: levelGravity(),
          gyroBody: Vector3.zero(),
          dt: 0.02,
        );
        final now = f.horizontalPositionSigma!;
        expect(now, greaterThanOrEqualTo(last - 1e-9));
        last = now;
      }
      expect(last, greaterThan(f.config.ekf.initialPositionSigma * 0 + 5));
    });

    test('a GNSS fix shrinks position uncertainty', () {
      final f = seeded(positionSigma: 40);
      final before = f.horizontalPositionSigma!;
      final result = f.updatePosition(
        latitudeDeg: lat0,
        longitudeDeg: lon0,
        horizontalSigma: 4,
      );
      expect(result.accepted, isTrue);
      final after = f.horizontalPositionSigma!;
      expect(after, lessThan(before));
      // Two independent estimates combine: 1/s² = 1/40² + 1/4².
      expect(after, closeTo(1 / math.sqrt(1 / 1600 + 1 / 16), 0.1));
    });

    test('repeated good fixes drive uncertainty down towards the fix accuracy',
        () {
      final f = seeded(positionSigma: 50);
      for (var i = 0; i < 30; i++) {
        f.predict(
            accelBody: levelGravity(), gyroBody: Vector3.zero(), dt: 0.05);
        f.updatePosition(
          latitudeDeg: lat0,
          longitudeDeg: lon0,
          horizontalSigma: 5,
        );
      }
      expect(f.horizontalPositionSigma!, lessThan(5));
    });
  });

  group('measurement gating', () {
    test('a 10-sigma jump is rejected instead of teleporting the marker', () {
      final f = seeded(positionSigma: 5);
      final before = f.state!;

      // 500 m away while claiming 5 m accuracy: physically impossible.
      final jumped = NavMath.addNed(
        latDeg: lat0,
        lonDeg: lon0,
        altM: 216,
        north: 500,
        east: 0,
        down: 0,
      );
      final result = f.updatePosition(
        latitudeDeg: jumped[0],
        longitudeDeg: jumped[1],
        horizontalSigma: 5,
      );

      expect(result.outcome, MeasurementOutcome.rejectedByGate);
      expect(result.nis!, greaterThan(result.gateLimit!));
      expect(f.state!.latitudeDeg, closeTo(before.latitudeDeg, 1e-12));
      expect(f.state!.longitudeDeg, closeTo(before.longitudeDeg, 1e-12));
      expect(f.correctionCount, 0);
    });

    test('a plausible fix inside the gate is accepted and moves the state', () {
      final f = seeded(positionSigma: 20);
      final nearby = NavMath.addNed(
        latDeg: lat0,
        lonDeg: lon0,
        altM: 216,
        north: 12,
        east: -5,
        down: 0,
      );
      final result = f.updatePosition(
        latitudeDeg: nearby[0],
        longitudeDeg: nearby[1],
        horizontalSigma: 8,
      );
      expect(result.accepted, isTrue);
      final moved = NavMath.nedBetween(
        lat0: lat0,
        lon0: lon0,
        alt0: 216,
        lat1: f.state!.latitudeDeg,
        lon1: f.state!.longitudeDeg,
        alt1: f.state!.altitudeM,
      );
      // Weighted towards the measurement but not all the way onto it.
      expect(moved.x, greaterThan(5));
      expect(moved.x, lessThan(12));
    });

    test('a non-finite measurement is skipped, not gated', () {
      final f = seeded();
      final result = f.updatePosition(
        latitudeDeg: double.nan,
        longitudeDeg: lon0,
        horizontalSigma: 5,
      );
      expect(result.outcome, MeasurementOutcome.skipped);
      expect(f.hasFailed, isFalse);
    });

    test('updates on an uninitialised filter are skipped, not crashes', () {
      final f = NavigationFilter();
      expect(f.updateZeroVelocity().outcome, MeasurementOutcome.skipped);
      expect(
        f.updateNonHolonomic(lateralSigma: 0.1).outcome,
        MeasurementOutcome.skipped,
      );
      expect(
        f.updateHeading(measuredHeadingRad: 1).outcome,
        MeasurementOutcome.skipped,
      );
    });
  });

  group('zero velocity and zero angular rate', () {
    test('ZUPT pulls an accumulated phantom velocity back to zero', () {
      final f = seeded();
      // Bias makes the INS believe it is accelerating.
      run(
        f,
        seconds: 5,
        accel: Vector3(0.3, 0, -NavMath.gravity),
        gyro: Vector3.zero(),
      );
      expect(f.state!.groundSpeed, greaterThan(1.0));

      for (var i = 0; i < 20; i++) {
        f.predict(
            accelBody: Vector3(0.3, 0, -NavMath.gravity),
            gyroBody: Vector3.zero(),
            dt: 0.05);
        f.updateZeroVelocity();
      }
      expect(f.state!.groundSpeed, lessThan(0.05));
    });

    test('at rest, ZUPT cancels the specific-force error but CANNOT tell '
        'accelerometer bias from tilt', () {
      final f = seeded();
      const trueBias = 0.3; // m/s^2 forward
      for (var i = 0; i < 2000; i++) {
        f.predict(
          accelBody: Vector3(trueBias, 0, -NavMath.gravity),
          gyroBody: Vector3.zero(),
          dt: 0.02,
        );
        f.updateZeroVelocity();
      }

      // What ZUPT genuinely delivers: no velocity drift at all.
      expect(f.state!.groundSpeed, lessThan(0.001));

      // What it does NOT deliver: the bias itself. A 0.3 m/s^2 forward bias
      // and a 1.75 deg nose-up pitch are the same measurement to a stationary
      // IMU, and the filter picks whichever its covariance says is likelier.
      // Here the attitude prior is far looser, so it lands in pitch.
      final pitchRad = NavMath.eulerFromQuaternion(f.state!.qBodyToNav)[1];
      final explainedByTilt = -NavMath.gravity * math.sin(pitchRad);
      expect(explainedByTilt + f.state!.accelBias.x, closeTo(-trueBias, 0.02));

      // Stated for the avoidance of doubt: this is why §5 calibration needs a
      // guided movement and §6 alignment needs a drive. Separating the two
      // requires changing acceleration.
      expect(f.state!.accelBias.x.abs(), lessThan(trueBias / 2));
    });

    test('ZARU learns the gyro bias so heading stops drifting at a red light',
        () {
      final f = seeded();
      const trueBias = 0.01; // rad/s ~ 0.6 deg/s, typical phone MEMS
      for (var i = 0; i < 1000; i++) {
        f.predict(
          accelBody: levelGravity(),
          gyroBody: Vector3(0, 0, trueBias),
          dt: 0.02,
        );
        f.updateZeroAngularRate(gyroBody: Vector3(0, 0, trueBias));
      }
      expect(f.state!.gyroBias.z, closeTo(trueBias, 0.002));
      expect(
        NavMath.headingFromQuaternion(f.state!.qBodyToNav) * NavMath.radToDeg,
        closeTo(0, 5),
      );
    });
  });

  group('non-holonomic constraint', () {
    test('NHC removes sideways velocity from the body frame', () {
      final f = seeded();
      // Accelerate north-east for 5 s while the vehicle keeps pointing north:
      // part of the velocity ends up sideways, which a car cannot do.
      run(
        f,
        seconds: 5,
        accel: Vector3(2.0, 0.6, -NavMath.gravity),
        gyro: Vector3.zero(),
        dt: 0.02,
      );
      expect(f.state!.velocityBody.y.abs(), greaterThan(1.0));

      for (var i = 0; i < 40; i++) {
        f.predict(
          accelBody: levelGravity(),
          gyroBody: Vector3.zero(),
          dt: 0.02,
        );
        f.updateNonHolonomic(lateralSigma: 0.15);
      }
      expect(f.state!.velocityBody.y.abs(), lessThan(0.1));
    });

    test('NHC alone cannot observe yaw — its residual is already perfectly '
        'correlated with the yaw error', () {
      final f = seeded();
      run(
        f,
        seconds: 8,
        accel: Vector3(2.0, 0, -NavMath.gravity),
        gyro: Vector3.zero(),
        dt: 0.02,
      );
      final before = f.headingSigmaDeg!;
      for (var i = 0; i < 300; i++) {
        f.predict(
          accelBody: levelGravity(),
          gyroBody: Vector3.zero(),
          dt: 0.02,
        );
        final r = f.updateNonHolonomic(lateralSigma: 0.15);
        // Residual is identically zero: a yaw error of dPsi produces exactly
        // V*dPsi of lateral velocity error, so H*P*H' cancels to nothing and
        // the gain is zero. The constraint is satisfied, and satisfying a
        // constraint teaches you nothing.
        expect(r.accepted, isTrue);
      }
      expect(f.headingSigmaDeg!, closeTo(before, 1.5));
    });

    test('NHC plus an independent velocity reference DOES observe yaw', () {
      // Measured, not asserted from theory: with a GNSS velocity that
      // disagrees with the believed heading, NHC is what converts that
      // disagreement into a yaw correction.
      double finalYaw(bool withNhc) {
        final f = seeded(headingRad: 25 * NavMath.degToRad);
        run(
          f,
          seconds: 2,
          accel: Vector3(1.6, 0, -NavMath.gravity),
          gyro: Vector3.zero(),
          dt: 0.02,
        );
        for (var i = 0; i < 400; i++) {
          f.predict(
            accelBody: levelGravity(),
            gyroBody: Vector3.zero(),
            dt: 0.02,
          );
          // Truth: travelling due north at 3.2 m/s.
          f.updateVelocityNed(
            velocityNed: Vector3(3.2, 0, 0),
            sigmas: Vector3(0.3, 0.3, 0.3),
          );
          if (withNhc) f.updateNonHolonomic(lateralSigma: 0.15);
        }
        return NavMath.headingFromQuaternion(f.state!.qBodyToNav) *
            NavMath.radToDeg;
      }

      expect(finalYaw(true).abs(), lessThan(1.0));
      expect(finalYaw(false).abs(), greaterThan(3.0));
    });

    test('a loose two-wheeler sigma constrains less than a tight car one', () {
      double lateralAfter(double sigma) {
        final f = seeded();
        run(
          f,
          seconds: 5,
          accel: Vector3(2.0, 0.6, -NavMath.gravity),
          gyro: Vector3.zero(),
          dt: 0.02,
        );
        f.updateNonHolonomic(lateralSigma: sigma);
        return f.state!.velocityBody.y.abs();
      }

      final car = lateralAfter(NavConfig.defaults.ekf.nhcSigmaCar);
      final bike = lateralAfter(NavConfig.defaults.ekf.nhcSigmaTwoWheeler);
      expect(bike, greaterThan(car));
    });
  });

  group('other measurements', () {
    test('a heading update corrects yaw', () {
      final f = seeded(headingRad: 0);
      final result = f.updateHeading(
        measuredHeadingRad: 45 * NavMath.degToRad,
        sigma: 0.05,
      );
      expect(result.accepted, isTrue);
      expect(
        NavMath.headingFromQuaternion(f.state!.qBodyToNav) * NavMath.radToDeg,
        closeTo(45, 2),
      );
    });

    test('a magnetometer reading corrects yaw in the right direction', () {
      // The filter believes it points north; the field says it points 30° east
      // of that.
      final f = seeded(headingRad: 0);
      final fieldNav = Vector3(22, 0, 43);
      final truth = NavMath.quaternionFromEuler(
        roll: 0,
        pitch: 0,
        yaw: 30 * NavMath.degToRad,
      );
      final magBody = NavMath.rotateNavToBody(truth, fieldNav);

      for (var i = 0; i < 40; i++) {
        f.updateMagnetometer(magBody: magBody, sigma: 0.1);
      }
      expect(
        NavMath.headingFromQuaternion(f.state!.qBodyToNav) * NavMath.radToDeg,
        closeTo(30, 2),
      );
    });

    test('a magnetometer with no horizontal component is skipped, not faked',
        () {
      final f = seeded();
      final result = f.updateMagnetometer(magBody: Vector3(0, 0, 50));
      expect(result.outcome, MeasurementOutcome.skipped);
    });

    test('a barometric altitude update moves altitude towards the reading', () {
      final f = seeded();
      final start = f.state!.altitudeM;
      for (var i = 0; i < 20; i++) {
        f.updateAltitude(altitudeM: start + 10, sigma: 1.5);
      }
      expect(f.state!.altitudeM, closeTo(start + 10, 0.5));
    });

    test('a forward-speed measurement converges ground speed onto it', () {
      final f = seeded();
      // Repeated consistent measurements: each one is a few sigma from the
      // last estimate, so the gate lets the state walk up to 12 m/s.
      for (var i = 0; i < 200; i++) {
        f.predict(
            accelBody: levelGravity(), gyroBody: Vector3.zero(), dt: 0.05);
        f.updateForwardSpeed(speedMps: 12, sigma: 0.5);
      }
      expect(f.state!.groundSpeed, closeTo(12, 0.5));
    });

    test('a GNSS velocity update steers the velocity vector', () {
      final f = seeded();
      // Seed the motion from the IMU, then let GNSS velocity refine it.
      run(
        f,
        seconds: 5,
        accel: Vector3(1.6, -1.2, -NavMath.gravity),
        gyro: Vector3.zero(),
        dt: 0.02,
      );
      for (var i = 0; i < 10; i++) {
        final r = f.updateVelocityNed(
          velocityNed: Vector3(8, -6, 0),
          sigmas: Vector3(0.3, 0.3, 0.3),
        );
        expect(r.outcome, isNot(MeasurementOutcome.skipped));
      }
      expect(f.state!.groundSpeed, closeTo(10, 0.3));
      expect(f.state!.headingDeg, closeTo(NavMath.wrap360(-36.87), 3));
    });

    test('a measurement rejected over and over eventually reopens the gate '
        'instead of locking the filter out forever', () {
      final f = seeded(positionSigma: 3);
      final far = NavMath.addNed(
        latDeg: lat0,
        lonDeg: lon0,
        altM: 216,
        north: 60,
        east: 0,
        down: 0,
      );
      MeasurementResult push() => f.updatePosition(
            latitudeDeg: far[0],
            longitudeDeg: far[1],
            horizontalSigma: 3,
          );

      // The vehicle really did move; the filter is simply overconfident.
      var rejections = 0;
      var accepted = false;
      for (var i = 0; i < 40 && !accepted; i++) {
        final r = push();
        if (r.accepted) {
          accepted = true;
        } else {
          rejections++;
        }
      }
      expect(rejections, greaterThanOrEqualTo(
          NavConfig.defaults.ekf.consecutiveRejectLimit));
      expect(accepted, isTrue,
          reason: 'covariance inflation must let a persistent measurement in');
    });
  });

  group('dead-reckoning behaviour', () {
    test('constraints materially reduce drift during a 60 s outage', () {
      // The vehicle is genuinely stationary in a tunnel car park, but the
      // accelerometer has a 0.2 m/s² bias and the gyro 0.01 rad/s. Open loop
      // this integrates into hundreds of metres.
      final accel = Vector3(0.2, 0, -NavMath.gravity);
      final gyro = Vector3(0, 0, 0.01);

      double drift(NavigationFilter f) => NavMath.horizontalDistance(
            lat0: lat0,
            lon0: lon0,
            lat1: f.state!.latitudeDeg,
            lon1: f.state!.longitudeDeg,
          );

      final openLoop = seeded();
      run(openLoop, seconds: 60, accel: accel, gyro: gyro, dt: 0.02);

      final constrained = seeded();
      for (var i = 0; i < 3000; i++) {
        constrained.predict(accelBody: accel, gyroBody: gyro, dt: 0.02);
        // The vehicle is stopped, and the detector says so.
        constrained.updateZeroVelocity();
        constrained.updateZeroAngularRate(gyroBody: gyro);
      }

      expect(drift(openLoop), greaterThan(100));
      expect(drift(constrained), lessThan(drift(openLoop) / 20));
    });

    test('uncertainty keeps growing during an outage and collapses on '
        'reacquisition', () {
      final f = seeded(positionSigma: 5);
      run(f, seconds: 30, accel: levelGravity(), gyro: Vector3.zero(), dt: 0.02);
      final duringOutage = f.horizontalPositionSigma!;
      expect(duringOutage, greaterThan(5));

      f.updatePosition(
        latitudeDeg: lat0,
        longitudeDeg: lon0,
        horizontalSigma: 6,
      );
      expect(f.horizontalPositionSigma!, lessThan(duringOutage));
    });
  });
}
