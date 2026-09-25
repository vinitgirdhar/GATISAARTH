import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';

import 'support/drive_simulator.dart';

/// Drives a converged mount, then knocks the phone into a new orientation
/// while the vehicle sits still, and checks the snapshot tells that apart
/// from a mount that has simply never converged (§ mount-change detection).
void main() {
  test('a converged mount that moves mid-drive is reported as recalibrating',
      () {
    final sim = DriveSimulator(mount: PhoneMount.flatTopForward());
    final e = NavigationEngine();

    void driveFor(double seconds, {double accel = 0, bool gnss = true}) {
      final steps = (seconds * sim.imuHz).round();
      var nextGnssUs = 0;
      for (var i = 0; i < steps; i++) {
        final frame = sim.step(DriveSegment(seconds: 1 / sim.imuHz, longitudinalAccel: accel));
        e.onImu(
          accelPhone: frame.accelPhone,
          gyroPhone: frame.gyroPhone,
          monotonicUs: frame.truth.monotonicUs,
        );
        if (gnss && frame.truth.monotonicUs >= nextGnssUs) {
          nextGnssUs = frame.truth.monotonicUs + 1000000;
          e.onGnss(sim.gnss());
        }
      }
    }

    // A normal calibration drive: repeated accelerate/brake on a straight
    // road, exactly what the mount estimator needs (§6).
    driveFor(3);
    for (var i = 0; i < 14; i++) {
      driveFor(4, accel: 1.8);
      driveFor(1);
      driveFor(4, accel: -1.8);
      driveFor(1);
    }

    expect(e.alignment, isNotNull);
    expect(e.alignment!.confidence, greaterThanOrEqualTo(0.6));
    expect(e.snapshot!.recalibratingMount, isFalse);
    expect(
      e.snapshot!.notes.any((n) => n.contains('Mount change detected')),
      isFalse,
    );

    // Knock the phone into a new mount: gravity in the phone frame swings by
    // far more than the drift threshold (0.25 rad / ~14 deg) while the
    // vehicle sits still — the classic "phone fell out of the cradle" event.
    final rotated = PhoneMount.tilted(yawDeg: 80, tiltDeg: 65);
    var us = sim.truth.monotonicUs;
    for (var i = 0; i < 400; i++) {
      us += 20000;
      e.onImu(
        accelPhone: rotated.toPhone(Vector3(0, 0, -NavMath.gravity)),
        gyroPhone: Vector3.zero(),
        monotonicUs: us,
      );
    }

    final snap = e.snapshot!;
    expect(snap.recalibratingMount, isTrue);
    expect(
      snap.notes.any((n) => n.contains('Mount change detected')),
      isTrue,
      reason: 'must read differently from the first-boot '
          '"alignment not established" note',
    );
    expect(
      snap.notes.any((n) => n.contains('Recalibrating vehicle frame')),
      isTrue,
    );
  });
}
