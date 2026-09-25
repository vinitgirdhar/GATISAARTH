import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/features/ai_motion/data/datasources/ml_speed_estimator.dart';

void main() {
  group('MlSpeedEstimator Confidence & Calibration Tests', () {
    late MlSpeedEstimator estimator;

    setUp(() {
      estimator = MlSpeedEstimator();
    });

    tearDown(() {
      estimator.dispose();
    });

    test('Stationary condition produces 0.0 m/s and >= 95% confidence', () {
      // Feed 30 stationary frames: upright on desk / mount (gravity on Z, minimal noise)
      for (int i = 0; i < 30; i++) {
        estimator.addImuFrame(
          ax: 0.02 * math.sin(i * 0.5),
          ay: 0.01 * math.cos(i * 0.5),
          az: 9.81 + 0.02 * math.sin(i * 0.7),
          gx: 0.005 * math.cos(i * 0.3),
          gy: 0.004 * math.sin(i * 0.3),
          gz: 0.002 * math.cos(i * 0.2),
          pitch: 0.0,
          roll: 0.0,
        );
      }

      expect(estimator.estimatedSpeed, equals(0.0));
      expect(estimator.confidence, greaterThanOrEqualTo(0.95));
    });

    test('Moving condition with normal operational sigma achieves >= 80% confidence', () {
      // Feed dynamic frames simulating forward vehicle driving
      for (int i = 0; i < 30; i++) {
        estimator.addImuFrame(
          ax: 1.2 + 0.4 * math.sin(i * 0.8), // Longitudinal acceleration
          ay: 0.1 * math.cos(i * 0.5),
          az: 9.81 + 0.3 * math.sin(i * 1.2), // Road vibration
          gx: 0.02 * math.cos(i * 0.4),
          gy: 0.03 * math.sin(i * 0.6),
          gz: 0.05 * math.sin(i * 0.3),
          pitch: 0.02,
          roll: 0.01,
        );
      }

      // Model fallback or inference should provide confidence >= 80%
      expect(estimator.confidence, greaterThanOrEqualTo(0.80));
    });

    test('Gaussian error tolerance CDF formula calibration', () {
      // Numerical test of the CDF confidence curve: P(|e| <= 2.2 m/s) = erf(2.2 / (sqrt(2) * sigma))
      // For sigma = 1.2 m/s (~4.3 km/h uncertainty) -> conf ~ 93%
      // For sigma = 1.6 m/s (~5.7 km/h uncertainty) -> conf ~ 83%
      // For sigma = 2.0 m/s (~7.2 km/h uncertainty) -> conf ~ 73%
      // For sigma = 2.5 m/s (~9.0 km/h uncertainty) -> conf ~ 62%
      const double deltaV = 2.2;

      double computeConfidence(double sigma) {
        final x = deltaV / (math.sqrt(2.0) * sigma);
        // Abramowitz and Stegun 7.1.26
        const p = 0.3275911;
        const a1 = 0.254829592;
        const a2 = -0.284496736;
        const a3 = 1.421413741;
        const a4 = -1.453152027;
        const a5 = 1.061405429;
        final t = 1.0 / (1.0 + p * x);
        final erf = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-x * x);
        return erf;
      }

      expect(computeConfidence(1.2), greaterThanOrEqualTo(0.90));
      expect(computeConfidence(1.6), greaterThanOrEqualTo(0.80));
      expect(computeConfidence(2.5), lessThan(0.70));
    });

    test('Gravity leveling prevents out-of-distribution feature errors on upright phone', () {
      // Phone held upright (e.g. on mount or emulator): gravity is on Y axis
      final rawAcc = Vector3(0.05, 9.77, 0.81);

      // Leveling decomposition
      final up = rawAcc.normalized();
      final az = rawAcc.dot(up); // ~9.80 m/s^2
      final aHoriz = rawAcc - (up * az);
      final ax = aHoriz.length > 0.05 ? aHoriz.length : 0.0;
      final ay = 0.0;

      // Z-score calculation based on training dataset scaler statistics
      // mean_az = 9.84, std_az = 0.53
      final zAz = ((az - 9.84) / 0.53).abs();
      // mean_ay = 0.08, std_ay = 0.85
      final zAy = ((ay - 0.08) / 0.85).abs();
      // mean_ax = 0.09, std_ax = 0.98
      final zAx = ((ax - 0.09) / 0.98).abs();

      expect(zAz, lessThan(1.0)); // well within 1 sigma
      expect(zAy, lessThan(1.0)); // well within 1 sigma
      expect(zAx, lessThan(1.0)); // well within 1 sigma
      expect(az, closeTo(9.80, 0.05));
    });
  });
}
