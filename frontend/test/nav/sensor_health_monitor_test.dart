import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/sensors/sensor_health.dart';

void main() {
  group('SensorHealthMonitor', () {
    HealthCheck check(SensorHealthReport r, String name) =>
        r.checks.firstWhere((c) => c.name == name);

    test('a healthy 50 Hz phone passes accelerometer/gyro/mag/rate/jitter',
        () {
      final m = SensorHealthMonitor();
      final rng = math.Random(1);
      double n(double s) => (rng.nextDouble() - 0.5) * 2 * s;
      var us = 0;
      for (var i = 0; i < 400; i++) {
        us += 20000; // 50 Hz
        m.observeImu(
          accelPhone: Vector3(n(0.05), n(0.05), -9.81 + n(0.05)),
          gyroPhone: Vector3(n(0.001), n(0.001), n(0.001)),
          magPhone: Vector3(22 + n(0.3), 3 + n(0.3), 42 + n(0.3)),
          monotonicUs: us,
        );
      }
      m.observeGnssFix(0);
      m.observeGnssFix(1000000);
      m.observeGnssFix(2000000);

      final report = m.evaluate(monotonicUs: us);
      expect(check(report, 'Accelerometer').verdict, HealthVerdict.pass);
      expect(check(report, 'Gyroscope').verdict, HealthVerdict.pass);
      expect(check(report, 'Magnetometer').verdict, HealthVerdict.pass);
      expect(check(report, 'Sampling rate').verdict, HealthVerdict.pass);
      expect(check(report, 'Timestamp jitter').verdict, HealthVerdict.pass);
      expect(check(report, 'GNSS').verdict, HealthVerdict.pass);
      expect(
        check(report, 'Gyro bias stability').verdict,
        HealthVerdict.pass,
        reason: 'the phone never moved, two stationary windows must agree',
      );
      expect(report.overall, HealthVerdict.pass);
    });

    test('nothing fed yet reports pending, not a false pass', () {
      final m = SensorHealthMonitor();
      final report = m.evaluate(monotonicUs: 0);
      expect(report.overall, HealthVerdict.pending);
      for (final c in report.checks) {
        expect(c.verdict, HealthVerdict.pending, reason: c.name);
        expect(c.value, '--');
      }
    });

    test('a 20 Hz jittery stream is degraded on rate and jitter', () {
      final m = SensorHealthMonitor();
      final rng = math.Random(2);
      var us = 0;
      for (var i = 0; i < 200; i++) {
        // ~55 ms mean interval with jitter wide enough to clearly cross the
        // excellent/good ratio thresholds, not sit on the boundary.
        us += 10000 + rng.nextInt(90000);
        m.observeImu(
          accelPhone: Vector3(0, 0, -9.81 + (rng.nextDouble() - 0.5) * 0.05),
          gyroPhone: Vector3((rng.nextDouble() - 0.5) * 0.001, 0, 0),
          monotonicUs: us,
        );
      }
      final report = m.evaluate(monotonicUs: us);
      expect(
        check(report, 'Sampling rate').verdict,
        anyOf(HealthVerdict.degraded, HealthVerdict.fail),
      );
      expect(
        check(report, 'Timestamp jitter').verdict,
        anyOf(HealthVerdict.degraded, HealthVerdict.fail),
      );
      expect(report.overall, anyOf(HealthVerdict.degraded, HealthVerdict.fail));
    });

    test('a frozen gyroscope fails', () {
      final m = SensorHealthMonitor();
      var us = 0;
      for (var i = 0; i < 80; i++) {
        us += 20000;
        m.observeImu(
          accelPhone: Vector3(0, 0, -9.81),
          // Byte-identical readings: a real MEMS never does this.
          gyroPhone: Vector3(0.01, -0.02, 0.005),
          monotonicUs: us,
        );
      }
      final report = m.evaluate(monotonicUs: us);
      expect(check(report, 'Gyroscope').verdict, HealthVerdict.fail);
      expect(report.overall, HealthVerdict.fail);
    });

    test('a 120 uT field is not Earth\'s and is flagged', () {
      final m = SensorHealthMonitor();
      final rng = math.Random(3);
      var us = 0;
      for (var i = 0; i < 80; i++) {
        us += 20000;
        m.observeImu(
          accelPhone: Vector3(0, 0, -9.81 + (rng.nextDouble() - 0.5) * 0.05),
          gyroPhone: Vector3((rng.nextDouble() - 0.5) * 0.001, 0, 0),
          magPhone: Vector3(120 + i * 0.01, 5, 10),
          monotonicUs: us,
        );
      }
      final report = m.evaluate(monotonicUs: us);
      expect(
        check(report, 'Magnetic interference').verdict,
        anyOf(HealthVerdict.degraded, HealthVerdict.fail),
      );
      expect(
        check(report, 'Magnetometer').verdict,
        anyOf(HealthVerdict.degraded, HealthVerdict.fail),
      );
    });

    test('reset clears every check back to pending', () {
      final m = SensorHealthMonitor();
      var us = 0;
      for (var i = 0; i < 80; i++) {
        us += 20000;
        m.observeImu(
          accelPhone: Vector3(0, 0, -9.81),
          gyroPhone: Vector3.zero(),
          monotonicUs: us,
        );
      }
      m.reset();
      final report = m.evaluate(monotonicUs: us);
      expect(report.overall, HealthVerdict.pending);
    });
  });
}
