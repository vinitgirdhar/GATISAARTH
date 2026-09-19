import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/calibration/ellipsoid_fit.dart';
import 'package:gatisaarth/core/nav/calibration/sensor_calibration.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

/// Points on an ellipsoid with the given centre and radii, spread over the
/// whole sphere via a Fibonacci lattice.
List<Vector3> ellipsoidCloud({
  required Vector3 centre,
  required Vector3 radii,
  int count = 200,
  double noise = 0,
  int seed = 11,
}) {
  final rng = math.Random(seed);
  final points = <Vector3>[];
  final golden = math.pi * (3 - math.sqrt(5));
  for (var i = 0; i < count; i++) {
    final z = 1 - (2 * i + 1) / count;
    final r = math.sqrt(math.max(0.0, 1 - z * z));
    final theta = golden * i;
    double n() => noise == 0 ? 0 : (rng.nextDouble() - 0.5) * 2 * noise;
    points.add(Vector3(
      centre.x + radii.x * r * math.cos(theta) + n(),
      centre.y + radii.y * r * math.sin(theta) + n(),
      centre.z + radii.z * z + n(),
    ));
  }
  return points;
}

void main() {
  group('EllipsoidFitter', () {
    test('recovers the centre and radii of a clean sphere', () {
      final fit = EllipsoidFitter.fit(ellipsoidCloud(
        centre: Vector3(0.4, -0.2, 0.15),
        radii: Vector3(9.80665, 9.80665, 9.80665),
      ));
      expect(fit, isNotNull);
      expect(fit!.centre.x, closeTo(0.4, 1e-6));
      expect(fit.centre.y, closeTo(-0.2, 1e-6));
      expect(fit.centre.z, closeTo(0.15, 1e-6));
      expect(fit.meanRadius, closeTo(9.80665, 1e-6));
      expect(fit.residualRms, lessThan(1e-6));
      expect(fit.coverage, 1.0);
    });

    test('recovers per-axis radii of an ellipsoid (soft iron)', () {
      final fit = EllipsoidFitter.fit(ellipsoidCloud(
        centre: Vector3(12, -30, 5),
        radii: Vector3(48, 40, 44),
      ));
      expect(fit, isNotNull);
      expect(fit!.radii.x, closeTo(48, 0.05));
      expect(fit.radii.y, closeTo(40, 0.05));
      expect(fit.radii.z, closeTo(44, 0.05));
      // The scale correction maps it back to a sphere.
      final corrected = fit.correct(Vector3(12 + 48, -30, 5));
      expect(corrected.length, closeTo(fit.meanRadius, 0.05));
    });

    test('survives realistic noise', () {
      final fit = EllipsoidFitter.fit(ellipsoidCloud(
        centre: Vector3(0.3, 0.1, -0.25),
        radii: Vector3(9.8, 9.8, 9.8),
        noise: 0.05,
      ));
      expect(fit, isNotNull);
      expect(fit!.centre.x, closeTo(0.3, 0.05));
      expect(fit.centre.z, closeTo(-0.25, 0.05));
      expect(fit.residualRms, lessThan(0.1));
    });

    test('refuses too few samples rather than fitting noise', () {
      expect(
        EllipsoidFitter.fit(ellipsoidCloud(
          centre: Vector3.zero(),
          radii: Vector3(9.8, 9.8, 9.8),
          count: 10,
        )),
        isNull,
      );
    });

    test('refuses a degenerate cloud', () {
      // Every sample identical: no geometry at all.
      final flat = List.generate(80, (_) => Vector3(1, 2, 3));
      expect(EllipsoidFitter.fit(flat), isNull);
    });

    test('coverage reports the octants actually visited', () {
      final full = ellipsoidCloud(
        centre: Vector3.zero(),
        radii: Vector3(9.8, 9.8, 9.8),
      );
      expect(EllipsoidFitter.directionCoverage(full, Vector3.zero()), 1.0);

      // Only the +z hemisphere.
      final half = full.where((v) => v.z > 0).toList();
      expect(
        EllipsoidFitter.directionCoverage(half, Vector3.zero()),
        closeTo(0.5, 0.01),
      );
    });

    test('planarity catches samples confined to one plane', () {
      final sphere = ellipsoidCloud(
        centre: Vector3.zero(),
        radii: Vector3(9.8, 9.8, 9.8),
      );
      expect(
        EllipsoidFitter.planarity(sphere, Vector3.zero()),
        closeTo(1.0, 0.05),
      );

      // A ring in the xy plane: the z axis is never observed.
      final ring = List.generate(120, (i) {
        final a = 2 * math.pi * i / 120;
        return Vector3(9.8 * math.cos(a), 9.8 * math.sin(a), 0);
      });
      expect(EllipsoidFitter.planarity(ring, Vector3.zero()), lessThan(0.1));
    });

    test('gravityError flags a sphere that is not gravity', () {
      final good = EllipsoidFitter.fit(ellipsoidCloud(
        centre: Vector3(0.2, 0, 0),
        radii: Vector3(9.80665, 9.80665, 9.80665),
      ))!;
      expect(good.gravityError, lessThan(0.01));

      final moving = EllipsoidFitter.fit(ellipsoidCloud(
        centre: Vector3(0.2, 0, 0),
        radii: Vector3(13, 13, 13),
      ))!;
      expect(moving.gravityError, greaterThan(3));
    });
  });

  group('quick calibration', () {
    CalibrationEstimator quick() => CalibrationEstimator(
          mode: CalibrationMode.quick,
          config: const NavConfig(
            calibration: CalibrationConfig(minSamples: 100),
          ),
        );

    void feedStill(
      CalibrationEstimator e, {
      required Vector3 gyroBias,
      int count = 400,
      double noise = 0.002,
      int seed = 3,
      double? temperatureC,
    }) {
      final rng = math.Random(seed);
      for (var i = 0; i < count; i++) {
        double n(double s) => (rng.nextDouble() - 0.5) * 2 * s;
        e.add(
          accel: Vector3(n(0.01), n(0.01), -NavMath.gravity + n(0.01)),
          gyro: gyroBias + Vector3(n(noise), n(noise), n(noise)),
          temperatureC: temperatureC,
        );
      }
    }

    test('recovers the gyroscope bias', () {
      final e = quick();
      feedStill(e, gyroBias: Vector3(0.004, -0.002, 0.009));
      final cal = e.finish(nowMs: 1000);
      expect(cal, isNotNull);
      expect(cal!.gyroBias.x, closeTo(0.004, 0.001));
      expect(cal.gyroBias.y, closeTo(-0.002, 0.001));
      expect(cal.gyroBias.z, closeTo(0.009, 0.001));
      expect(cal.gyroBiasQuality, isNotNull);
      expect(cal.gyroBiasQuality!, greaterThan(0.5));
    });

    test('does NOT claim an accelerometer bias — it is unobservable from one '
        'orientation', () {
      final e = quick();
      feedStill(e, gyroBias: Vector3.zero());
      final cal = e.finish(nowMs: 1000)!;
      expect(cal.accelBiasQuality, isNull);
      expect(cal.accelBias.length, 0);
      expect(
        cal.notes.any((n) => n.contains('several orientations')),
        isTrue,
      );
    });

    test('measures real noise statistics instead of using a datasheet number',
        () {
      final e = quick();
      feedStill(e, gyroBias: Vector3.zero(), noise: 0.004);
      final cal = e.finish(nowMs: 1000)!;
      expect(cal.gyroNoiseStd, isNotNull);
      expect(cal.gyroNoiseStd!, greaterThan(0));
      expect(cal.accelNoiseStd, isNotNull);
    });

    test('returns null when the phone never settled', () {
      final e = quick();
      final rng = math.Random(5);
      for (var i = 0; i < 400; i++) {
        double n(double s) => (rng.nextDouble() - 0.5) * 2 * s;
        e.add(
          accel: Vector3(n(3), n(3), -NavMath.gravity + n(3)),
          gyro: Vector3(n(1), n(1), n(1)),
        );
      }
      expect(e.finish(nowMs: 1000), isNull);
    });

    test('rejects a bias so large the phone must have been moving', () {
      final e = quick();
      // A steady 0.5 rad/s is a turntable, not a bias.
      feedStill(e, gyroBias: Vector3(0.5, 0, 0), noise: 0.001);
      expect(e.finish(nowMs: 1000), isNull);
    });

    test('progress tells the user what to do', () {
      final e = quick();
      expect(e.progress.ready, isFalse);
      expect(e.progress.hint, contains('still'));
      feedStill(e, gyroBias: Vector3.zero());
      expect(e.progress.ready, isTrue);
      expect(e.progress.isStill, isTrue);
      expect(e.progress.hint, 'Done');
    });
  });

  group('full calibration', () {
    test('recovers accelerometer bias and scale from several orientations', () {
      final e = CalibrationEstimator(
        mode: CalibrationMode.full,
        config: const NavConfig(
          calibration: CalibrationConfig(minSamples: 100),
        ),
      );
      final bias = Vector3(0.35, -0.2, 0.15);
      final cloud = ellipsoidCloud(
        centre: bias,
        radii: Vector3(9.80665, 9.80665, 9.80665),
        count: 60,
      );
      // Each orientation is held still for a while — that is what the user
      // actually does when told to rest the phone on a new face.
      for (final orientation in cloud) {
        for (var i = 0; i < 30; i++) {
          e.add(accel: orientation, gyro: Vector3.zero());
        }
      }
      final cal = e.finish(nowMs: 2000);
      expect(cal, isNotNull);
      expect(cal!.accelBias.x, closeTo(bias.x, 0.02));
      expect(cal.accelBias.y, closeTo(bias.y, 0.02));
      expect(cal.accelBias.z, closeTo(bias.z, 0.02));
      expect(cal.accelBiasQuality, isNotNull);
      expect(cal.accelBiasQuality!, greaterThan(0.7));
    });

    test('recovers magnetometer hard iron and soft iron', () {
      final e = CalibrationEstimator(
        mode: CalibrationMode.full,
        config: const NavConfig(
          calibration: CalibrationConfig(minSamples: 100),
        ),
      );
      final hardIron = Vector3(14, -22, 6);
      final magCloud = ellipsoidCloud(
        centre: hardIron,
        radii: Vector3(50, 42, 46),
        count: 200,
      );
      final accelCloud = ellipsoidCloud(
        centre: Vector3.zero(),
        radii: Vector3(9.80665, 9.80665, 9.80665),
        count: 40,
      );
      for (var i = 0; i < magCloud.length; i++) {
        e.add(
          accel: accelCloud[i % accelCloud.length],
          gyro: Vector3.zero(),
          mag: magCloud[i],
        );
      }
      // Top up the still-sample count.
      for (var i = 0; i < 200; i++) {
        e.add(
          accel: accelCloud[i % accelCloud.length],
          gyro: Vector3.zero(),
          mag: magCloud[i % magCloud.length],
        );
      }
      final cal = e.finish(nowMs: 3000);
      expect(cal, isNotNull);
      expect(cal!.magHardIron.x, closeTo(14, 1));
      expect(cal.magHardIron.y, closeTo(-22, 1));
      expect(cal.magQuality, isNotNull);
      // Correcting a raw reading should land it on a sphere.
      final corrected = cal.correctMag(Vector3(14 + 50, -22, 6));
      final other = cal.correctMag(Vector3(14, -22 + 42, 6));
      expect(corrected.length, closeTo(other.length, 1.0));
    });

    test('a magnetometer that barely moved is discarded, not reported', () {
      final e = CalibrationEstimator(
        mode: CalibrationMode.full,
        config: const NavConfig(
          calibration: CalibrationConfig(minSamples: 50),
        ),
      );
      final accelCloud = ellipsoidCloud(
        centre: Vector3.zero(),
        radii: Vector3(9.80665, 9.80665, 9.80665),
        count: 40,
      );
      final rng = math.Random(9);
      for (var i = 0; i < 300; i++) {
        e.add(
          accel: accelCloud[i % accelCloud.length],
          gyro: Vector3.zero(),
          // Jitter of a couple of microtesla around one direction.
          mag: Vector3(
            45 + (rng.nextDouble() - 0.5) * 2,
            2 + (rng.nextDouble() - 0.5) * 2,
            18 + (rng.nextDouble() - 0.5) * 2,
          ),
        );
      }
      final cal = e.finish(nowMs: 4000)!;
      expect(cal.magQuality, isNull);
      expect(cal.magHardIron.length, 0);
    });

    test('an accelerometer fit that is not gravity is rejected with a reason',
        () {
      final e = CalibrationEstimator(
        mode: CalibrationMode.full,
        config: const NavConfig(
          calibration: CalibrationConfig(minSamples: 50),
        ),
      );
      // Radius 13 m/s²: the phone was being swung, not rested.
      final cloud = ellipsoidCloud(
        centre: Vector3.zero(),
        radii: Vector3(13, 13, 13),
        count: 60,
      );
      for (final orientation in cloud) {
        for (var i = 0; i < 10; i++) {
          e.add(accel: orientation, gyro: Vector3.zero());
        }
      }
      final cal = e.finish(nowMs: 5000)!;
      expect(cal.accelBiasQuality, isNull);
      expect(cal.notes.any((n) => n.contains('not gravity')), isTrue);
    });

    test('progress prompts for more orientations', () {
      final e = CalibrationEstimator(mode: CalibrationMode.full);
      for (var i = 0; i < 60; i++) {
        e.add(
          accel: Vector3(0, 0, -NavMath.gravity),
          gyro: Vector3.zero(),
        );
      }
      expect(e.progress.orientationsSeen, 1);
      expect(e.progress.hint, contains('different position'));
      expect(e.progress.ready, isFalse);
    });
  });

  group('persistence and invalidation', () {
    SensorCalibration sample() => SensorCalibration(
          mode: CalibrationMode.full,
          createdAtMs: 1000000,
          gyroBias: Vector3(0.001, 0.002, -0.003),
          accelBias: Vector3(0.1, 0.2, 0.3),
          accelScale: Vector3(1.01, 0.99, 1.0),
          magHardIron: Vector3(10, -20, 5),
          magSoftIron: Vector3(1.02, 0.98, 1.0),
          gyroBiasQuality: 0.91,
          accelBiasQuality: 0.83,
          magQuality: 0.62,
          gyroNoiseStd: 0.003,
          temperatureC: 31,
        );

    test('round-trips through JSON', () {
      final restored = SensorCalibration.fromJson(sample().toJson());
      expect(restored, isNotNull);
      expect(restored!.gyroBias.z, closeTo(-0.003, 1e-12));
      expect(restored.accelScale.x, closeTo(1.01, 1e-12));
      expect(restored.magQuality, closeTo(0.62, 1e-12));
      expect(restored.temperatureC, 31);
      expect(restored.mode, CalibrationMode.full);
    });

    test('corrupt JSON returns null instead of throwing', () {
      expect(SensorCalibration.fromJson(const {}), isNull);
      expect(
        SensorCalibration.fromJson(const {'createdAtMs': 'yesterday'}),
        isNull,
      );
      final partial = sample().toJson()..['accelBias'] = 'nonsense';
      final restored = SensorCalibration.fromJson(partial);
      expect(restored, isNotNull);
      // A bad field falls back to identity, never to a random number.
      expect(restored!.accelBias.length, 0);
    });

    test('an empty calibration is always stale', () {
      expect(SensorCalibration.none.isStale(nowMs: 1), isTrue);
    });

    test('goes stale with age', () {
      final cal = sample();
      expect(cal.isStale(nowMs: cal.createdAtMs + 1000), isFalse);
      expect(
        cal.isStale(
          nowMs: cal.createdAtMs +
              const Duration(days: 30).inMilliseconds,
        ),
        isTrue,
      );
    });

    test('goes stale on a large temperature swing', () {
      final cal = sample();
      expect(
        cal.isStale(nowMs: cal.createdAtMs + 1000, temperatureC: 36),
        isFalse,
      );
      expect(
        cal.isStale(nowMs: cal.createdAtMs + 1000, temperatureC: 55),
        isTrue,
      );
    });

    test('goes stale when the config version moves', () {
      final cal = SensorCalibration(
        mode: CalibrationMode.quick,
        createdAtMs: 1000,
        configVersion: NavConfig.currentVersion + 1,
      );
      expect(cal.isStale(nowMs: 2000), isTrue);
    });

    test('corrections are applied in the right order', () {
      final cal = SensorCalibration(
        mode: CalibrationMode.full,
        createdAtMs: 1,
        accelBias: Vector3(1, 0, 0),
        accelScale: Vector3(2, 1, 1),
        gyroBias: Vector3(0.1, 0, 0),
      );
      // (5 - 1) * 2 = 8, not 5*2 - 1 = 9.
      expect(cal.correctAccel(Vector3(5, 0, 0)).x, 8);
      expect(cal.correctGyro(Vector3(0.3, 0, 0)).x, closeTo(0.2, 1e-12));
    });

    test('an identity calibration changes nothing', () {
      final raw = Vector3(1, 2, 3);
      expect(SensorCalibration.none.correctAccel(raw).x, 1);
      expect(SensorCalibration.none.correctGyro(raw).y, 2);
      expect(SensorCalibration.none.correctMag(raw).z, 3);
    });
  });
}
