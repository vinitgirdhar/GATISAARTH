import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/motion/motion_classifier.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

/// Feeds [seconds] of samples at 50 Hz and returns the final snapshot.
MotionSnapshot feed(
  MotionClassifier c, {
  required double seconds,
  required double noiseAccel,
  double noiseGyro = 0.0,
  double longitudinal = 0,
  double lateral = 0,
  double yawRate = 0,
  double? gnssSpeed,
  double? filterSpeed,
  double? rollRad,
  int startUs = 0,
  int seed = 7,
}) {
  final rng = math.Random(seed);
  final steps = (seconds * 50).round();
  late MotionSnapshot last;
  for (var i = 0; i < steps; i++) {
    double n(double scale) => (rng.nextDouble() - 0.5) * 2 * scale;
    last = c.addSample(
      accelBody: Vector3(
        longitudinal + n(noiseAccel),
        lateral + n(noiseAccel),
        -NavMath.gravity + n(noiseAccel),
      ),
      gyroBody: Vector3(n(noiseGyro), n(noiseGyro), yawRate + n(noiseGyro)),
      monotonicUs: startUs + i * 20000,
      gnssSpeedMps: gnssSpeed,
      filterSpeedMps: filterSpeed,
      rollRad: rollRad,
    );
  }
  return last;
}

void main() {
  group('stationary detection', () {
    test('a genuinely still phone becomes stationary after the enter delay',
        () {
      final c = MotionClassifier();
      final early = c.addSample(
        accelBody: Vector3(0, 0, -NavMath.gravity),
        gyroBody: Vector3.zero(),
        monotonicUs: 0,
      );
      expect(early.isStationary, isFalse,
          reason: 'must not declare a stop on the very first sample');

      final later = feed(c, seconds: 3, noiseAccel: 0.01, noiseGyro: 0.001);
      expect(later.isStationary, isTrue);
      expect(later.state, VehicleState.stationary);
      expect(later.stopDuration.inMilliseconds, greaterThan(1000));
    });

    test('vibration alone breaks the stop', () {
      final c = MotionClassifier();
      feed(c, seconds: 3, noiseAccel: 0.01, noiseGyro: 0.001);
      expect(c.snapshot.isStationary, isTrue);

      final moving = feed(
        c,
        seconds: 3,
        noiseAccel: 1.2,
        noiseGyro: 0.2,
        startUs: 3000000,
      );
      expect(moving.isStationary, isFalse);
    });

    test('live GNSS speed vetoes a stop even when the IMU looks still', () {
      final c = MotionClassifier();
      final s = feed(
        c,
        seconds: 4,
        noiseAccel: 0.01,
        noiseGyro: 0.001,
        gnssSpeed: 18,
      );
      expect(s.isStationary, isFalse);
    });

    test('the filter-speed prior stops a smooth cruise reading as a stop — '
        'the exact failure the old variance-only rule had', () {
      final c = MotionClassifier();
      // Motorway at 25 m/s on good tarmac: the IMU is as quiet as a car park.
      final s = feed(
        c,
        seconds: 5,
        noiseAccel: 0.01,
        noiseGyro: 0.001,
        filterSpeed: 25,
      );
      expect(s.isStationary, isFalse);

      // Same signal with the filter already near a standstill: a real stop.
      final c2 = MotionClassifier();
      final s2 = feed(
        c2,
        seconds: 5,
        noiseAccel: 0.01,
        noiseGyro: 0.001,
        filterSpeed: 0.2,
      );
      expect(s2.isStationary, isTrue);
    });

    test('hysteresis stops moving/stopped chatter on a borderline signal', () {
      final c = MotionClassifier(
        config: const NavConfig(
          motion: MotionConfig(
            zuptEnterDelay: Duration(milliseconds: 600),
            zuptExitDelay: Duration(milliseconds: 250),
          ),
        ),
      );
      feed(c, seconds: 3, noiseAccel: 0.01, noiseGyro: 0.001);
      expect(c.snapshot.isStationary, isTrue);

      // A single noisy sample must not end the stop.
      final blip = c.addSample(
        accelBody: Vector3(3, 0, -NavMath.gravity),
        gyroBody: Vector3(0, 0, 0.5),
        monotonicUs: 3020000,
      );
      expect(blip.isStationary, isTrue);

      var transitions = 0;
      var previous = true;
      for (var i = 0; i < 200; i++) {
        // Alternating quiet/noisy samples: pathological input.
        final noisy = i.isEven;
        final s = c.addSample(
          accelBody: Vector3(
            noisy ? 0.5 : 0,
            0,
            -NavMath.gravity,
          ),
          gyroBody: Vector3(0, 0, noisy ? 0.1 : 0),
          monotonicUs: 3040000 + i * 20000,
        );
        if (s.isStationary != previous) {
          transitions++;
          previous = s.isStationary;
        }
      }
      expect(transitions, lessThan(6),
          reason: 'hysteresis must damp chatter, not track every sample');
    });

    test('stop duration accumulates and resets when motion resumes', () {
      final c = MotionClassifier();
      feed(c, seconds: 5, noiseAccel: 0.01, noiseGyro: 0.001);
      expect(c.snapshot.stopDuration.inSeconds, greaterThanOrEqualTo(4));

      feed(c, seconds: 2, noiseAccel: 1.5, noiseGyro: 0.3, startUs: 5000000);
      expect(c.snapshot.stopDuration, Duration.zero);
      expect(c.snapshot.stopStartedAtUs, isNull);
    });
  });

  group('classification', () {
    test('before there is history the state is unknown, not a guess', () {
      final c = MotionClassifier();
      final s = c.addSample(
        accelBody: Vector3(0, 0, -NavMath.gravity),
        gyroBody: Vector3.zero(),
        monotonicUs: 0,
      );
      expect(s.state, VehicleState.unknown);
      expect(s.confidence, lessThan(0.2));
    });

    test('confidence rises as the window fills', () {
      final c = MotionClassifier();
      final short = feed(c, seconds: 0.2, noiseAccel: 0.05);
      final full = feed(c, seconds: 2, noiseAccel: 0.05, startUs: 200000);
      expect(full.confidence, greaterThan(short.confidence));
      expect(full.confidence, closeTo(1.0, 0.05));
    });

    test('sustained forward acceleration reads as accelerating', () {
      final c = MotionClassifier();
      final s = feed(
        c,
        seconds: 2,
        noiseAccel: 0.1,
        noiseGyro: 0.01,
        longitudinal: 2.0,
        filterSpeed: 10,
      );
      expect(s.state, VehicleState.accelerating);
      expect(s.longitudinalAccel, closeTo(2.0, 0.2));
    });

    test('sustained deceleration reads as braking', () {
      final c = MotionClassifier();
      final s = feed(
        c,
        seconds: 2,
        noiseAccel: 0.1,
        noiseGyro: 0.01,
        longitudinal: -4.0,
        filterSpeed: 15,
      );
      expect(s.state, VehicleState.braking);
    });

    test('a yaw rate reads as turning, a big one as a sharp turn', () {
      final turning = feed(
        MotionClassifier(),
        seconds: 2,
        noiseAccel: 0.1,
        noiseGyro: 0.01,
        yawRate: 0.25,
        filterSpeed: 10,
      );
      expect(turning.state, VehicleState.turning);

      final sharp = feed(
        MotionClassifier(),
        seconds: 2,
        noiseAccel: 0.1,
        noiseGyro: 0.01,
        yawRate: 0.9,
        filterSpeed: 10,
      );
      expect(sharp.state, VehicleState.sharpTurning);
    });

    test('heavy vibration reads as rough road', () {
      final s = feed(
        MotionClassifier(),
        seconds: 2,
        noiseAccel: 6.0,
        noiseGyro: 0.05,
        filterSpeed: 10,
      );
      expect(s.state, VehicleState.roughRoad);
      expect(s.vibrationRms, greaterThan(NavConfig.defaults.motion.severeRms));
    });

    test('a NaN sample reports a sensor anomaly instead of a motion state', () {
      final c = MotionClassifier();
      feed(c, seconds: 2, noiseAccel: 0.1);
      final s = c.addSample(
        accelBody: Vector3(double.nan, 0, -9.8),
        gyroBody: Vector3.zero(),
        monotonicUs: 2000000,
      );
      expect(s.state, VehicleState.sensorAnomaly);
      expect(s.isStationary, isFalse);
      expect(s.nhcApplicable, isFalse);
    });

    test('an absurd magnitude reports a sensor anomaly', () {
      final c = MotionClassifier();
      for (var i = 0; i < 60; i++) {
        c.addSample(
          accelBody: Vector3(200, 0, -9.8),
          gyroBody: Vector3.zero(),
          monotonicUs: i * 20000,
        );
      }
      expect(c.snapshot.state, VehicleState.sensorAnomaly);
    });
  });

  group('non-holonomic applicability', () {
    test('NHC applies while cruising', () {
      final s = feed(
        MotionClassifier(),
        seconds: 2,
        noiseAccel: 0.15,
        noiseGyro: 0.01,
        filterSpeed: 15,
      );
      expect(s.nhcApplicable, isTrue);
    });

    test('NHC is suppressed in a hard turn, where the assumption is weakest',
        () {
      final s = feed(
        MotionClassifier(),
        seconds: 2,
        noiseAccel: 0.15,
        noiseGyro: 0.01,
        yawRate: 1.2,
        filterSpeed: 15,
      );
      expect(s.nhcApplicable, isFalse);
    });

    test('NHC is suppressed while stopped — ZUPT covers that case', () {
      final c = MotionClassifier();
      final s = feed(c, seconds: 3, noiseAccel: 0.01, noiseGyro: 0.001);
      expect(s.isStationary, isTrue);
      expect(s.nhcApplicable, isFalse);
    });
  });

  group('two-wheeler', () {
    test('a car gets the tight lateral sigma, a bike a looser one', () {
      final car = MotionClassifier(vehicleClass: VehicleClass.car);
      final bike = MotionClassifier(vehicleClass: VehicleClass.twoWheeler);
      feed(car, seconds: 2, noiseAccel: 0.15, filterSpeed: 12);
      feed(bike, seconds: 2, noiseAccel: 0.15, filterSpeed: 12);
      expect(bike.nhcLateralSigma, greaterThan(car.nhcLateralSigma));
    });

    test('lean widens the lateral sigma further', () {
      final bike = MotionClassifier(vehicleClass: VehicleClass.twoWheeler);
      feed(bike, seconds: 2, noiseAccel: 0.1, filterSpeed: 12, rollRad: 0);
      final upright = bike.nhcLateralSigma;

      feed(
        bike,
        seconds: 2,
        noiseAccel: 0.1,
        filterSpeed: 12,
        rollRad: 30 * NavMath.degToRad,
        startUs: 2000000,
      );
      expect(bike.nhcLateralSigma, greaterThan(upright));
    });

    test('a leaning bike is classified as leaning, and a car never is', () {
      final bike = MotionClassifier(vehicleClass: VehicleClass.twoWheeler);
      final leaning = feed(
        bike,
        seconds: 2,
        noiseAccel: 0.1,
        noiseGyro: 0.01,
        filterSpeed: 12,
        rollRad: 25 * NavMath.degToRad,
      );
      expect(leaning.state, VehicleState.leaning);
      expect(leaning.leanAngleDeg, closeTo(25, 0.5));

      final car = MotionClassifier(vehicleClass: VehicleClass.car);
      final carState = feed(
        car,
        seconds: 2,
        noiseAccel: 0.1,
        noiseGyro: 0.01,
        filterSpeed: 12,
        rollRad: 25 * NavMath.degToRad,
      );
      expect(carState.state, isNot(VehicleState.leaning));
      expect(carState.leanAngleRad, isNull);
    });

    test('lean falls back to lateral specific force when roll is unknown', () {
      final bike = MotionClassifier(vehicleClass: VehicleClass.twoWheeler);
      // Coordinated turn: a_lat = g*tan(lean). 5.66 m/s^2 => ~30 degrees.
      final s = feed(
        bike,
        seconds: 2,
        noiseAccel: 0.05,
        noiseGyro: 0.01,
        lateral: NavMath.gravity * math.tan(30 * NavMath.degToRad),
        filterSpeed: 12,
      );
      expect(s.leanAngleDeg, closeTo(30, 2));
    });
  });

  group('reset', () {
    test('reset clears the state so a new drive starts from unknown', () {
      final c = MotionClassifier();
      feed(c, seconds: 3, noiseAccel: 0.01, noiseGyro: 0.001);
      expect(c.snapshot.isStationary, isTrue);
      c.reset();
      expect(c.snapshot.state, VehicleState.unknown);
      expect(c.snapshot.isStationary, isFalse);
      expect(c.snapshot.confidence, 0);
    });
  });
}
