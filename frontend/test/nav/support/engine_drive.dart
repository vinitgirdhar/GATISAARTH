import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';

import 'drive_simulator.dart';

/// Drives a [NavigationEngine] from a [DriveSimulator], one IMU frame at a
/// time, with a 1 Hz GNSS fix while [gnssOn]. Drains per frame (the clock
/// trap in the root CLAUDE.md).
class EngineDrive {
  EngineDrive(this.engine, this.sim);

  final NavigationEngine engine;
  final DriveSimulator sim;
  bool gnssOn = true;
  int _nextGnssUs = 0;

  void drive(List<DriveSegment> segments) {
    for (final segment in segments) {
      final steps = (segment.seconds * sim.imuHz).round();
      for (var i = 0; i < steps; i++) {
        final frame = sim.step(segment);
        engine.onImu(
          accelPhone: frame.accelPhone,
          gyroPhone: frame.gyroPhone,
          monotonicUs: frame.truth.monotonicUs,
        );
        if (gnssOn && frame.truth.monotonicUs >= _nextGnssUs) {
          _nextGnssUs = frame.truth.monotonicUs + 1000000;
          engine.onGnss(sim.gnss());
        }
      }
    }
  }

  void loseGnss() {
    gnssOn = false;
    engine.onGnssLost(sim.truth.monotonicUs);
  }

  /// Turns GNSS back on; the next frame of [drive] delivers the first fix.
  void restoreGnss() {
    gnssOn = true;
    _nextGnssUs = 0;
  }

  /// Horizontal distance from the filter's position to the truth.
  double errorM() {
    final s = engine.filter.state!;
    final t = sim.truth;
    return NavMath.horizontalDistance(
      lat0: s.latitudeDeg,
      lon0: s.longitudeDeg,
      lat1: t.latitude,
      lon1: t.longitude,
    );
  }
}
