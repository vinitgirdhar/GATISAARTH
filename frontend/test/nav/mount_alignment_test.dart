import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/alignment/mount_alignment.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

/// A phone mounting, expressed as the vehicle axes seen in phone coordinates.
class Mount {
  const Mount({
    required this.name,
    required this.forward,
    required this.down,
  });

  final String name;
  final Vector3 forward;
  final Vector3 down;

  Vector3 get right => down.cross(forward).normalized();

  /// What this mounted phone measures, given vehicle-frame motion.
  ///
  /// Specific force is `a_kinematic - g`, and in the vehicle frame gravity is
  /// `(0, 0, +g)` with down positive, so a stationary level vehicle gives
  /// `(0, 0, -g)`.
  Vector3 measure({
    double longitudinal = 0,
    double lateral = 0,
    double vertical = 0,
  }) {
    final specificVehicle = Vector3(
      longitudinal,
      lateral,
      vertical - NavMath.gravity,
    );
    // Vehicle -> phone: the vehicle axes are already in phone coordinates.
    return forward * specificVehicle.x +
        right * specificVehicle.y +
        down * specificVehicle.z;
  }
}

/// Phone lying flat on the dashboard, its top pointing at the windscreen.
final flatTopForward = Mount(
  name: 'flat, top forward',
  forward: Vector3(0, 1, 0),
  down: Vector3(0, 0, -1),
);

/// Same, but rotated 90 degrees clockwise in its cradle (landscape).
final flatRotated90 = Mount(
  name: 'flat, rotated 90 deg',
  forward: Vector3(1, 0, 0),
  down: Vector3(0, 0, -1),
);

/// Windscreen mount: phone standing upright, screen facing the driver, top up.
final windscreenUpright = Mount(
  name: 'windscreen upright',
  forward: Vector3(0, 0, -1),
  down: Vector3(0, -1, 0),
);

/// Awkward console mount: yawed 35 deg and tilted 25 deg back.
Mount tilted() {
  const yaw = 35 * NavMath.degToRad;
  const tilt = 25 * NavMath.degToRad;
  // Start flat/top-forward, tilt about the phone x axis, then yaw about down.
  final down = Vector3(0, -math.sin(tilt), -math.cos(tilt)).normalized();
  final flatForward = Vector3(0, math.cos(tilt), -math.sin(tilt)).normalized();
  // Rotate the forward axis about the down axis by `yaw`.
  final right = down.cross(flatForward).normalized();
  final forward =
      (flatForward * math.cos(yaw) + right * math.sin(yaw)).normalized();
  return Mount(name: 'tilted console', forward: forward, down: down);
}

/// Drives a synthetic calibration run through the estimator.
MountAlignmentEstimator driveThrough(
  Mount mount, {
  NavConfig config = NavConfig.defaults,
  int events = 24,
  double accelMagnitude = 1.6,
  double lateralNoise = 0.05,
  double yawRate = 0.0,
  bool withGnss = true,
  int seed = 17,
}) {
  final e = MountAlignmentEstimator(config: config);
  final rng = math.Random(seed);

  // Settle gravity first — a phone in a mount is level before it moves.
  for (var i = 0; i < 400; i++) {
    e.add(
      accelPhone: mount.measure(),
      gyroPhone: Vector3.zero(),
      monotonicUs: i * 20000,
      gnssSpeedMps: withGnss ? 0 : null,
      gnssUs: i * 20000,
    );
  }

  var us = 400 * 20000;
  var speed = 0.0;
  for (var event = 0; event < events; event++) {
    // Alternate acceleration and braking, so the regression sees both signs.
    final a = event.isEven ? accelMagnitude : -accelMagnitude;
    for (var i = 0; i < 25; i++) {
      us += 20000;
      speed = (speed + a * 0.02).clamp(0.0, 40.0);
      double n(double s) => (rng.nextDouble() - 0.5) * 2 * s;
      e.add(
        accelPhone: mount.measure(
          longitudinal: a + n(0.05),
          lateral: n(lateralNoise),
          vertical: n(0.05),
        ),
        gyroPhone: Vector3(0, 0, yawRate),
        monotonicUs: us,
        gnssSpeedMps: withGnss ? speed : null,
        gnssUs: us,
      );
    }
  }
  return e;
}

void main() {
  group('levelling', () {
    test('gravity alone gives the down axis before any driving', () {
      final e = MountAlignmentEstimator();
      for (var i = 0; i < 100; i++) {
        e.add(
          accelPhone: flatTopForward.measure(),
          gyroPhone: Vector3.zero(),
          monotonicUs: i * 20000,
        );
      }
      expect(e.hasLevelling, isTrue);
      final up = e.upInPhone!;
      // Phone flat, screen up: "up" in phone coordinates is +z.
      expect(up.z, closeTo(1, 1e-6));
      // But nothing may be published about the forward axis yet.
      expect(e.alignment, isNull);
      expect(e.isConverged, isFalse);
    });

    test('a windscreen mount levels to a different down axis', () {
      final e = MountAlignmentEstimator();
      for (var i = 0; i < 100; i++) {
        e.add(
          accelPhone: windscreenUpright.measure(),
          gyroPhone: Vector3.zero(),
          monotonicUs: i * 20000,
        );
      }
      final up = e.upInPhone!;
      expect(up.y, closeTo(1, 1e-6));
      expect(up.z, closeTo(0, 1e-6));
    });
  });

  group('forward axis recovery', () {
    void expectRecovers(Mount mount, {double toleranceDeg = 4}) {
      final e = driveThrough(mount);
      final a = e.alignment;
      expect(a, isNotNull, reason: '${mount.name}: nothing published');
      final angle = math.acos(
            a!.forwardInPhone.dot(mount.forward).clamp(-1.0, 1.0),
          ) *
          NavMath.radToDeg;
      expect(angle, lessThan(toleranceDeg),
          reason: '${mount.name}: forward axis off by '
              '${angle.toStringAsFixed(1)} deg');
      expect(e.isConverged, isTrue, reason: '${mount.name}: not converged');
    }

    test('flat with the top pointing forward', () {
      expectRecovers(flatTopForward);
    });

    test('flat but rotated 90 degrees in the cradle', () {
      expectRecovers(flatRotated90);
    });

    test('upright in a windscreen mount', () {
      expectRecovers(windscreenUpright);
    });

    test('yawed and tilted on a centre console', () {
      expectRecovers(tilted());
    });

    test('the recovered frame is orthonormal and right-handed', () {
      final a = driveThrough(tilted()).alignment!;
      expect(a.forwardInPhone.dot(a.rightInPhone).abs(), lessThan(1e-9));
      expect(a.forwardInPhone.dot(a.downInPhone).abs(), lessThan(1e-9));
      expect(a.rightInPhone.dot(a.downInPhone).abs(), lessThan(1e-9));
      expect(a.forwardInPhone.length, closeTo(1, 1e-9));
      // forward x right == down for x-forward, y-right, z-down.
      final cross = a.forwardInPhone.cross(a.rightInPhone);
      expect(cross.dot(a.downInPhone), closeTo(1, 1e-9));
    });

    test('the transform maps vehicle motion into the vehicle frame', () {
      final mount = tilted();
      final a = driveThrough(mount).alignment!;
      // Pure braking in the vehicle frame must come back as pure -x.
      final measured = mount.measure(longitudinal: -3.0) - mount.measure();
      final inVehicle = a.toVehicle(measured);
      expect(inVehicle.x, closeTo(-3.0, 0.15));
      expect(inVehicle.y.abs(), lessThan(0.2));
      expect(inVehicle.z.abs(), lessThan(0.2));
    });

    test('the sign is resolved — forward is forward, not backward', () {
      // A sign error would show as a 180 degree error and is the failure that
      // sends dead reckoning the wrong way down the road.
      for (final mount in [flatTopForward, flatRotated90, tilted()]) {
        final a = driveThrough(mount).alignment!;
        expect(a.forwardInPhone.dot(mount.forward), greaterThan(0.9),
            reason: '${mount.name}: forward axis points backwards');
      }
    });
  });

  group('reported offsets', () {
    test('a flat top-forward phone has no offsets at all', () {
      final a = driveThrough(flatTopForward).alignment!;
      expect(a.yawOffsetDeg.abs(), lessThan(4));
      expect(a.pitchOffsetDeg.abs(), lessThan(1));
      expect(a.rollOffsetDeg.abs(), lessThan(1));
    });

    test('a 90 degree cradle rotation shows as a 90 degree yaw offset', () {
      final a = driveThrough(flatRotated90).alignment!;
      expect(a.yawOffsetDeg.abs(), closeTo(90, 5));
      expect(a.pitchOffsetDeg.abs(), lessThan(1));
    });

    test('an upright windscreen mount shows as a large pitch offset', () {
      final a = driveThrough(windscreenUpright).alignment!;
      expect(a.pitchOffsetDeg.abs(), closeTo(90, 2));
    });

    test('a 25 degree console tilt is reported as such', () {
      final a = driveThrough(tilted()).alignment!;
      expect(a.pitchOffsetDeg.abs(), closeTo(25, 2));
    });
  });

  group('refusal to guess', () {
    test('no GNSS speed means no forward axis, ever', () {
      final e = driveThrough(flatTopForward, withGnss: false);
      expect(e.alignment, isNull);
      expect(e.isConverged, isFalse);
      expect(e.acceptedSamples, 0);
    });

    test('driving at a constant speed teaches nothing', () {
      final e = MountAlignmentEstimator();
      for (var i = 0; i < 2000; i++) {
        e.add(
          accelPhone: flatTopForward.measure(),
          gyroPhone: Vector3.zero(),
          monotonicUs: i * 20000,
          gnssSpeedMps: 20,
          gnssUs: i * 20000,
        );
      }
      expect(e.alignment, isNull);
      expect(e.acceptedSamples, 0);
    });

    test('samples taken mid-turn are rejected', () {
      // Same drive, but the vehicle is turning throughout: the horizontal
      // acceleration is then not purely longitudinal.
      final e = driveThrough(flatTopForward, yawRate: 0.5);
      expect(e.acceptedSamples, 0);
      expect(e.alignment, isNull);
    });

    test('too few events leave it unconverged, with a reason', () {
      final e = driveThrough(flatTopForward, events: 6);
      // It may publish a provisional estimate, but must not claim calibration.
      expect(e.isConverged, isFalse);
      if (e.alignment != null) {
        expect(e.alignment!.confidence, lessThan(0.6));
      }
    });

    test('confidence never reaches 1', () {
      final e = driveThrough(flatTopForward, events: 80);
      expect(e.alignment!.confidence, lessThan(1.0));
    });

    test('a NaN sample is ignored rather than poisoning the fit', () {
      final e = driveThrough(flatTopForward);
      final before = e.alignment!.forwardInPhone.clone();
      e.add(
        accelPhone: Vector3(double.nan, 0, 0),
        gyroPhone: Vector3.zero(),
        monotonicUs: 99999999,
        gnssSpeedMps: 10,
        gnssUs: 99999999,
      );
      expect(e.alignment!.forwardInPhone.x, closeTo(before.x, 1e-12));
    });

    test('a GNSS gap does not produce a bogus derivative', () {
      final e = MountAlignmentEstimator();
      for (var i = 0; i < 400; i++) {
        e.add(
          accelPhone: flatTopForward.measure(),
          gyroPhone: Vector3.zero(),
          monotonicUs: i * 20000,
          gnssSpeedMps: 0,
          gnssUs: i * 20000,
        );
      }
      // A 30 s hole, then 25 m/s. That is not a 0.83 m/s² acceleration event.
      e.add(
        accelPhone: flatTopForward.measure(longitudinal: 1.0),
        gyroPhone: Vector3.zero(),
        monotonicUs: 38000000,
        gnssSpeedMps: 25,
        gnssUs: 38000000,
      );
      expect(e.acceptedSamples, 0);
    });
  });

  group('mount movement', () {
    test('a phone knocked into a new position restarts the fit', () {
      final e = driveThrough(flatTopForward);
      expect(e.isConverged, isTrue);

      // The phone is bumped: gravity now points somewhere else entirely.
      for (var i = 0; i < 500; i++) {
        e.add(
          accelPhone: windscreenUpright.measure(),
          gyroPhone: Vector3.zero(),
          monotonicUs: 50000000 + i * 20000,
          gnssSpeedMps: 10,
          gnssUs: 50000000 + i * 20000,
        );
      }
      expect(e.isConverged, isFalse,
          reason: 'a moved mount must not keep claiming to be calibrated');
    });

    test('reset clears everything', () {
      final e = driveThrough(flatTopForward);
      expect(e.alignment, isNotNull);
      e.reset();
      expect(e.alignment, isNull);
      expect(e.acceptedSamples, 0);
      expect(e.hasLevelling, isFalse);
    });
  });

  group('configuration', () {
    test('a stricter convergence bar is respected', () {
      final e = driveThrough(
        flatTopForward,
        config: const NavConfig(
          alignment: AlignmentConfig(minSamples: 4000),
        ),
      );
      expect(e.isConverged, isFalse);
    });

    test('no configuration can make it claim certainty', () {
      // Confidence is capped below 1, so a bar of 0.99 is unreachable however
      // good the drive was (§83).
      final e = driveThrough(
        flatTopForward,
        events: 80,
        config: const NavConfig(
          alignment: AlignmentConfig(convergedConfidence: 0.99),
        ),
      );
      expect(e.alignment!.confidence, lessThanOrEqualTo(0.98));
      expect(e.isConverged, isFalse);
    });
  });

  group('real-phone vibration', () {
    // A cradle-mounted phone on a real road (three drives, 2026-09-24): the
    // gyro shakes by ~0.4 rad/s and the accelerometer by ~1.2 m/s^2 sample to
    // sample, zero-mean. Gating each sample on "straight" and "agrees with
    // GNSS" rejected nearly all of them and the mount never aligned.
    test('aligns through zero-mean shake with 100 Hz IMU and 1 Hz GNSS', () {
      final e = MountAlignmentEstimator();
      final mount = tilted();
      final rng = math.Random(5);
      double n(double s) => (rng.nextDouble() - 0.5) * 2 * s * math.sqrt(3);
      Vector3 shake(double s) => Vector3(n(s), n(s), n(s));
      var us = 0;
      var speed = 0.0;
      var fixSpeed = 0.0;
      var fixUs = 0;
      void run(double accel, int seconds) {
        for (var i = 0; i < seconds * 100; i++) {
          us += 10000;
          speed = (speed + accel * 0.01).clamp(0.0, 40.0);
          if (us - fixUs >= 1000000) {
            fixUs = us;
            fixSpeed = speed;
          }
          e.add(
            accelPhone: mount.measure(longitudinal: accel) + shake(1.2),
            gyroPhone: shake(0.4),
            monotonicUs: us,
            gnssSpeedMps: fixSpeed,
            gnssUs: fixUs,
          );
        }
      }

      run(0, 5);
      for (var cycle = 0; cycle < 15; cycle++) {
        run(1.2, 4);
        run(0, 2);
        run(-1.2, 4);
        run(0, 2);
      }
      expect(e.isConverged, isTrue);
      final forward = e.alignment!.forwardInPhone;
      final errDeg =
          math.acos(forward.dot(mount.forward).clamp(-1.0, 1.0)) * 180 / math.pi;
      expect(errDeg, lessThan(5));
    });
  });
}
