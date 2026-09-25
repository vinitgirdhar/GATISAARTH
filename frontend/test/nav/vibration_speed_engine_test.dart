import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';

import 'support/drive_simulator.dart';
import 'support/engine_drive.dart';

/// Cruise at several steady speeds with GNSS (the speedometer learns the
/// wheel), then an outage with a speed change the accelerometer must follow.
({NavigationEngine engine, double errorM, int appliedWhileGnss}) _run({
  required bool vibration,
  double forwardBias = 0.08,
}) {
  final engine = NavigationEngine(
    config: NavConfig(features: FeatureFlags(vibrationSpeed: vibration)),
  );
  final sim = DriveSimulator(
    mount: PhoneMount.tilted(),
    wheelVibration: 0.3,
    accelBias: [forwardBias, -0.05, 0.06],
    seed: 11,
  );
  final d = EngineDrive(engine, sim);
  d.drive(calibrationDrive());
  for (final accel in [1.0, 0.6, 0.8, -0.7]) {
    d.drive([
      DriveSegment(seconds: 5, longitudinalAccel: accel),
      const DriveSegment(seconds: 20),
    ]);
  }
  final appliedWhileGnss = engine.vibrationSpeedDiagnostics.applied;
  d.loseGnss();
  d.drive(const [
    DriveSegment(seconds: 30),
    DriveSegment(seconds: 5, longitudinalAccel: 0.8),
    DriveSegment(seconds: 50),
  ]);
  return (engine: engine, errorM: d.errorM(), appliedWhileGnss: appliedWhileGnss);
}

void main() {
  test('switched off, it does nothing at all', () {
    final r = _run(vibration: false);
    expect(r.engine.vibrationSpeedDiagnostics.peaks, 0);
  });

  test('it learns the wheel from GNSS and is never applied while GNSS is live',
      () {
    final r = _run(vibration: true);
    final d = r.engine.vibrationSpeedDiagnostics;
    expect(r.appliedWhileGnss, 0);
    expect(d.calibrationPairs, greaterThan(10));
    expect(d.trusted, isTrue);
    // The simulated tyre: f = v / (2 pi r), so metres per cycle = 2 pi r.
    expect(d.metresPerCycle, closeTo(2 * 3.14159 * 0.31, 0.06));
  });

  test('in an outage it is offered to the filter and bounds along-track drift '
      '(simulated: a claim needs a recorded phone drive)', () {
    final off = _run(vibration: false, forwardBias: 0.12);
    final on = _run(vibration: true, forwardBias: 0.12);
    expect(on.engine.vibrationSpeedDiagnostics.applied, greaterThan(20));
    // ignore: avoid_print
    print('85 s outage, forward accel bias 0.12 m/s²: '
        'off ${off.errorM.toStringAsFixed(1)} m, '
        'on ${on.errorM.toStringAsFixed(1)} m');
    expect(on.errorM, lessThan(off.errorM * 1.25 + 2));
  });
}
