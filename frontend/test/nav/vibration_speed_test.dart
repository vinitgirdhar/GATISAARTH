import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/math/fft.dart';
import 'package:gatisaarth/core/nav/motion/vibration_speed.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

const _wheelRadius = 0.31;
const _rateHz = 50.0;

double _wheelHz(double speed) => speed / (2 * math.pi * _wheelRadius);

/// Feeds [seconds] of vertical vibration from a car at [speed] and returns the
/// last observation. [gnss] (when given) is the GNSS speed the estimator may
/// learn from after each poll.
({VibrationSpeedObservation? obs, int us}) _drive(
  VibrationSpeedEstimator e, {
  required double speed,
  double seconds = 6,
  int startUs = 0,
  double? gnss,
  double lineAmplitude = 0.25,
  double noise = 0.15,
  int seed = 1,
}) {
  final rng = math.Random(seed);
  VibrationSpeedObservation? last;
  final n = (seconds * _rateHz).round();
  var us = startUs;
  for (var i = 0; i < n; i++) {
    us = startUs + (i * 1e6 / _rateHz).round();
    final t = us / 1e6;
    final f = _wheelHz(speed);
    final z = 9.81 +
        lineAmplitude * math.sin(2 * math.pi * f * t) +
        0.4 * lineAmplitude * math.sin(2 * math.pi * 2 * f * t + 0.7) +
        noise * (rng.nextDouble() * 2 - 1);
    e.add(verticalAccel: z, monotonicUs: us);
    if (gnss != null && i % 50 == 0) {
      e.addGnssSpeed(speedMps: gnss, monotonicUs: us);
    }
    final obs = e.poll(us);
    if (obs != null) {
      last = obs;
      if (gnss != null) e.learn(obs);
    }
  }
  return (obs: last, us: us);
}

void main() {
  group('FFT', () {
    test('finds the bin of a pure tone', () {
      const n = 64;
      final re = List<double>.generate(n, (i) => math.cos(2 * math.pi * 5 * i / n));
      final im = List<double>.filled(n, 0);
      fftInPlace(re, im);
      final power = [for (var k = 0; k < n ~/ 2; k++) re[k] * re[k] + im[k] * im[k]];
      final peak = power.indexOf(power.reduce(math.max));
      expect(peak, 5);
      expect(re[5], closeTo(n / 2, 1e-9));
    });

    test('refuses a length that is not a power of two', () {
      expect(() => fftInPlace(List.filled(6, 0.0), List.filled(6, 0.0)),
          throwsArgumentError);
    });
  });

  group('wheel-rate peak', () {
    test('tracks the rotation line of the vertical vibration', () {
      final e = VibrationSpeedEstimator();
      final r = _drive(e, speed: 15);
      expect(r.obs, isNotNull);
      expect(r.obs!.peakHz, closeTo(_wheelHz(15), 0.15));
      expect(r.obs!.prominence, greaterThan(6));
    });

    test('says nothing on a spectrum without a line', () {
      final e = VibrationSpeedEstimator();
      final r = _drive(e, speed: 15, lineAmplitude: 0, noise: 0.4);
      expect(r.obs, isNull);
    });

    test('says nothing when the phone samples too slowly to see the wheel', () {
      final e = VibrationSpeedEstimator();
      for (var i = 0; i < 60; i++) {
        final us = i * 100000; // 10 Hz, like the IO-VNBD logs
        e.add(verticalAccel: 9.81 + math.sin(i.toDouble()), monotonicUs: us);
        expect(e.poll(us), isNull);
      }
    });
  });

  group('per-vehicle scale', () {
    test('gives no speed until GNSS has taught it the wheel', () {
      final e = VibrationSpeedEstimator();
      final r = _drive(e, speed: 15);
      expect(r.obs!.speedMps, isNull);
      expect(e.trusted, isFalse);
    });

    test('learns the scale while GNSS is live, then measures a new speed', () {
      final e = VibrationSpeedEstimator();
      var t = 0;
      for (final v in [10.0, 13.0, 16.0, 19.0]) {
        t = _drive(e, speed: v, gnss: v, seconds: 8, startUs: t, seed: t).us +
            20000;
      }
      expect(e.trusted, isTrue);
      final r = _drive(e, speed: 22, seconds: 6, startUs: t);
      expect(r.obs!.speedMps, closeTo(22, 1.2));
      expect(r.obs!.sigmaMps, inInclusiveRange(0.4, 2.5));
    });

    test('a peak that hops between harmonics never earns trust', () {
      final e = VibrationSpeedEstimator();
      var t = 0;
      for (var k = 0; k < 8; k++) {
        // GNSS alternately says the line is the first and the second harmonic.
        final v = k.isEven ? 12.0 : 24.0;
        t = _drive(e, speed: 12, gnss: v, seconds: 6, startUs: t, seed: k).us +
            20000;
      }
      expect(e.trusted, isFalse);
    });
  });

  test('every threshold comes from the config', () {
    const c = VibrationSpeedConfig();
    expect(c.minHz, lessThan(c.maxHz));
    expect(c.minSampleRateHz, greaterThanOrEqualTo(2 * 10));
    expect(NavConfig.defaults.features.vibrationSpeed, isFalse);
    expect(NavConfig.live.features.vibrationSpeed, isFalse);
  });
}
