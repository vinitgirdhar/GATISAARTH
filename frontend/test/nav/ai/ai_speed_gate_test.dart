import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/ai/ai_speed_gate.dart';
import 'package:gatisaarth/core/nav/ai/ai_types.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

import '../support/accel_signals.dart' show gaussian;

const _config = AiConfig(enabled: true);

AiSpeedObservation _obs({
  double speed = 10.0,
  double sigma = 0.5,
  int us = 1000000,
  double latency = 5,
  double z = 1.5,
  int windows = 20,
}) =>
    AiSpeedObservation(
      speedMps: speed,
      sigmaMps: sigma,
      monotonicUs: us,
      latencyMs: latency,
      featureZMax: z,
      windowsFed: windows,
    );

/// One prediction seen while GNSS is healthy, then a fix at the same instant
/// reporting a Doppler speed of [gnss]: what the engine does once per second.
void _gradedPair(
  AiSpeedGate gate, {
  required double speed,
  required double gnss,
  required int us,
  double z = 1.5,
  int windows = 20,
}) {
  gate.evaluate(
    obs: _obs(speed: speed, us: us, z: z, windows: windows),
    engineUs: us,
    predictedMps: gnss,
    predictedVariance: 0.09,
    applyNow: false,
    sigmaScale: 1,
  );
  gate.gradeAgainstGnss(gnssSpeedMps: gnss, fixUs: us);
}

/// A gate whose model has already earned its place: 100 predictions that agreed
/// with the GNSS Doppler speed while GNSS was healthy.
AiSpeedGate _validatedGate([AiConfig config = _config]) {
  final gate = AiSpeedGate(config);
  final rng = math.Random(4);
  for (var i = 0; i < 100; i++) {
    _gradedPair(gate,
        speed: 10 + 0.3 * gaussian(rng), gnss: 10, us: 1000000 + i * 100000);
  }
  expect(gate.validated, isTrue, reason: 'the fixture must start validated');
  return gate;
}

AiSpeedDecision _inOutage(
  AiSpeedGate gate,
  AiSpeedObservation obs, {
  double predicted = 10,
  double variance = 0.25,
  double scale = 1,
  int? engineUs,
}) =>
    gate.evaluate(
      obs: obs,
      engineUs: engineUs ?? obs.monotonicUs,
      predictedMps: predicted,
      predictedVariance: variance,
      applyNow: true,
      sigmaScale: scale,
    );

void main() {
  const late0 = 100000000; // after the fixture's timestamps

  group('accepting', () {
    test('a clean observation is applied, with the model\'s own sigma', () {
      final gate = _validatedGate();
      final d = _inOutage(gate, _obs(speed: 10.4, sigma: 0.6, us: late0));
      expect(d.applied, isTrue);
      expect(d.sigmaUsedMps, closeTo(0.6, 1e-12));
      expect(d.innovationMps, closeTo(0.4, 1e-12));
      expect(gate.applied, 1);
    });

    test('a sigma below the floor is raised to it: an overconfident head must '
        'not dominate', () {
      final gate = _validatedGate();
      final d = _inOutage(gate, _obs(sigma: 0.05, us: late0));
      expect(d.sigmaUsedMps, closeTo(_config.floorSigma, 1e-12));
    });

    test('a disturbance scale widens the sigma the filter is given', () {
      final gate = _validatedGate();
      final d = _inOutage(gate, _obs(sigma: 0.6, us: late0), scale: 2);
      expect(d.sigmaUsedMps, closeTo(1.2, 1e-12));
    });
  });

  group('each gate has its own reason', () {
    late AiSpeedGate gate;
    setUp(() => gate = _validatedGate());

    void expectRejected(AiSpeedDecision d, AiRejectReason reason) {
      expect(d.rejected, isTrue);
      expect(d.reason, reason);
      expect(gate.rejected[reason], 1);
      expect(gate.lastReject, reason);
    }

    test('non-finite, negative and zero-sigma observations are invalid', () {
      for (final bad in [
        _obs(speed: double.nan, us: late0),
        _obs(speed: -1, us: late0 + 1),
        _obs(sigma: 0, us: late0 + 2),
        _obs(sigma: double.nan, us: late0 + 3),
        _obs(z: double.nan, us: late0 + 4),
        _obs(latency: double.infinity, us: late0 + 5),
      ]) {
        expect(_inOutage(gate, bad).reason, AiRejectReason.invalid,
            reason: '$bad');
      }
      expect(gate.rejected[AiRejectReason.invalid], 6);
    });

    test('a timestamp that is not newer is out of order', () {
      expect(_inOutage(gate, _obs(us: late0)).applied, isTrue);
      expectRejected(
          _inOutage(gate, _obs(us: late0)), AiRejectReason.outOfOrder);
    });

    test('an older timestamp is out of order too', () {
      _inOutage(gate, _obs(us: late0));
      expectRejected(
          _inOutage(gate, _obs(us: late0 - 100000)), AiRejectReason.outOfOrder);
    });

    test('too few windows is warm-up', () {
      expectRejected(_inOutage(gate, _obs(windows: 9, us: late0)),
          AiRejectReason.warmup);
      expect(_inOutage(gate, _obs(windows: 10, us: late0 + 1)).applied, isTrue);
    });

    test('slow inference is dropped: a late velocity is worse than none', () {
      expectRejected(_inOutage(gate, _obs(latency: 41, us: late0)),
          AiRejectReason.latency);
      expect(_inOutage(gate, _obs(latency: 40, us: late0 + 1)).applied, isTrue);
    });

    test('an observation that sat in a queue counts its age as latency', () {
      // 5 ms of inference, then 50 ms before the engine saw it.
      expectRejected(
        _inOutage(gate, _obs(latency: 5, us: late0), engineUs: late0 + 50000),
        AiRejectReason.latency,
      );
    });

    test('an observation stamped slightly ahead of the engine is not "old"',
        () {
      // Stamped 20 ms in the future of the last IMU frame: age is zero.
      final d = _inOutage(gate, _obs(us: late0), engineUs: late0 - 20000);
      expect(d.applied, isTrue);
    });

    test('an input window off the training distribution is not believed', () {
      expectRejected(_inOutage(gate, _obs(z: 6.5, us: late0)),
          AiRejectReason.offDistribution);
      expect(_inOutage(gate, _obs(z: 6.0, us: late0 + 1)).applied, isTrue);
    });

    test('a speed beyond max is over-speed', () {
      expectRejected(_inOutage(gate, _obs(speed: 45.5, us: late0), predicted: 45),
          AiRejectReason.overSpeed);
    });

    test('a model that never earned its place is unvalidated', () {
      final fresh = AiSpeedGate(_config);
      final d = _inOutage(fresh, _obs(us: late0));
      expect(d.reason, AiRejectReason.unvalidated);
      expect(fresh.rejected[AiRejectReason.unvalidated], 1);
    });

    test('an innovation beyond the combined sigmas is disagreement', () {
      // predicted 10, variance 0.25, model sigma 0.5: combined sqrt(0.5).
      final combined = math.sqrt(0.25 + 0.25);
      expect(
        _inOutage(gate, _obs(speed: 10 + 3.9 * combined, us: late0)).applied,
        isTrue,
      );
      expectRejected(
        _inOutage(gate, _obs(speed: 10 + 4.1 * combined, us: late0 + 1)),
        AiRejectReason.physicsDisagreement,
      );
    });

    test('the disagreement is symmetric: too slow is refused as well', () {
      final combined = math.sqrt(0.5);
      expect(
        _inOutage(gate, _obs(speed: 10 - 4.5 * combined, us: late0)).reason,
        AiRejectReason.physicsDisagreement,
      );
    });

    test('an uncertain INS forgives more disagreement than a certain one', () {
      final wide = _validatedGate();
      final tight = _validatedGate();
      final o1 = _obs(speed: 13, us: late0);
      final o2 = _obs(speed: 13, us: late0);
      expect(_inOutage(wide, o1, variance: 4).applied, isTrue);
      expect(_inOutage(tight, o2, variance: 0.04).reason,
          AiRejectReason.physicsDisagreement);
    });

    test('the disturbance-inflated sigma counts towards agreement, so a shaken '
        'phone is harder to contradict', () {
      final strict = _validatedGate();
      final shaken = _validatedGate();
      final o = _obs(speed: 13, us: late0);
      expect(_inOutage(strict, o).reason, AiRejectReason.physicsDisagreement);
      expect(_inOutage(shaken, o, scale: 4).applied, isTrue);
    });
  });

  group('the contribution clamp', () {
    test('a gain above the ceiling is brought down to it, by widening sigma',
        () {
      final gate = _validatedGate();
      // P = 4, R = 0.25: the gain would be 0.94.
      final d = _inOutage(gate, _obs(us: late0), variance: 4);
      const p = 4.0;
      final sigma = d.sigmaUsedMps!;
      expect(p / (p + sigma * sigma), closeTo(_config.maxContribution, 1e-9));
      expect(sigma, greaterThan(0.5));
    });

    test('a gain already inside the range leaves the sigma alone, exactly', () {
      final gate = _validatedGate();
      final d = _inOutage(gate, _obs(sigma: 0.6, us: late0), variance: 0.25);
      expect(d.sigmaUsedMps, 0.6);
    });

    test('a floor on the gain shrinks a very wide sigma to it', () {
      final gate = _validatedGate(
          const AiConfig(enabled: true, minContribution: 0.3));
      // P = 0.25, sigma 2.0: gain 0.058, well under 0.3.
      final d = _inOutage(gate, _obs(sigma: 2.0, us: late0));
      const p = 0.25;
      final sigma = d.sigmaUsedMps!;
      expect(p / (p + sigma * sigma), closeTo(0.3, 1e-9));
    });
  });

  group('validation against the GNSS-anchored speed', () {
    AiSpeedGate feed(double Function(math.Random) error, {int n = 100}) {
      final gate = AiSpeedGate(_config);
      final rng = math.Random(11);
      for (var i = 0; i < n; i++) {
        _gradedPair(gate,
            speed: 10 + error(rng), gnss: 10, us: 1000000 + i * 100000);
      }
      return gate;
    }

    test('an honest model validates, against the GNSS speed and nothing '
        'else', () {
      final gate = feed((rng) => 0.4 * gaussian(rng));
      expect(gate.validated, isTrue);
      expect(gate.validationRmseMps, closeTo(0.4, 0.15));
      expect(gate.validationBiasMps!.abs(), lessThan(0.2));
    });

    test('a biased model does not, however quiet it is', () {
      final gate = feed((rng) => 2.0 + 0.1 * gaussian(rng));
      expect(gate.validated, isFalse);
      expect(gate.validationBiasMps, closeTo(2.0, 0.1));
    });

    test('a bias just inside the limit validates and just outside does not',
        () {
      expect(feed((rng) => 0.2 + 0.05 * gaussian(rng)).validated, isTrue);
      expect(feed((rng) => 0.4 + 0.05 * gaussian(rng)).validated, isFalse);
    });

    test('a noisy model does not validate either', () {
      final gate = feed((rng) => 1.6 * gaussian(rng));
      expect(gate.validated, isFalse);
      expect(gate.validationRmseMps!, greaterThan(_config.validationMaxRmse));
    });

    test('a model must be seen for a while first', () {
      final gate = feed((rng) => 0.1 * gaussian(rng),
          n: _config.validationMinSamples - 1);
      expect(gate.validated, isFalse);
      final more = feed((rng) => 0.1 * gaussian(rng),
          n: _config.validationMinSamples);
      expect(more.validated, isTrue);
    });

    test('a model that goes bad loses its standing within its window', () {
      final gate = _validatedGate();
      var us = 200000000;
      final rng = math.Random(2);
      for (var i = 0; i < 80; i++) {
        us += 100000;
        _gradedPair(gate, speed: 13 + 0.1 * gaussian(rng), gnss: 10, us: us);
      }
      expect(gate.validated, isFalse);
    });

    test('the record is frozen during an outage: the INS is the thing being '
        'distrusted then, so it cannot grade the model', () {
      final gate = _validatedGate();
      final before = gate.validationRmseMps;
      var us = late0;
      for (var i = 0; i < 200; i++) {
        us += 100000;
        _inOutage(gate, _obs(speed: 14, us: us, sigma: 3), variance: 50);
      }
      expect(gate.validationRmseMps, before);
      expect(gate.validated, isTrue);
      // Nothing was held back for grading, so even a stray fix grades nothing.
      gate.gradeAgainstGnss(gnssSpeedMps: 3, fixUs: us);
      expect(gate.validationRmseMps, before);
    });

    test('observations that fail the data checks never grade the model', () {
      final gate = AiSpeedGate(_config);
      for (var i = 0; i < 200; i++) {
        _gradedPair(gate,
            speed: 10, gnss: 10, us: 1000000 + i * 100000, windows: 3);
      }
      expect(gate.validated, isFalse);
      expect(gate.rejected[AiRejectReason.warmup], 200);
      expect(gate.validationRmseMps, isNull);
    });

    test('validated-only observations are counted as such and change nothing',
        () {
      final gate = AiSpeedGate(_config);
      final d = gate.evaluate(
        obs: _obs(speed: 10.3, us: 1000000),
        engineUs: 1000000,
        predictedMps: 10,
        predictedVariance: 0.09,
        applyNow: false,
        sigmaScale: 1,
      );
      expect(d.outcome, AiSpeedOutcome.validatedOnly);
      expect(d.innovationMps, closeTo(0.3, 1e-12));
      expect(gate.validatedOnly, 1);
      expect(gate.applied, 0);
      expect(gate.rejectedTotal, 0);
      // Held for grading, not graded: only a fix can do that.
      expect(gate.validationRmseMps, isNull);
    });

    test('a fix grades the newest prediction if it is close enough in time, '
        'and only once', () {
      final gate = AiSpeedGate(_config);
      gate.evaluate(
        obs: _obs(speed: 10.5, us: 1000000),
        engineUs: 1000000,
        predictedMps: 10,
        predictedVariance: 0.09,
        applyNow: false,
        sigmaScale: 1,
      );
      // 300 ms away is another moment: the vehicle may have accelerated.
      gate.gradeAgainstGnss(gnssSpeedMps: 10, fixUs: 1300000);
      expect(gate.validationRmseMps, isNull);
      gate.gradeAgainstGnss(gnssSpeedMps: 10, fixUs: 1200000);
      expect(gate.validationBiasMps, closeTo(0.5, 1e-12));
      // The same prediction is not graded again by the next fix.
      gate.gradeAgainstGnss(gnssSpeedMps: 10, fixUs: 1210000);
      expect(gate.validationBiasMps, closeTo(0.5, 1e-12));
    });

    test('only the newest prediction is held: an older one is not graded late',
        () {
      final gate = AiSpeedGate(_config);
      for (final us in [1000000, 1100000]) {
        gate.evaluate(
          obs: _obs(speed: us == 1000000 ? 20 : 10, us: us),
          engineUs: us,
          predictedMps: 10,
          predictedVariance: 0.09,
          applyNow: false,
          sigmaScale: 1,
        );
      }
      gate.gradeAgainstGnss(gnssSpeedMps: 10, fixUs: 1150000);
      expect(gate.validationBiasMps, closeTo(0, 1e-12));
    });

    test('a GNSS speed that is not a speed grades nothing', () {
      final gate = AiSpeedGate(_config);
      gate.evaluate(
        obs: _obs(us: 1000000),
        engineUs: 1000000,
        predictedMps: 10,
        predictedVariance: 0.09,
        applyNow: false,
        sigmaScale: 1,
      );
      gate.gradeAgainstGnss(gnssSpeedMps: double.nan, fixUs: 1000000);
      gate.gradeAgainstGnss(gnssSpeedMps: -1, fixUs: 1000000);
      expect(gate.validationRmseMps, isNull);
      gate.gradeAgainstGnss(gnssSpeedMps: 10, fixUs: 1000000);
      expect(gate.validationRmseMps, isNotNull);
    });

    test('the INS is not the reference: a model that agrees with the GNSS '
        'validates however wrong the INS is', () {
      final gate = AiSpeedGate(_config);
      for (var i = 0; i < 60; i++) {
        final us = 1000000 + i * 100000;
        gate.evaluate(
          obs: _obs(speed: 10, us: us),
          engineUs: us,
          predictedMps: 7, // an INS lagging 3 m/s behind
          predictedVariance: 0.09,
          applyNow: false,
          sigmaScale: 1,
        );
        gate.gradeAgainstGnss(gnssSpeedMps: 10, fixUs: us);
      }
      expect(gate.validated, isTrue);
    });
  });

  group('bookkeeping', () {
    test('every observation is counted exactly once', () {
      final gate = _validatedGate();
      final before = gate.observed;
      _inOutage(gate, _obs(us: late0)); // applied
      _inOutage(gate, _obs(us: late0 + 1, z: 9)); // rejected
      gate.evaluate(
        obs: _obs(us: late0 + 2),
        engineUs: late0 + 2,
        predictedMps: 10,
        predictedVariance: 0.1,
        applyNow: false,
        sigmaScale: 1,
      ); // validated only
      expect(gate.observed - before, 3);
      expect(gate.applied + gate.validatedOnly + gate.rejectedTotal,
          gate.observed);
    });

    test('the engine can record refusals the gate never sees', () {
      final gate = AiSpeedGate(_config);
      gate.reject(AiRejectReason.disabled, _obs());
      gate.reject(AiRejectReason.notReady, _obs());
      gate.reject(AiRejectReason.filterRefused, _obs());
      expect(gate.observed, 3);
      expect(gate.rejected[AiRejectReason.notReady], 1);
      expect(gate.lastReject, AiRejectReason.filterRefused);
    });

    test('the published counters cannot be mutated from outside', () {
      final gate = _validatedGate();
      expect(() => gate.rejected[AiRejectReason.warmup] = 5,
          throwsUnsupportedError);
    });

    test('reset forgets everything, including the model\'s standing', () {
      final gate = _validatedGate();
      _inOutage(gate, _obs(us: late0, z: 9));
      gate.reset();
      expect(gate.observed, 0);
      expect(gate.validated, isFalse);
      expect(gate.rejectedTotal, 0);
      expect(gate.lastReject, isNull);
    });
  });
}
