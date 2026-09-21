import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/ai/accel_disturbance_estimator.dart';
import 'package:gatisaarth/core/nav/ai/ai_types.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

import '../support/accel_signals.dart';

/// Runs [samples] through a fresh estimator and returns every estimate.
List<DisturbanceEstimate> run(
  List<AccelSample> samples, {
  NavConfig config = NavConfig.defaults,
}) {
  final estimator = AccelDisturbanceEstimator(config: config);
  return [for (final s in samples) estimator.add(s.accel, s.us)];
}

/// The estimate at the end of a stream.
DisturbanceEstimate last(List<AccelSample> samples) => run(samples).last;

final _up = Vector3(0.3, 2.0, 9.6).normalized();
final _h1 = horizontalAxes(_up).$1;

void main() {
  group('what is not a disturbance', () {
    test('a smooth cruise scores zero, is LOW and keeps full quality', () {
      final e = last(synthAccel(seconds: 6));
      expect(e.vibrationScore, lessThan(0.02));
      expect(e.vibrationClass, DisturbanceClass.low);
      expect(e.motionQuality, greaterThan(0.98));
      expect(e.shock, ShockKind.none);
      expect(e.source, EstimateSource.statistical);
    });

    test('a driver braking and pulling away is a manoeuvre, not vibration',
        () {
      // 0 -> -2.5 m/s^2 over 1 s, held, then back: the slow, low-frequency
      // content the high-pass exists to leave alone.
      final e = last(synthAccel(
        seconds: 8,
        extra: (i, t) {
          final ramp = t < 1 ? t : (t < 5 ? 1.0 : math.max(0.0, 6 - t));
          return _h1 * (-2.5 * ramp);
        },
      ));
      expect(e.vibrationScore, lessThan(0.1));
      expect(e.vibrationClass, DisturbanceClass.low);
      expect(e.shock, ShockKind.none);
    });

    test('a steady 2 m/s^2 is invisible once it has settled', () {
      final samples = synthAccel(
        seconds: 10,
        extra: (i, t) => _h1 * math.min(2.0, t * 2.0),
      );
      final estimates = run(samples);
      expect(estimates.last.vibrationScore, lessThan(0.02));
    });
  });

  group('vibration', () {
    test('engine idle: a 20 Hz shudder reads as measurable and NORMAL', () {
      final e = last(synthAccel(
        seconds: 8,
        extra: (i, t) => _up * (0.45 * math.sin(2 * math.pi * 20 * t)),
      ));
      expect(e.vibrationScore, inInclusiveRange(0.2, 0.6));
      expect(e.vibrationClass, DisturbanceClass.normal);
      expect(e.motionQuality, lessThan(0.95));
      expect(e.shock, ShockKind.none);
    });

    test('a rough road is HIGH and costs motion quality', () {
      final rng = math.Random(9);
      final e = last(synthAccel(
        seconds: 8,
        extra: (i, t) => _up * (1.5 * gaussian(rng)),
      ));
      expect(e.vibrationScore, greaterThan(0.6));
      expect(e.vibrationClass, DisturbanceClass.high);
      expect(e.motionQuality, lessThan(0.65));
    });

    test('the score grows with the vibration, monotonically', () {
      double scoreFor(double amplitude) => last(synthAccel(
            seconds: 8,
            extra: (i, t) =>
                _up * (amplitude * math.sin(2 * math.pi * 17 * t)),
          )).vibrationScore;
      final scores = [for (final a in [0.05, 0.2, 0.5, 1.0, 2.0]) scoreFor(a)];
      for (var i = 1; i < scores.length; i++) {
        expect(scores[i], greaterThan(scores[i - 1]));
      }
      expect(scores.first, lessThan(0.05));
      expect(scores.last, lessThan(1.0));
    });

    test('the same physics reads the same whichever way the phone is mounted',
        () {
      double score(Vector3 up) {
        final (h, _) = horizontalAxes(up);
        return last(synthAccel(
          up: up,
          seconds: 8,
          extra: (i, t) =>
              up.normalized() * (0.4 * math.sin(2 * math.pi * 15 * t)) +
              h * (0.15 * math.sin(2 * math.pi * 11 * t)),
        )).vibrationScore;
      }

      final a = score(Vector3(0, 0, 1));
      final b = score(Vector3(0.3, 2.0, 9.6));
      final c = score(Vector3(-5, 4, 2));
      expect(b, closeTo(a, 0.05));
      expect(c, closeTo(a, 0.05));
    });

    test('vibration high up in the band counts for more than the same amplitude '
        'low down', () {
      double at(double hz) => last(synthAccel(
            seconds: 8,
            extra: (i, t) => _up * (0.5 * math.sin(2 * math.pi * hz * t)),
          )).vibrationScore;
      // 3 Hz passes the first corner only; 18 Hz passes both.
      expect(at(18), greaterThan(at(3)));
    });
  });

  group('shocks', () {
    Vector3 impulse(Vector3 axis, int i, int at, int width, double size) =>
        i >= at && i < at + width ? axis * size : Vector3.zero();

    test('a sharp vertical impulse is a pothole, held, then released', () {
      final samples = synthAccel(
        seconds: 4,
        extra: (i, t) => impulse(_up, i, 100, 3, 9.5),
      );
      final estimates = run(samples);
      expect(estimates[99].shock, ShockKind.none);
      // From the impulse and for the hold after it.
      expect(estimates[101].shock, ShockKind.pothole);
      expect(estimates[110].shock, ShockKind.pothole);
      // 1.2 s hold = 60 samples at 50 Hz, from the last shocked one.
      expect(estimates[150].shock, ShockKind.pothole);
      expect(estimates[170].shock, ShockKind.none);
      expect(estimates.last.shock, ShockKind.none);
    });

    test('a shock drops motion quality for as long as it is held, then the '
        'score decays back', () {
      final samples = synthAccel(
        seconds: 8,
        extra: (i, t) => impulse(_up, i, 100, 3, 9.5),
      );
      final estimates = run(samples);
      expect(estimates[99].motionQuality, greaterThan(0.99));
      expect(estimates[110].motionQuality, lessThanOrEqualTo(0.35));
      // One pothole is not sustained violent vibration: the clipped energy
      // reads it as moderate, briefly, and not as the top of the scale.
      expect(estimates[110].vibrationScore, inInclusiveRange(0.15, 0.85));
      // After the hold the quality is only what the (decaying) energy says.
      expect(estimates[170].motionQuality, greaterThan(0.35));
      // The energy forgets on its 1 s time constant.
      expect(estimates.last.vibrationScore, lessThan(0.05));
      expect(estimates.last.motionQuality, greaterThan(0.95));
    });

    test('a gentler vertical hit is a bump, not a pothole', () {
      final samples = synthAccel(
        seconds: 3,
        extra: (i, t) => impulse(_up, i, 60, 6, 5.0),
      );
      final kinds = run(samples).map((e) => e.shock).toSet();
      expect(kinds, contains(ShockKind.bump));
      expect(kinds, isNot(contains(ShockKind.pothole)));
    });

    test('below the bump threshold nothing is flagged', () {
      final samples = synthAccel(
        seconds: 3,
        extra: (i, t) => impulse(_up, i, 60, 4, 3.0),
      );
      expect(run(samples).every((e) => e.shock == ShockKind.none), isTrue);
    });

    test('a horizontal knock is a jolt, not a bump', () {
      final samples = synthAccel(
        seconds: 3,
        extra: (i, t) => impulse(_h1, i, 60, 3, 8.0),
      );
      final kinds = run(samples).map((e) => e.shock).toSet();
      expect(kinds, contains(ShockKind.jolt));
      expect(kinds, isNot(contains(ShockKind.pothole)));
    });

    test('a shock is caught at any sample rate a phone might deliver', () {
      for (final hz in [10, 25, 50, 100, 200]) {
        final at = (hz * 2).round();
        final samples = synthAccel(
          seconds: 5,
          hz: hz,
          extra: (i, t) => impulse(_up, i, at, math.max(1, hz ~/ 25), 9.5),
        );
        final estimates = run(samples);
        expect(estimates.any((e) => e.shock == ShockKind.pothole), isTrue,
            reason: 'missed at $hz Hz');
        // ...and a smooth drive never trips it at that rate either.
        expect(
          run(synthAccel(seconds: 5, hz: hz))
              .every((e) => e.shock == ShockKind.none),
          isTrue,
          reason: 'false alarm at $hz Hz',
        );
      }
    });

    test('the thresholds are the config\'s, not the estimator\'s', () {
      // The same 5 m/s^2 hit: a bump by default, nothing if the speed-breaker
      // threshold is raised above it.
      final samples = synthAccel(
        seconds: 3,
        extra: (i, t) => impulse(_up, i, 60, 6, 5.0),
      );
      final relaxed = run(
        samples,
        config: const NavConfig(motion: MotionConfig(speedBreakerNetAccel: 8)),
      );
      expect(relaxed.every((e) => e.shock == ShockKind.none), isTrue);
    });
  });

  group('robustness', () {
    test('identical input gives identical output, and reset forgets', () {
      final samples = synthAccel(
        seconds: 4,
        extra: (i, t) => _up * (0.5 * math.sin(2 * math.pi * 17 * t)),
      );
      final a = run(samples);
      final b = run(samples);
      for (var i = 0; i < a.length; i++) {
        expect(b[i].vibrationScore, a[i].vibrationScore);
        expect(b[i].motionQuality, a[i].motionQuality);
      }
      final estimator = AccelDisturbanceEstimator();
      for (final s in samples) {
        estimator.add(s.accel, s.us);
      }
      expect(estimator.latest.vibrationScore, greaterThan(0.1));
      estimator.reset();
      expect(estimator.latest.vibrationScore, 0);
      expect(estimator.latest.motionQuality, 1);
    });

    test('non-finite samples and duplicate or backwards timestamps are '
        'ignored, not absorbed', () {
      final estimator = AccelDisturbanceEstimator();
      final base = synthAccel(seconds: 2);
      for (final s in base) {
        estimator.add(s.accel, s.us);
      }
      final before = estimator.latest;
      estimator.add(Vector3(double.nan, 0, 9.8), base.last.us + 20000);
      estimator.add(Vector3(0, double.infinity, 9.8), base.last.us + 20000);
      estimator.add(base.last.accel, base.last.us); // duplicate
      estimator.add(base.last.accel, base.first.us); // backwards
      expect(estimator.latest.vibrationScore, before.vibrationScore);
      expect(estimator.latest.shock, ShockKind.none);
    });

    test('a long gap restarts the filters instead of leaking a fake shock', () {
      final estimator = AccelDisturbanceEstimator();
      final first = synthAccel(seconds: 3, up: Vector3(0, 0, 1));
      for (final s in first) {
        estimator.add(s.accel, s.us);
      }
      // The app was backgrounded and the phone picked up: a very different
      // orientation after 5 s of nothing. That is not a pothole.
      final second = synthAccel(
        seconds: 3,
        up: Vector3(5, -3, 2),
        startUs: first.last.us + 5000000,
      );
      final kinds = <ShockKind>{};
      for (final s in second) {
        kinds.add(estimator.add(s.accel, s.us).shock);
      }
      expect(kinds, {ShockKind.none});
      expect(estimator.latest.vibrationScore, lessThan(0.05));
    });

    test('scores and qualities stay inside their ranges under abuse', () {
      final rng = math.Random(3);
      final estimator = AccelDisturbanceEstimator();
      var us = 0;
      for (var i = 0; i < 5000; i++) {
        us += 10000 + rng.nextInt(30000);
        final e = estimator.add(
          Vector3(gaussian(rng) * 40, gaussian(rng) * 40, gaussian(rng) * 40),
          us,
        );
        expect(e.vibrationScore, inInclusiveRange(0.0, 1.0));
        expect(e.motionQuality, inInclusiveRange(0.0, 1.0));
        expect(e.vibrationScore.isFinite, isTrue);
      }
    });

    test('a smooth cruise never trips a shock at any rate, thousands of '
        'samples in', () {
      final samples = synthAccel(seconds: 60, seed: 5);
      expect(run(samples).every((e) => e.shock == ShockKind.none), isTrue);
    });
  });

  group('cost', () {
    test('O(1) per sample: microseconds, flat as the stream grows', () {
      final samples = synthAccel(seconds: 400, seed: 2); // 20,000 at 50 Hz
      double microsPerSample(int count) {
        final estimator = AccelDisturbanceEstimator();
        final watch = Stopwatch()..start();
        for (var i = 0; i < count; i++) {
          final s = samples[i % samples.length];
          estimator.add(s.accel, s.us + (i ~/ samples.length) * 500000000);
        }
        watch.stop();
        return watch.elapsedMicroseconds / count;
      }

      microsPerSample(2000); // warm up the JIT
      final short = microsPerSample(20000);
      final long = microsPerSample(200000);
      // ignore: avoid_print
      print('AccelDisturbanceEstimator: ${long.toStringAsFixed(2)} us/sample '
          '(${short.toStringAsFixed(2)} us over 20k)');
      expect(long, lessThan(25));
      // Doing ten times the samples must not cost much more per sample.
      expect(long, lessThan(short * 3 + 1));
    });
  });
}
