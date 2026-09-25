import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/ai/ai_speed_gate.dart';
import 'package:gatisaarth/core/nav/ai/ai_types.dart';
import 'package:gatisaarth/core/nav/ai/speed_calibration.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

import '../support/accel_signals.dart' show gaussian;

/// A model that reads 15 % fast plus 0.8 m/s on this vehicle.
double _biasedModel(double v) => 1.15 * v + 0.8;

void _pair(AiSpeedGate gate, double truth, int us, math.Random rng) {
  final model = _biasedModel(truth) + 0.2 * gaussian(rng);
  gate.evaluate(
    obs: AiSpeedObservation(
        speedMps: model,
        sigmaMps: 0.5,
        monotonicUs: us,
        latencyMs: 5,
        featureZMax: 1.5,
        windowsFed: 20),
    engineUs: us,
    predictedMps: truth,
    predictedVariance: 0.09,
    applyNow: false,
    sigmaScale: 1,
  );
  gate.gradeAgainstGnss(gnssSpeedMps: truth, fixUs: us);
}

AiSpeedGate _trained(AiConfig config) {
  final gate = AiSpeedGate(config);
  final rng = math.Random(9);
  for (var i = 0; i < 150; i++) {
    final truth = 6 + 10 * (0.5 + 0.5 * math.sin(i / 12)); // 6..16 m/s
    _pair(gate, truth, 1000000 + i * 1000000, rng);
  }
  return gate;
}

void main() {
  group('SpeedCalibration', () {
    test('fits scale and offset from GNSS pairs', () {
      final c = SpeedCalibration(const AiConfig());
      for (var v = 4.0; v < 20; v += 0.25) {
        c.add(modelMps: _biasedModel(v), gnssMps: v);
      }
      expect(c.scale, closeTo(1 / 1.15, 1e-6));
      expect(c.apply(_biasedModel(12))!, closeTo(12, 1e-6));
    });

    test('is not ready before enough pairs', () {
      final c = SpeedCalibration(const AiConfig());
      c.add(modelMps: 10, gnssMps: 9);
      expect(c.apply(10), isNull);
    });

    test('a single cruising speed fits an offset only', () {
      final c = SpeedCalibration(const AiConfig());
      for (var i = 0; i < 60; i++) {
        c.add(modelMps: 12.8 + (i.isEven ? 0.05 : -0.05), gnssMps: 12);
      }
      expect(c.scale, 1.0);
      expect(c.apply(12.8)!, closeTo(12, 0.01));
    });

    test('an implausible scale is refused', () {
      final c = SpeedCalibration(const AiConfig());
      for (var v = 4.0; v < 20; v += 0.25) {
        c.add(modelMps: 3 * v, gnssMps: v);
      }
      expect(c.apply(30), isNull);
    });
  });

  group('in the gate', () {
    test('off (the default), a biased model never validates', () {
      final gate = _trained(const AiConfig(enabled: true));
      expect(gate.validated, isFalse);
    });

    test('on, the same model validates on its corrected speed', () {
      final gate = _trained(
          const AiConfig(enabled: true, perVehicleCalibration: true));
      expect(gate.validated, isTrue);
      expect(gate.validationBiasMps!.abs(), lessThan(0.3));
      final d = gate.evaluate(
        obs: const AiSpeedObservation(
            speedMps: 1.15 * 14 + 0.8,
            sigmaMps: 0.5,
            monotonicUs: 900000000,
            latencyMs: 5,
            featureZMax: 1.5,
            windowsFed: 20),
        engineUs: 900000000,
        predictedMps: 14,
        predictedVariance: 1.0,
        applyNow: true,
        sigmaScale: 1,
      );
      expect(d.applied, isTrue);
      expect(d.speedMps!, closeTo(14, 0.3));
    });
  });

  test('stays off in the live config until a replay shows it helps', () {
    expect(NavConfig.live.ai.perVehicleCalibration, isFalse);
  });
}
