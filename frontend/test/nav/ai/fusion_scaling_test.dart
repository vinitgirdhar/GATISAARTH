import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/ai/ai_fusion.dart';
import 'package:gatisaarth/core/nav/ai/ai_types.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

const _config = NavConfig(ai: AiConfig(enabled: true));
const _d = DisturbanceConfig();
const _ai = AiConfig(enabled: true);

DisturbanceEstimate _est({
  double v = 0,
  double q = 1,
  int us = 0,
  ShockKind shock = ShockKind.none,
}) =>
    DisturbanceEstimate(
      vibrationScore: v,
      vibrationClass: DisturbanceClass.normal,
      motionQuality: q,
      monotonicUs: us,
      shock: shock,
    );

void main() {
  group('the formulas of ml/README.md', () {
    test('R = R0 (1 + 2 V) / Q and Qins = Q0 (1 + 1.5 V) / Q, exactly', () {
      final e = _est(v: 0.5, q: 0.8);
      expect(e.measurementNoiseScale(_d), closeTo((1 + 2 * 0.5) / 0.8, 1e-12));
      expect(e.processNoiseScale(_d), closeTo((1 + 1.5 * 0.5) / 0.8, 1e-12));
    });

    test('a calm, trustworthy estimate scales nothing: exactly 1', () {
      final e = _est();
      expect(e.measurementNoiseScale(_d), 1.0);
      expect(e.processNoiseScale(_d), 1.0);
    });

    test('quality is floored, so zero cannot make a noise term infinite', () {
      final e = _est(v: 0.5, q: 0);
      expect(e.measurementNoiseScale(_d), closeTo(2 / _d.minMotionQuality, 1e-12));
      expect(_est(q: -3).measurementNoiseScale(_d),
          _est(q: 0).measurementNoiseScale(_d));
    });

    test('both scales are capped', () {
      const tight = DisturbanceConfig(maxMeasurementScale: 4, maxProcessScale: 3);
      final worst = _est(v: 1, q: 0);
      expect(worst.measurementNoiseScale(tight), 4);
      expect(worst.processNoiseScale(tight), 3);
      // With the defaults the worst case is (1 + 2) / 0.25 = 12 and the process
      // noise, (1 + 1.5) / 0.25 = 10, is held to its cap of 8.
      expect(worst.measurementNoiseScale(_d), closeTo(12, 1e-12));
      expect(worst.processNoiseScale(_d), _d.maxProcessScale);
    });

    test('a scale never goes below 1: the model can distrust, not over-trust',
        () {
      // Out-of-range inputs: a quality above 1 and a negative score.
      expect(_est(q: 5).measurementNoiseScale(_d), 1.0);
      expect(_est(v: -1).measurementNoiseScale(_d), 1.0);
    });

    test('non-finite outputs from a broken model are neutral, not NaN', () {
      for (final bad in [double.nan, double.infinity, double.negativeInfinity]) {
        final e = _est(v: bad, q: bad);
        expect(e.measurementNoiseScale(_d).isFinite, isTrue);
        expect(e.processNoiseScale(_d).isFinite, isTrue);
        expect(e.measurementNoiseScale(_d), greaterThanOrEqualTo(1));
      }
    });

    test('the scale is monotonic in both arguments', () {
      double r(double v, double q) => _est(v: v, q: q).measurementNoiseScale(_d);
      expect(r(0.6, 0.9), greaterThan(r(0.3, 0.9)));
      expect(r(0.3, 0.5), greaterThan(r(0.3, 0.9)));
    });
  });

  group('fusion confidence', () {
    test('GNSS trust divides the variance: the sigma scales by 1/sqrt(trust)',
        () {
      expect(const FusionConfidence(gnssTrust: 0.25).gnssSigmaScale(_ai),
          closeTo(2.0, 1e-12));
      expect(const FusionConfidence().gnssSigmaScale(_ai), 1.0);
    });

    test('trust is floored and capped: a model can soften a sensor, not '
        'silence it, and cannot claim more than it was given', () {
      expect(const FusionConfidence(gnssTrust: 0.0).gnssSigmaScale(_ai),
          closeTo(1 / math.sqrt(_ai.minGnssTrust), 1e-12));
      expect(const FusionConfidence(gnssTrust: 7).gnssSigmaScale(_ai), 1.0);
      expect(const FusionConfidence(insTrust: 0).effectiveInsTrust(_ai),
          _ai.minInsTrust);
      expect(const FusionConfidence(insTrust: 3).effectiveInsTrust(_ai), 1.0);
      expect(
          const FusionConfidence(gnssTrust: double.nan).gnssSigmaScale(_ai), 1);
    });

    test('a fresh model INS trust replaces the motion quality in the process '
        'noise: the same thing is never divided by twice', () {
      final e = _est(v: 0.8, q: 0.5);
      expect(e.processNoiseScale(_d), closeTo((1 + 1.2) / 0.5, 1e-12));
      expect(e.processNoiseScale(_d, insTrust: 0.5),
          e.processNoiseScale(_d)); // same 0.5, so the same: not 0.25
      expect(e.processNoiseScale(_d, insTrust: 1.0), closeTo(2.2, 1e-12));
    });
  });

  group('the engine-side bookkeeping (AiFusion)', () {
    late AiFusion fusion;
    setUp(() => fusion = AiFusion(_config));

    test('nothing said, nothing scaled', () {
      final s = fusion.scales(1000000);
      expect(s.measurementVariance, closeTo(1, 0.02));
      expect(s.processNoise, closeTo(1, 0.02));
      expect(s.gnssSigma, 1.0);
      expect(s.holdUpdates, isFalse);
      expect(fusion.gnssSigmaScale(1000000), 1.0);
    });

    test('disabled is exactly neutral, whatever the models say', () {
      final off = AiFusion(const NavConfig());
      off.setModelDisturbance(_est(v: 1, q: 0.1, shock: ShockKind.pothole));
      off.setFusionConfidence(const FusionConfidence(gnssTrust: 0.2));
      final s = off.scales(0);
      expect(identical(s, AiScales.neutral), isTrue);
      expect(off.gnssSigmaScale(0), 1.0);
      expect(identical(off.diagnostics(0), AiDiagnostics.off), isTrue);
    });

    test('a model estimate drives the scales while it is fresh', () {
      fusion.setModelDisturbance(_est(v: 0.8, q: 0.5, us: 1000000));
      final s = fusion.scales(1500000);
      expect(s.measurementVariance, closeTo(5.2, 1e-9));
      expect(s.processNoise, closeTo(4.4, 1e-9));
      expect(s.measurementSigma, closeTo(math.sqrt(5.2), 1e-9));
    });

    test('...and the statistical estimate takes over when it is not', () {
      fusion.setModelDisturbance(_est(v: 0.8, q: 0.5, us: 1000000));
      final stale = 1000000 + _ai.modelOutputTtl.inMicroseconds + 1;
      final s = fusion.scales(stale);
      expect(s.measurementVariance, closeTo(1, 0.02));
      expect(fusion.effectiveDisturbance(stale).source,
          EstimateSource.statistical);
      expect(fusion.effectiveDisturbance(1500000).source, EstimateSource.model);
    });

    test('a model estimate is clamped to its range and non-finite ones are '
        'ignored', () {
      fusion.setModelDisturbance(_est(v: 5, q: -2, us: 10));
      final e = fusion.effectiveDisturbance(10);
      expect(e.vibrationScore, 1.0);
      expect(e.motionQuality, 0.0);
      final before = fusion.effectiveDisturbance(20);
      fusion.setModelDisturbance(_est(v: double.nan, q: 0.5, us: 20));
      expect(fusion.effectiveDisturbance(20).vibrationScore,
          before.vibrationScore);
    });

    test('an older estimate never overwrites a newer one', () {
      fusion.setModelDisturbance(_est(v: 0.9, q: 0.3, us: 5000));
      fusion.setModelDisturbance(_est(v: 0.0, q: 1.0, us: 1000));
      expect(fusion.effectiveDisturbance(5000).vibrationScore, 0.9);
    });

    test('a shock seen statistically holds updates even when the model says '
        'calm: holding too much is the safe error', () {
      // Feed the fallback a pothole (9.5 m/s^2 impulse on a level phone).
      for (var i = 0; i < 100; i++) {
        fusion.observeAccel(Vector3(0, 0, 9.8), 1000000 + i * 20000);
      }
      for (var i = 100; i < 103; i++) {
        fusion.observeAccel(Vector3(0, 0, 19.3), 1000000 + i * 20000);
      }
      final now = 1000000 + 103 * 20000;
      fusion.setModelDisturbance(_est(v: 0.05, q: 0.99, us: now));
      final s = fusion.scales(now);
      expect(s.holdUpdates, isTrue);
      expect(fusion.effectiveDisturbance(now).source, EstimateSource.model);
      expect(fusion.effectiveDisturbance(now).shock, isNot(ShockKind.none));
    });

    test('a model shock is held for the configured time, then released', () {
      fusion.setModelDisturbance(
          _est(v: 0.3, q: 0.6, us: 1000000, shock: ShockKind.bump));
      expect(fusion.scales(1000000 + 500000).holdUpdates, isTrue);
      final after = 1000000 + _d.shockHold.inMicroseconds + 1;
      expect(fusion.scales(after).holdUpdates, isFalse);
    });

    test('GNSS trust reaches the GNSS sigma, and expires', () {
      fusion.setFusionConfidence(
          const FusionConfidence(gnssTrust: 0.25, monotonicUs: 1000000));
      expect(fusion.gnssSigmaScale(1000000), closeTo(2.0, 1e-12));
      expect(fusion.scales(1000000).gnssSigma, closeTo(2.0, 1e-12));
      expect(fusion.gnssSigmaScale(
              1000000 + _ai.modelOutputTtl.inMicroseconds + 1),
          1.0);
    });

    test('INS trust with no disturbance model is 1/trust on the process noise',
        () {
      final only = AiFusion(const NavConfig(
          ai: AiConfig(enabled: true, disturbanceAdaptation: false)));
      only.setFusionConfidence(
          const FusionConfidence(insTrust: 0.5, monotonicUs: 10));
      final s = only.scales(10);
      expect(s.processNoise, closeTo(2.0, 1e-12));
      expect(s.measurementVariance, 1.0);
    });

    test('the sub-switches are independent', () {
      final gnssOnly = AiFusion(const NavConfig(
          ai: AiConfig(
              enabled: true,
              speedMeasurement: false,
              disturbanceAdaptation: false)));
      gnssOnly.setModelDisturbance(_est(v: 1, q: 0.1, us: 10));
      gnssOnly.setFusionConfidence(
          const FusionConfidence(gnssTrust: 0.25, monotonicUs: 10));
      final s = gnssOnly.scales(10);
      expect(s.measurementVariance, 1.0);
      expect(s.processNoise, 1.0);
      expect(s.holdUpdates, isFalse);
      expect(s.gnssSigma, closeTo(2.0, 1e-12));

      final noFusion = AiFusion(const NavConfig(
          ai: AiConfig(enabled: true, fusionTrust: false)));
      noFusion.setFusionConfidence(
          const FusionConfidence(gnssTrust: 0.25, monotonicUs: 10));
      expect(noFusion.scales(10).gnssSigma, 1.0);
      expect(noFusion.gnssSigmaScale(10), 1.0);
    });

    test('the diagnostics report the factors that are actually applied', () {
      fusion.setModelDisturbance(_est(v: 0.8, q: 0.5, us: 100));
      fusion.setFusionConfidence(
          const FusionConfidence(gnssTrust: 0.5, insTrust: 0.5, monotonicUs: 100));
      final d = fusion.diagnostics(100);
      expect(d.enabled, isTrue);
      expect(d.measurementNoiseScale, closeTo(5.2, 1e-9));
      expect(d.processNoiseScale, closeTo(4.4, 1e-9));
      expect(d.gnssSigmaScale, closeTo(math.sqrt(2), 1e-9));
      expect(d.disturbance!.source, EstimateSource.model);
      expect(d.fusion!.gnssTrust, 0.5);
      expect(d.summary, contains('fusion'));
    });
  });
}
