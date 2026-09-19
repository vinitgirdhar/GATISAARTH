import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/model/nav_snapshot.dart';

import 'support/drift_evaluator.dart';
import 'support/drive_simulator.dart';

/// Ground-truth drift benchmark (§39, §76).
///
/// **What this is:** the engine scored against a simulator's own truth, with
/// explicitly modelled sensor error — constant accelerometer and gyroscope
/// biases plus noise, a realistic mount, 1 Hz GNSS with 5 m accuracy.
///
/// **What this is not:** a field measurement. Real phones have temperature
/// drift, non-constant bias, vibration, multipath and mounts that slip. These
/// numbers bound the *estimator*, not the product, and must never be presented
/// as measured accuracy (§83). They exist so that a change which makes drift
/// worse fails CI (§61).
void main() {
  group('drift versus outage duration', () {
    test('prints the table and holds the 10 % bar out to 300 s', () {
      final evaluator = DriftEvaluator(mount: PhoneMount.tilted());
      final scores = <OutageScore>[];

      // ignore: avoid_print
      print('\nSIMULATED drift benchmark — car, tilted console mount');
      // ignore: avoid_print
      print(OutageScore.header);
      for (final seconds in [10.0, 30.0, 60.0, 120.0, 300.0]) {
        final score = evaluator.evaluate(outageSeconds: seconds);
        scores.add(score);
        // ignore: avoid_print
        print(score.row);
      }

      for (final score in scores) {
        expect(
          score.driftPercent,
          lessThan(10),
          reason: 'drift ${score.driftPercent.toStringAsFixed(2)} % over '
              '${score.outageSeconds.toStringAsFixed(0)} s',
        );
      }
    });

    test('the filter never claims to be more accurate than it is', () {
      // An estimate that is wrong but knows it is wrong stays usable; one that
      // is wrong and confident is the dangerous failure (§28).
      final evaluator = DriftEvaluator(mount: PhoneMount.tilted());
      for (final seconds in [30.0, 120.0, 300.0]) {
        final score = evaluator.evaluate(outageSeconds: seconds);
        expect(
          score.uncertaintyCoveredError,
          isTrue,
          reason: '${seconds.toStringAsFixed(0)} s: error '
              '${score.finalErrorM.toStringAsFixed(1)} m vs 3-sigma '
              '${(score.finalSigmaM * 3).toStringAsFixed(1)} m',
        );
      }
    });

    test('longer outages drift further, and the engine says so', () {
      final evaluator = DriftEvaluator(mount: PhoneMount.tilted());
      final short = evaluator.evaluate(outageSeconds: 30);
      final long = evaluator.evaluate(outageSeconds: 300);
      expect(long.finalErrorM, greaterThan(short.finalErrorM));
      expect(long.finalSigmaM, greaterThan(short.finalSigmaM));
      expect(long.mode, NavMode.deadReckoning);
    });
  });

  group('sensitivity', () {
    test('a worse IMU drifts further — the engine is not insensitive to its '
        'inputs', () {
      final good = DriftEvaluator(
        mount: PhoneMount.tilted(),
        accelBias: const [0.02, -0.01, 0.01],
        gyroBias: const [0.0005, -0.0003, 0.0008],
      ).evaluate(outageSeconds: 60);

      final poor = DriftEvaluator(
        mount: PhoneMount.tilted(),
        accelBias: const [0.30, -0.22, 0.18],
        gyroBias: const [0.010, -0.008, 0.012],
      ).evaluate(outageSeconds: 60);

      // ignore: avoid_print
      print('\nSIMULATED IMU sensitivity at 60 s');
      // ignore: avoid_print
      print(OutageScore.header);
      // ignore: avoid_print
      print('good  ${good.row}');
      // ignore: avoid_print
      print('poor  ${poor.row}');

      expect(poor.finalErrorM, greaterThan(good.finalErrorM));
    });

    test('mount orientation does not change the answer', () {
      // The whole point of the alignment step: a phone lying flat and a phone
      // yawed 35 deg on a tilted console must dead-reckon the same.
      final flat = DriftEvaluator(mount: PhoneMount.flatTopForward())
          .evaluate(outageSeconds: 60);
      final tilted = DriftEvaluator(mount: PhoneMount.tilted())
          .evaluate(outageSeconds: 60);

      // ignore: avoid_print
      print('\nSIMULATED mount comparison at 60 s');
      // ignore: avoid_print
      print(OutageScore.header);
      // ignore: avoid_print
      print('flat   ${flat.row}');
      // ignore: avoid_print
      print('tilted ${tilted.row}');

      expect(flat.driftPercent, lessThan(10));
      expect(tilted.driftPercent, lessThan(10));
    });
  });
}
