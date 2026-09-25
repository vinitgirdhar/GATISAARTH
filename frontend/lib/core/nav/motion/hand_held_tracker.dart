import 'dart:math' as math;

import '../math/nav_math.dart';
import '../nav_config.dart';

/// A minimal dead-reckoning model for a phone that is **not mounted**: there
/// is no known forward axis, so no vehicle-frame accelerometer integration
/// and no non-holonomic constraint (§ hand-held mode). Just heading from the
/// orientation-invariant gyro yaw rate (bias-corrected, frozen while the
/// phone is being handled, and pulled toward the road when the map matcher
/// snaps - see `NavigationEngine._runMapMatchHandHeld`), speed held from the
/// last trusted GNSS speed with a stop detector, and position advanced along
/// that heading and speed.
///
/// Deliberately **not** the full EKF (`NavigationFilter`): its strapdown
/// mechanization assumes body-frame accelerometer readings are meaningful,
/// which they are not without a phone-to-vehicle transform. This class, the
/// hand-held config (`NavConfig.handHeld`) and its default
/// (`FeatureFlags.handHeldMode`) exist to be justified or killed by the real
/// -drive benchmark (`test/nav/score_drive_test.dart`), not by argument.
class HandHeldTracker {
  HandHeldTracker({NavConfig config = NavConfig.defaults})
      : _config = config.handHeld;

  final HandHeldConfig _config;

  double? _latitudeDeg;
  double? _longitudeDeg;
  double? _headingRad;
  double? _speedMps;
  double _headingSigmaRad = 0;
  double _speedSigmaMps = 0;

  /// Sigma at the last fix, and how much variance has been added by dead
  /// reckoning since then - kept apart so the along-track term (a fraction of
  /// distance travelled) and the cross-track term (heading uncertainty) can
  /// each be computed honestly from what has actually happened since, rather
  /// than compounding a per-step approximation (§ hand-held mode, part 3).
  double _fixSigmaM = 0;
  double _crossTrackVarianceM2 = 0;
  double _distanceSinceFixM = 0;

  int? _lastUs;

  // Previous fix's own position/time, for a course derived from displacement
  // when the platform fix carries no bearing at all - see [onFix].
  double? _prevFixLat;
  double? _prevFixLon;
  int? _prevFixUs;

  bool get hasPosition => _latitudeDeg != null && _longitudeDeg != null;
  double? get latitudeDeg => _latitudeDeg;
  double? get longitudeDeg => _longitudeDeg;
  double? get headingDeg => _headingRad == null
      ? null
      : NavMath.wrap360(_headingRad! * NavMath.radToDeg);
  double? get speedMps => _speedMps;
  double get speedSigmaMps => _speedSigmaMps;
  double get headingSigmaDeg => _headingSigmaRad * NavMath.radToDeg;

  /// Along-track (a fraction of distance driven since the last fix) combined
  /// with cross-track (from accumulated heading uncertainty), on top of the
  /// last fix's own sigma.
  double get horizontalSigmaM {
    final alongTrack = _config.alongTrackErrorFraction * _distanceSinceFixM;
    return math.sqrt(
      _fixSigmaM * _fixSigmaM + _crossTrackVarianceM2 + alongTrack * alongTrack,
    );
  }

  void reset() {
    _latitudeDeg = null;
    _longitudeDeg = null;
    _headingRad = null;
    _speedMps = null;
    _headingSigmaRad = 0;
    _speedSigmaMps = 0;
    _fixSigmaM = 0;
    _crossTrackVarianceM2 = 0;
    _distanceSinceFixM = 0;
    _lastUs = null;
    _prevFixLat = null;
    _prevFixLon = null;
    _prevFixUs = null;
  }

  /// A trusted GNSS fix: snaps position (always) and speed (when reported)
  /// straight to it, and resets every sigma to what the fix itself is worth -
  /// exactly what a receiver-anchored dead-reckoner should do on real
  /// evidence.
  ///
  /// Heading prefers the fix's own bearing, but plenty of real receivers
  /// simply never report one (measured: 0/459 fixes on one of the three
  /// real drives this was built from) - when that happens, the course
  /// between this fix and the last one, from their raw displacement, is
  /// used instead. Both need a useful speed (below it, course-over-ground of
  /// either kind is mostly noise) and the displacement fallback additionally
  /// needs enough distance between the two fixes to bear a course at all.
  void onFix({
    required double latitudeDeg,
    required double longitudeDeg,
    double? bearingDeg,
    double? speedMps,
    required double horizontalSigmaM,
    required int monotonicUs,
  }) {
    final useful = (speedMps ?? 0) >= _config.minBearingSpeedMps;
    if (bearingDeg != null && useful) {
      _headingRad = bearingDeg * NavMath.degToRad;
      _headingSigmaRad = _config.headingSigmaAtFixRad;
    } else if (useful &&
        _prevFixLat != null &&
        _prevFixUs != null &&
        (monotonicUs - _prevFixUs!) / 1e6 <= _config.maxCourseFixGapS) {
      final d = NavMath.nedBetween(
        lat0: _prevFixLat!,
        lon0: _prevFixLon!,
        alt0: 0,
        lat1: latitudeDeg,
        lon1: longitudeDeg,
        alt1: 0,
      );
      if (math.sqrt(d.x * d.x + d.y * d.y) >= _config.minCourseDisplacementM) {
        _headingRad = math.atan2(d.y, d.x);
        _headingSigmaRad = _config.headingSigmaFromDisplacementRad;
      }
    }
    _prevFixLat = latitudeDeg;
    _prevFixLon = longitudeDeg;
    _prevFixUs = monotonicUs;

    _latitudeDeg = latitudeDeg;
    _longitudeDeg = longitudeDeg;
    if (speedMps != null) {
      _speedMps = speedMps;
      _speedSigmaMps = _config.speedSigmaAtFixMps;
    }
    _fixSigmaM = horizontalSigmaM;
    _crossTrackVarianceM2 = 0;
    _distanceSinceFixM = 0;
    _lastUs = monotonicUs;
  }

  /// A road-matched heading (§ hand-held mode, part 2): a scalar Bayesian
  /// fusion of the matched road heading against the tracker's own heading and
  /// its sigma, exactly like the mounted path's `updateHeading` but for this
  /// tracker's plain heading/sigma instead of the EKF's covariance. Only the
  /// heading is ever corrected this way - never the position, matching the
  /// map matcher's own rule that it "never pushes position into the state".
  void applyHeadingMeasurement({
    required double headingRad,
    required double sigmaRad,
  }) {
    final heading = _headingRad;
    if (heading == null || !sigmaRad.isFinite || sigmaRad <= 0) return;
    final priorVar = _headingSigmaRad * _headingSigmaRad;
    final measVar = sigmaRad * sigmaRad;
    final gain = priorVar / (priorVar + measVar);
    final innovation = NavMath.wrapPi(headingRad - heading);
    _headingRad = NavMath.wrapPi(heading + gain * innovation);
    _headingSigmaRad = math.sqrt((1 - gain) * priorVar);
  }

  /// Propagates the dead reckoning by one IMU step. No-op before the first
  /// [onFix] (nothing to propagate from) or on a non-positive/too-large `dt`
  /// (a clock glitch or a gap, not a real step).
  void predict({
    required double yawRateRadPerS,
    required bool handling,
    required bool stationary,
    required int monotonicUs,
  }) {
    final last = _lastUs;
    _lastUs = monotonicUs;
    if (last == null || !hasPosition) return;
    final dt = (monotonicUs - last) / 1e6;
    if (dt <= 0 || dt > 1) return;

    // Frozen while being handled: the gravity direction the yaw rate is
    // measured against is itself moving then, so the rate is not trustworthy
    // (measured: hand-held median heading error 13-15 deg/10 s outside
    // handling, far worse inside it).
    if (!handling && _headingRad != null) {
      _headingRad = NavMath.wrapPi(_headingRad! + yawRateRadPerS * dt);
    }
    final headingGrowth = handling
        ? _config.headingSigmaGrowthHandlingRadPerS
        : _config.headingSigmaGrowthRadPerS;
    _headingSigmaRad = math.min(
        _headingSigmaRad + headingGrowth * dt, _config.maxHeadingSigmaRad);

    if (stationary) {
      _speedMps = 0;
      _speedSigmaMps = _config.stationarySpeedSigmaMps;
    } else {
      _speedSigmaMps += _config.speedSigmaGrowthMpsPerS * dt;
    }

    final speed = _speedMps;
    final heading = _headingRad;
    if (speed != null && heading != null && speed > 0) {
      final moved = NavMath.addNed(
        latDeg: _latitudeDeg!,
        lonDeg: _longitudeDeg!,
        altM: 0,
        north: speed * math.cos(heading) * dt,
        east: speed * math.sin(heading) * dt,
        down: 0,
      );
      _latitudeDeg = moved[0];
      _longitudeDeg = moved[1];
      _distanceSinceFixM += speed * dt;
    }

    // Cross-track from heading uncertainty, accumulated as variance so a
    // long, quietly-held stretch does not overstate the error the way a
    // linear sum of sigmas would. Along-track is a fraction of distance
    // driven (`horizontalSigmaM`) - measured 25-38 % along-track error over
    // 30/60 s hold-last-speed in Mumbai stop-go traffic.
    final crossTrack = (speed ?? 0) * _headingSigmaRad * dt;
    _crossTrackVarianceM2 += crossTrack * crossTrack;
  }
}
