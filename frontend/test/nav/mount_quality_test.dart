import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/alignment/mount_quality.dart';

void main() {
  group('MountQualityEstimator', () {
    final e = MountQualityEstimator();

    test('a still, converged, quiet, on-field mount scores EXCELLENT', () {
      final q = e.evaluate(
        orientationWobbleDeg: 0.5,
        handling: false,
        vibrationScore: 0.05,
        magneticFieldMicroTesla: 45,
        alignmentConfidence: 0.9,
      );
      expect(q.label, MountQualityLabel.excellent);
      expect(q.unstable, isFalse);
      expect(q.message, isNull);
      expect(q.overall, greaterThanOrEqualTo(85));
    });

    test('a steady mount whose alignment is not learned yet is FAIR at best',
        () {
      final q = e.evaluate(
        orientationWobbleDeg: 0,
        handling: false,
        vibrationScore: 0,
        magneticFieldMicroTesla: 48,
        alignmentConfidence: 0,
      );
      expect(q.overall, greaterThanOrEqualTo(65)); // would read GOOD
      expect(q.label, MountQualityLabel.fair);
    });

    test('a phone being handled is flagged unstable regardless of the rest',
        () {
      final q = e.evaluate(
        orientationWobbleDeg: 1.0,
        handling: true,
        vibrationScore: 0.05,
        magneticFieldMicroTesla: 45,
        alignmentConfidence: 0.9,
      );
      expect(q.unstable, isTrue);
      expect(q.message, contains('Mount unstable'));
      expect(q.stability, lessThan(50));
    });

    test('heavy wobble past the threshold is unstable even without the '
        'handling flag', () {
      final q = e.evaluate(
        orientationWobbleDeg: 15,
        handling: false,
        vibrationScore: 0.05,
        magneticFieldMicroTesla: 45,
        alignmentConfidence: 0.9,
      );
      expect(q.unstable, isTrue);
    });

    test('a field outside Earth\'s band zeroes the magnetic sub-score', () {
      final q = e.evaluate(
        orientationWobbleDeg: 0.5,
        magneticFieldMicroTesla: 200,
        alignmentConfidence: 0.9,
      );
      expect(q.magnetic, 0);
    });

    test('heavy wobble, heavy vibration and no alignment yet pulls the '
        'score down to POOR', () {
      final q = e.evaluate(
        orientationWobbleDeg: 10,
        vibrationScore: 0.95,
        magneticFieldMicroTesla: 45,
        alignmentConfidence: null,
      );
      expect(q.label, MountQualityLabel.poor);
      expect(q.alignment, 0);
    });

    test('unknown inputs are neutral, not penalised as failures', () {
      final q = e.evaluate();
      expect(q.magnetic, greaterThan(0));
      expect(q.stability, 100);
    });
  });
}
