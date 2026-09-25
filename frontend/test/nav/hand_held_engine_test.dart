import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_quality.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/model/nav_snapshot.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';

/// A hand-held phone: no fixed phone-to-vehicle mount, so its orientation
/// relative to the world is driven directly (random tilt jitter plus
/// occasional "handling" bursts) rather than derived from a mount transform
/// the way `support/drive_simulator.dart` does for a mounted phone.
///
/// The vehicle itself drives straight (constant world heading) so ground
/// truth is trivial to compute; everything the gyro reports is genuinely the
/// phone moving in the hand, which is exactly what a hand-held path has to
/// see through.
class _HandHeldRig {
  _HandHeldRig({int seed = 11}) : _rng = math.Random(seed);

  final math.Random _rng;
  Quaternion _q = Quaternion.identity(); // phone-to-world(NED)

  double latitudeDeg = 12.9716;
  double longitudeDeg = 77.5946;
  double speed = 0; // m/s
  static const headingRad = math.pi / 2; // due east

  int _burstUntilUs = -1;

  /// Advances [dt] seconds at [accel] m/s² (world-frame, along heading), and
  /// returns the phone-frame accel/gyro an IMU would report.
  ({Vector3 accelPhone, Vector3 gyroPhone}) step({
    required double accel,
    required double dt,
    required int monotonicUs,
  }) {
    speed = math.max(0, speed + accel * dt);
    final moved = NavMath.addNed(
      latDeg: latitudeDeg,
      lonDeg: longitudeDeg,
      altM: 0,
      north: speed * math.cos(headingRad) * dt,
      east: speed * math.sin(headingRad) * dt,
      down: 0,
    );
    latitudeDeg = moved[0];
    longitudeDeg = moved[1];

    // Baseline hand tremor, always present (measured 0.4-1.4 rad/s hand-held
    // even at a standstill) plus, every ~2 s, a half-second "handling" burst
    // (picked up / turned over) an order of magnitude faster.
    final inBurst = monotonicUs < _burstUntilUs;
    if (!inBurst && monotonicUs % 2000000 < (dt * 1e6).round()) {
      _burstUntilUs = monotonicUs + 500000;
    }
    final scale = inBurst ? 3.0 : 0.6;
    double n() => (_rng.nextDouble() - 0.5) * 2 * scale;
    final gyroPhone = Vector3(n(), n(), n());
    _q = NavMath.propagate(_q, gyroPhone, dt);

    final worldAccel = Vector3(0, accel, 0); // NED: north=x, east=y
    final gravityNed = Vector3(0, 0, NavMath.gravity);
    final specificForceWorld = worldAccel - gravityNed;
    // Road/engine vibration while moving, near-silent at a standstill - what
    // actually lets std(|a|) tell the two apart on a real phone; a clean
    // constant acceleration has zero variance either way (§ hand-held mode,
    // `MotionConfig` doc on the same limitation for the mounted classifier).
    final vibrationStd = speed > 0.3 ? 0.9 : 0.05;
    double vib() => (_rng.nextDouble() - 0.5) * 2 * vibrationStd;
    final noisyForce =
        specificForceWorld + Vector3(vib(), vib(), vib());
    final accelPhone = NavMath.rotateNavToBody(_q, noisyForce);

    return (accelPhone: accelPhone, gyroPhone: gyroPhone);
  }

  GnssObservation fix(int monotonicUs) => GnssObservation(
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
        accuracyM: 5,
        monotonicUs: monotonicUs,
        speedMps: speed,
        bearingDeg: speed > 0.5 ? headingRad * NavMath.radToDeg : null,
      );
}

void main() {
  test(
      'a hand-held phone leads and bridges a GNSS outage despite random '
      'tilting and handling bursts', () {
    final config = NavConfig(features: FeatureFlags(handHeldMode: true));
    final engine = NavigationEngine(config: config);
    final rig = _HandHeldRig();

    const imuHz = 50.0;
    const dt = 1 / imuHz;
    var us = 0;
    var nextGnssUs = 0;

    // Warm up on live GNSS: accelerate to a cruise, mount never converges
    // (orientation is arbitrary each step), but the hand-held tracker should
    // pick up position and speed from the fixes.
    for (var i = 0; i < (20 * imuHz).round(); i++) {
      final accel = rig.speed < 12 ? 1.2 : 0.0;
      final sample = rig.step(accel: accel, dt: dt, monotonicUs: us);
      engine.onImu(
        accelPhone: sample.accelPhone,
        gyroPhone: sample.gyroPhone,
        monotonicUs: us,
      );
      if (us >= nextGnssUs) {
        engine.onGnss(rig.fix(us));
        nextGnssUs = us + 1000000;
      }
      us += (dt * 1e6).round();
    }

    final warm = engine.snapshot!;
    expect(warm.handHeld, isTrue,
        reason: 'no mount ever converges here; only the hand-held tracker '
            'can be reporting a position');
    expect(engine.alignment, isNull);
    expect(warm.canLeadPosition, isTrue,
        reason: 'a live, GNSS-anchored hand-held track should be usable');

    // Hold the last fix's position/speed as the baseline the hand-held
    // tracker must beat - the same "product with no inertial filter" bar the
    // outage benchmark uses.
    final holdLat = warm.latitude!;
    final holdLon = warm.longitude!;
    final holdSpeed = rig.speed;
    final outageStartUs = us;

    // 30 s outage, still tilting and handling: cruise, then brake to a full
    // stop and stay stopped - exactly where hold-last-speed fails hardest and
    // a stop detector earns its keep.
    engine.onGnssLost(us);
    for (var i = 0; i < (30 * imuHz).round(); i++) {
      final elapsed = i / imuHz;
      final accel = elapsed < 3
          ? 0.0
          : elapsed < 6
              ? -4.0
              : 0.0;
      final sample = rig.step(accel: accel, dt: dt, monotonicUs: us);
      engine.onImu(
        accelPhone: sample.accelPhone,
        gyroPhone: sample.gyroPhone,
        monotonicUs: us,
      );
      us += (dt * 1e6).round();
    }

    final afterOutage = engine.snapshot!;
    expect(afterOutage.handHeld, isTrue);
    expect(afterOutage.hasPosition, isTrue);

    final trueLat = rig.latitudeDeg;
    final trueLon = rig.longitudeDeg;
    final trackedError = NavMath.horizontalDistance(
      lat0: trueLat,
      lon0: trueLon,
      lat1: afterOutage.latitude!,
      lon1: afterOutage.longitude!,
    );
    final heldDuration = (us - outageStartUs) / 1e6;
    final heldMoved = NavMath.addNed(
      latDeg: holdLat,
      lonDeg: holdLon,
      altM: 0,
      north: holdSpeed * math.cos(_HandHeldRig.headingRad) * heldDuration,
      east: holdSpeed * math.sin(_HandHeldRig.headingRad) * heldDuration,
      down: 0,
    );
    final holdError = NavMath.horizontalDistance(
      lat0: trueLat,
      lon0: trueLon,
      lat1: heldMoved[0],
      lon1: heldMoved[1],
    );

    expect(trackedError, lessThan(holdError),
        reason: 'the hand-held tracker (gyro-projected, frozen-while-'
            'handling heading) should bridge the outage better than simply '
            'holding the last fix: $trackedError m vs $holdError m held');

    // Uncertainty must never shrink below what the fix itself was worth.
    expect(afterOutage.horizontalSigmaM, greaterThanOrEqualTo(5));
    // Never claimed better than medium: there is no known vehicle frame to
    // be more sure of (§ hand-held mode).
    expect(afterOutage.integrity, isNot(NavIntegrity.high));
  });
}
