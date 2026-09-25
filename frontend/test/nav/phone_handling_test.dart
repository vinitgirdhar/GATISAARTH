import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/motion/phone_handling.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

void main() {
  group('PhoneHandlingDetector', () {
    test('a quiet phone lying flat reports gravity up and no handling', () {
      final d = PhoneHandlingDetector();
      double? yawRate;
      for (var i = 0; i < 300; i++) {
        yawRate = d.add(
          accelPhone: Vector3(0, 0, -NavMath.gravity),
          gyroPhone: Vector3.zero(),
          monotonicUs: i * 20000,
        );
      }
      expect(d.isHandling, isFalse);
      expect(yawRate, closeTo(0, 1e-6));
    });

    test('a real turn about the true vertical reads through, however the '
        'phone is oriented', () {
      final d = PhoneHandlingDetector();
      // Phone lying flat: gravity direction is -Z, so a gyro reading about
      // the phone's own Z axis IS a rotation about the true vertical.
      const turnRate = 0.4; // rad/s
      double? yawRate;
      for (var i = 0; i < 300; i++) {
        yawRate = d.add(
          accelPhone: Vector3(0, 0, -NavMath.gravity),
          gyroPhone: Vector3(0, 0, turnRate),
          monotonicUs: i * 20000,
        );
      }
      expect(yawRate, closeTo(turnRate, 0.01));
    });

    test('a gravity direction sweeping fast sets the handling flag', () {
      final d = PhoneHandlingDetector(
        config: NavConfig(
          handHeld: const HandHeldConfig(
            gravityTauS: 0.05, // fast enough to track the sweep for the test
          ),
        ),
      );
      // Settle on "up" first.
      for (var i = 0; i < 100; i++) {
        d.add(
          accelPhone: Vector3(0, 0, -NavMath.gravity),
          gyroPhone: Vector3.zero(),
          monotonicUs: i * 20000,
        );
      }
      expect(d.isHandling, isFalse);

      // Now the phone is swept through 90 deg of tilt in well under a second:
      // being picked up and turned over, not riding quietly.
      var us = 100 * 20000;
      for (var i = 0; i <= 20; i++) {
        final angle = (i / 20) * (math.pi / 2);
        d.add(
          accelPhone:
              Vector3(math.sin(angle), 0, -math.cos(angle)) * NavMath.gravity,
          gyroPhone: Vector3.zero(),
          monotonicUs: us,
        );
        us += 10000; // 10 ms steps: 200 ms for the whole sweep
      }
      expect(d.isHandling, isTrue);
    });
  });

  group('HandHeldStopDetector', () {
    test('a still phone is declared stopped after the enter delay', () {
      final d = HandHeldStopDetector();
      bool last = false;
      for (var i = 0; i < 100; i++) {
        last = d.add(
          accelMagnitude: NavMath.gravity,
          monotonicUs: i * 20000,
        );
      }
      expect(last, isTrue);
    });

    test('shaking (high std(|a|)) is not a stop', () {
      final d = HandHeldStopDetector();
      bool last = false;
      for (var i = 0; i < 100; i++) {
        final wobble = (i.isEven ? 1 : -1) * 3.0;
        last = d.add(
          accelMagnitude: NavMath.gravity + wobble,
          monotonicUs: i * 20000,
        );
      }
      expect(last, isFalse);
    });
  });
}
