import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/sensors/barometer.dart';
import 'package:gatisaarth/core/nav/sensors/sensor_fault_detector.dart';
import 'package:gatisaarth/core/nav/sensors/sensor_sample.dart';

void main() {
  group('SensorFaultDetector', () {
    SensorFaultDetector detector({NavConfig? config}) =>
        SensorFaultDetector(config: config ?? NavConfig.defaults);

    void feed(
      SensorFaultDetector d, {
      required SensorType type,
      required List<double> Function(int i) values,
      int count = 60,
      int startUs = 0,
      int stepUs = 20000,
    }) {
      for (var i = 0; i < count; i++) {
        d.observe(
          type: type,
          values: values(i),
          monotonicUs: startUs + i * stepUs,
        );
      }
    }

    test('a healthy accelerometer reads healthy', () {
      final d = detector();
      final rng = math.Random(3);
      feed(
        d,
        type: SensorType.accelerometer,
        values: (_) => [
          (rng.nextDouble() - 0.5) * 0.1,
          (rng.nextDouble() - 0.5) * 0.1,
          -9.81 + (rng.nextDouble() - 0.5) * 0.1,
        ],
      );
      final diagnosis = d.diagnosisFor(SensorType.accelerometer);
      expect(diagnosis.fault, SensorFault.none);
      expect(diagnosis.usable, isTrue);
      expect(diagnosis.magnitude, closeTo(9.81, 0.2));
    });

    test('identical readings are a frozen sensor, not a still phone', () {
      final d = detector();
      // A phone on a desk still jitters; byte-identical values do not happen.
      feed(
        d,
        type: SensorType.gyroscope,
        values: (_) => const [0.001, -0.002, 0.0005],
      );
      final diagnosis = d.diagnosisFor(SensorType.gyroscope);
      expect(diagnosis.fault, SensorFault.frozen);
      expect(diagnosis.usable, isFalse);
      expect(diagnosis.detail, contains('identical'));
    });

    test('a still-but-jittering sensor is not called frozen', () {
      final d = detector();
      final rng = math.Random(11);
      feed(
        d,
        type: SensorType.gyroscope,
        values: (_) => [
          (rng.nextDouble() - 0.5) * 1e-4,
          (rng.nextDouble() - 0.5) * 1e-4,
          (rng.nextDouble() - 0.5) * 1e-4,
        ],
      );
      expect(d.diagnosisFor(SensorType.gyroscope).fault, SensorFault.none);
    });

    test('physically impossible readings are rejected', () {
      final d = detector();
      d.observe(
        type: SensorType.accelerometer,
        values: const [500, 0, 0],
        monotonicUs: 0,
      );
      final diagnosis = d.diagnosisFor(SensorType.accelerometer);
      expect(diagnosis.fault, SensorFault.outOfRange);
      expect(diagnosis.usable, isFalse);
    });

    test('a NaN reading is rejected', () {
      final d = detector();
      d.observe(
        type: SensorType.accelerometer,
        values: const [double.nan, 0, -9.81],
        monotonicUs: 0,
      );
      expect(
        d.diagnosisFor(SensorType.accelerometer).fault,
        SensorFault.outOfRange,
      );
    });

    test('a hard pothole is rough road, not a broken accelerometer', () {
      final d = detector();
      final rng = math.Random(5);
      feed(
        d,
        type: SensorType.accelerometer,
        values: (_) => [
          (rng.nextDouble() - 0.5) * 6,
          (rng.nextDouble() - 0.5) * 6,
          -9.81 + (rng.nextDouble() - 0.5) * 8,
        ],
      );
      expect(d.diagnosisFor(SensorType.accelerometer).usable, isTrue);
    });

    test('noise far beyond any road is a broken sensor', () {
      final d = detector();
      final rng = math.Random(7);
      // +/-60 m/s^2 per axis. The previous +/-40 gave a magnitude sigma of
      // 11.9 against a 12 limit, which is a coin flip, not a test.
      feed(
        d,
        type: SensorType.accelerometer,
        values: (_) => [
          (rng.nextDouble() - 0.5) * 120,
          (rng.nextDouble() - 0.5) * 120,
          (rng.nextDouble() - 0.5) * 120,
        ],
      );
      final diagnosis = d.diagnosisFor(SensorType.accelerometer);
      expect(diagnosis.fault, SensorFault.excessiveNoise);
      expect(diagnosis.usable, isFalse);
    });

    test('a magnetometer reading the car instead of the planet is flagged',
        () {
      final d = detector();
      // 250 uT is a speaker magnet or a dashboard mount, not Earth.
      feed(
        d,
        type: SensorType.magnetometer,
        values: (i) => [250.0 + i * 0.01, 5, 10],
      );
      final diagnosis = d.diagnosisFor(SensorType.magnetometer);
      expect(diagnosis.fault, SensorFault.magneticDisturbance);
      expect(diagnosis.usable, isFalse);
      expect(diagnosis.detail, contains('Earth'));
    });

    test('an ordinary magnetic field is accepted', () {
      final d = detector();
      final rng = math.Random(13);
      feed(
        d,
        type: SensorType.magnetometer,
        values: (_) => [
          22 + (rng.nextDouble() - 0.5) * 0.5,
          3 + (rng.nextDouble() - 0.5) * 0.5,
          42 + (rng.nextDouble() - 0.5) * 0.5,
        ],
      );
      expect(d.diagnosisFor(SensorType.magnetometer).usable, isTrue);
    });

    test('a sensor that stops is noticed without a new sample', () {
      final d = detector();
      final rng = math.Random(17);
      feed(
        d,
        type: SensorType.accelerometer,
        values: (_) => [
          (rng.nextDouble() - 0.5) * 0.1,
          0,
          -9.81 + (rng.nextDouble() - 0.5) * 0.1,
        ],
      );
      expect(d.isUsable(SensorType.accelerometer), isTrue);

      d.checkStaleness(60 * 20000 + 2000000);
      final diagnosis = d.diagnosisFor(SensorType.accelerometer);
      expect(diagnosis.fault, SensorFault.stalled);
      expect(diagnosis.usable, isFalse);
      expect(diagnosis.detail, contains('ms'));
    });

    test('a dead magnetometer does not stop inertial navigation', () {
      final d = detector();
      final rng = math.Random(19);
      for (final type in [SensorType.accelerometer, SensorType.gyroscope]) {
        feed(
          d,
          type: type,
          values: (_) => [
            (rng.nextDouble() - 0.5) * 0.05,
            (rng.nextDouble() - 0.5) * 0.05,
            type == SensorType.accelerometer
                ? -9.81 + (rng.nextDouble() - 0.5) * 0.05
                : (rng.nextDouble() - 0.5) * 0.05,
          ],
        );
      }
      feed(
        d,
        type: SensorType.magnetometer,
        values: (_) => const [400, 400, 400],
      );

      expect(d.isUsable(SensorType.magnetometer), isFalse);
      // The thing that actually matters:
      expect(d.hasMinimumViableSensors, isTrue);
      expect(d.faultedSensors, [SensorType.magnetometer]);
    });

    test('losing the gyroscope does break the minimum viable set', () {
      final d = detector();
      final rng = math.Random(23);
      feed(
        d,
        type: SensorType.accelerometer,
        values: (_) => [0, 0, -9.81 + (rng.nextDouble() - 0.5) * 0.05],
      );
      feed(
        d,
        type: SensorType.gyroscope,
        values: (_) => const [0.001, 0.001, 0.001],
      );
      expect(d.hasMinimumViableSensors, isFalse);
    });

    test('a sensor never observed reports unavailable, not healthy', () {
      final d = detector();
      final diagnosis = d.diagnosisFor(SensorType.barometer);
      expect(diagnosis.usable, isFalse);
      expect(diagnosis.samples, 0);
      expect(diagnosis.detail, contains('Not present'));
    });

    test('reset clears every diagnosis', () {
      final d = detector();
      feed(d, type: SensorType.accelerometer, values: (_) => const [0, 0, -9.8]);
      expect(d.diagnoses, isNotEmpty);
      d.reset();
      expect(d.diagnoses, isEmpty);
      expect(d.hasMinimumViableSensors, isFalse);
    });
  });

  group('BarometerProcessor', () {
    /// Pressure at a height above the 1013.25 hPa reference level.
    double pressureAt(double metres) =>
        1013.25 * math.pow(1 - metres / 44330.0, 5.255).toDouble();

    test('relative height is recovered from pressure', () {
      final b = BarometerProcessor();
      b.add(pressureHpa: pressureAt(0), monotonicUs: 0);
      // Enough samples for the smoothing to settle on the new level.
      BarometerEstimate? estimate;
      for (var i = 1; i <= 120; i++) {
        estimate = b.add(
          pressureHpa: pressureAt(30),
          monotonicUs: i * 200000,
        );
      }
      expect(estimate!.relativeAltitudeM, closeTo(30, 1.5));
    });

    test('absolute height is null until GNSS anchors it', () {
      final b = BarometerProcessor();
      final first = b.add(pressureHpa: pressureAt(0), monotonicUs: 0)!;
      expect(first.relativeAltitudeM, isNotNull);
      expect(first.absoluteAltitudeM, isNull);
      expect(first.sigmaM, isNull);

      b.anchorToGnss(
        altitudeM: 216,
        pressureHpa: pressureAt(0),
        monotonicUs: 1000000,
      );
      final anchored =
          b.add(pressureHpa: pressureAt(0), monotonicUs: 2000000)!;
      expect(anchored.absoluteAltitudeM, closeTo(216, 1));
      expect(anchored.sigmaM, isNotNull);
    });

    test('the absolute uncertainty grows once the anchor goes stale', () {
      final b = BarometerProcessor();
      b.add(pressureHpa: pressureAt(0), monotonicUs: 0);
      b.anchorToGnss(
        altitudeM: 100,
        pressureHpa: pressureAt(0),
        monotonicUs: 0,
      );
      final fresh = b.add(pressureHpa: pressureAt(0), monotonicUs: 1000000)!;
      final stale = b.add(
        pressureHpa: pressureAt(0),
        monotonicUs: 3 * 3600 * 1000000,
      )!;
      expect(fresh.sigmaM!, lessThan(3));
      // Three hours of weather is tens of metres of datum drift.
      expect(stale.sigmaM!, greaterThan(20));
      expect(
        stale.sigmaM!,
        greaterThan(NavConfig.defaults.barometer.maxUsableSigmaM),
        reason: 'past this the filter should stop using it',
      );
    });

    test('a climb reads as ascending and a descent as descending', () {
      final b = BarometerProcessor();
      var us = 0;
      BarometerEstimate? estimate;
      // Climb a 30 m ramp over 15 s.
      for (var i = 0; i <= 150; i++) {
        us += 100000;
        estimate = b.add(pressureHpa: pressureAt(i * 0.2), monotonicUs: us);
      }
      expect(estimate!.motion, VerticalMotion.ascending);
      expect(estimate.verticalRateMps!, greaterThan(0.35));

      for (var i = 150; i >= 0; i--) {
        us += 100000;
        estimate = b.add(pressureHpa: pressureAt(i * 0.2), monotonicUs: us);
      }
      expect(estimate!.motion, VerticalMotion.descending);
    });

    test('a level drive stays flat', () {
      final b = BarometerProcessor();
      final rng = math.Random(29);
      BarometerEstimate? estimate;
      for (var i = 0; i < 200; i++) {
        estimate = b.add(
          // A few pascals of sensor noise, no real height change.
          pressureHpa: pressureAt(0) + (rng.nextDouble() - 0.5) * 0.04,
          monotonicUs: i * 200000,
        );
      }
      expect(estimate!.motion, VerticalMotion.flat);
      expect(estimate.relativeAltitudeM!.abs(), lessThan(2));
    });

    test('car-park floors are counted as level changes', () {
      final b = BarometerProcessor();
      var us = 0;
      // Four floors down, 3 m each.
      for (var floor = 0; floor < 4; floor++) {
        for (var i = 0; i <= 60; i++) {
          us += 100000;
          b.add(
            pressureHpa: pressureAt(-(floor * 3 + i * 0.05)),
            monotonicUs: us,
          );
        }
      }
      expect(b.last!.levelChanges, greaterThanOrEqualTo(3));
      expect(b.last!.relativeAltitudeM!, lessThan(-8));
    });

    test('an implausible pressure is ignored, not integrated', () {
      final b = BarometerProcessor();
      b.add(pressureHpa: pressureAt(0), monotonicUs: 0);
      final before = b.last!.relativeAltitudeM;
      b.add(pressureHpa: 0, monotonicUs: 1000000);
      b.add(pressureHpa: double.nan, monotonicUs: 2000000);
      b.add(pressureHpa: 5000, monotonicUs: 3000000);
      expect(b.last!.relativeAltitudeM, before);
    });

    test('reset drops the reference', () {
      final b = BarometerProcessor();
      b.add(pressureHpa: pressureAt(0), monotonicUs: 0);
      expect(b.hasReference, isTrue);
      b.reset();
      expect(b.hasReference, isFalse);
      expect(b.last, isNull);
    });
  });
}
