import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';
import '../nav_config.dart';

/// One GNSS fix as the navigation core sees it.
///
/// Deliberately separate from the platform layer's `GnssFix` so the core stays
/// free of plugin and Flutter types; the session adapter converts between them.
@immutable
class GnssObservation {
  const GnssObservation({
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.accuracyM,
    required this.monotonicUs,
    this.altitudeM,
    this.speedMps,
    this.speedAccuracyMps,
    this.bearingDeg,
    this.bearingAccuracyDeg,
    this.verticalAccuracyM,
    this.satellitesUsed,
    this.isMocked = false,
  });

  final double latitudeDeg;
  final double longitudeDeg;

  /// Horizontal accuracy radius (m) as the platform reports it.
  final double accuracyM;
  final int monotonicUs;

  final double? altitudeM;
  final double? speedMps;
  final double? speedAccuracyMps;
  final double? bearingDeg;
  final double? bearingAccuracyDeg;
  final double? verticalAccuracyM;

  /// Only when the OS actually exposes it. Null means "not available", and the
  /// UI must show `--` rather than a plausible-looking number (§65, §83).
  final int? satellitesUsed;

  final bool isMocked;

  bool get hasFiniteCoordinates =>
      latitudeDeg.isFinite &&
      longitudeDeg.isFinite &&
      latitudeDeg.abs() <= 90 &&
      longitudeDeg.abs() <= 180;
}

/// Quality banding for a fix (§13).
enum GnssQualityClass { excellent, good, degraded, poor, invalid }

/// Why a fix was refused as a filter measurement (§14).
enum GnssRejectReason {
  none,
  nonFinite,
  outOfBounds,
  stale,
  accuracyTooPoor,
  impossibleJump,
  impossibleAcceleration,
  impossibleHeadingChange,
  mocked,
}

/// Independent health verdict on the GNSS source (§15).
///
/// Wording is deliberately cautious: a phone cannot prove spoofing, only that
/// the signal is behaving in a way real satellite geometry does not.
enum GnssIntegrity { healthy, degraded, unreliable, anomaly }

extension GnssIntegrityLabel on GnssIntegrity {
  String get label {
    switch (this) {
      case GnssIntegrity.healthy:
        return 'GNSS healthy';
      case GnssIntegrity.degraded:
        return 'GNSS degraded';
      case GnssIntegrity.unreliable:
        return 'GNSS unreliable';
      case GnssIntegrity.anomaly:
        return 'GNSS integrity anomaly detected';
    }
  }
}

@immutable
class GnssAssessment {
  const GnssAssessment({
    required this.quality,
    required this.score,
    required this.reason,
    required this.integrity,
    required this.horizontalSigmaM,
    this.verticalSigmaM,
    this.velocitySigmaMps,
    this.useVelocity = false,
    this.notes = const [],
  });

  final GnssQualityClass quality;

  /// 0..1 composite. Used to scale measurement covariance (§12), not shown as
  /// a percentage of anything physical.
  final double score;

  final GnssRejectReason reason;
  final GnssIntegrity integrity;

  /// Measurement sigma the filter should use — the reported accuracy inflated
  /// by everything the score knows and the platform does not.
  final double horizontalSigmaM;
  final double? verticalSigmaM;
  final double? velocitySigmaMps;

  /// True when the Doppler velocity is good enough to use as a measurement.
  final bool useVelocity;

  final List<String> notes;

  bool get usable => reason == GnssRejectReason.none;

  @override
  String toString() =>
      'GNSS ${quality.name} score=${score.toStringAsFixed(2)} '
      'sigma=${horizontalSigmaM.toStringAsFixed(1)}m '
      '${usable ? 'usable' : 'rejected:${reason.name}'} ${integrity.name}';
}

/// Scores, gates and monitors GNSS fixes (§13, §14, §15).
///
/// Stateful on purpose: most of what distinguishes a good fix from a bad one
/// is how it relates to the previous ones. Feed it every fix, accepted or not.
class GnssQualityEngine {
  GnssQualityEngine({NavConfig config = NavConfig.defaults})
      : _config = config.gnss;

  final GnssConfig _config;

  GnssObservation? _lastAccepted;
  double? _lastAcceptedSpeed;
  final Queue<GnssObservation> _recent = Queue<GnssObservation>();
  final Queue<bool> _strikes = Queue<bool>();
  int _consecutiveRejections = 0;

  int get consecutiveRejections => _consecutiveRejections;

  /// Fixes kept for the oscillation test.
  int get windowLength => _recent.length;

  void reset() {
    _lastAccepted = null;
    _lastAcceptedSpeed = null;
    _recent.clear();
    _strikes.clear();
    _consecutiveRejections = 0;
  }

  /// Assesses [fix].
  ///
  /// [inertialHeadingDeg] and [inertialSpeedMps] come from the filter when it
  /// is running; they let the monitor notice GNSS disagreeing with physics.
  /// Pass null before the filter is initialised — the checks that need them
  /// are then simply skipped rather than guessed at.
  GnssAssessment assess(
    GnssObservation fix, {
    double? inertialHeadingDeg,
    double? inertialSpeedMps,
  }) {
    final notes = <String>[];

    if (!fix.hasFiniteCoordinates || !fix.accuracyM.isFinite) {
      return _reject(GnssRejectReason.nonFinite, fix, notes);
    }
    // (0,0) is in the Gulf of Guinea; every GNSS stack in the world emits it
    // as a null-island placeholder far more often than anyone drives there.
    if (fix.latitudeDeg == 0 && fix.longitudeDeg == 0) {
      return _reject(GnssRejectReason.outOfBounds, fix, notes);
    }
    if (fix.isMocked) {
      notes.add('Fix reported as mocked by the platform');
      return _reject(GnssRejectReason.mocked, fix, notes);
    }
    if (fix.accuracyM <= 0 || fix.accuracyM > _config.maxUsableAccuracy) {
      return _reject(GnssRejectReason.accuracyTooPoor, fix, notes);
    }

    final previous = _lastAccepted;
    double? impliedSpeed;
    double? impliedAccel;

    if (previous != null) {
      final dtSeconds = (fix.monotonicUs - previous.monotonicUs) / 1e6;
      if (dtSeconds <= 0) {
        notes.add('Fix is not newer than the last accepted one');
        return _reject(GnssRejectReason.stale, fix, notes);
      }
      final distance = NavMath.horizontalDistance(
        lat0: previous.latitudeDeg,
        lon0: previous.longitudeDeg,
        lat1: fix.latitudeDeg,
        lon1: fix.longitudeDeg,
      );
      impliedSpeed = distance / dtSeconds;

      // Allow for the uncertainty of both endpoints before calling a jump
      // impossible: two 40 m fixes 30 m apart is noise, not teleportation.
      final tolerance = (previous.accuracyM + fix.accuracyM) / dtSeconds;
      if (impliedSpeed > _config.maxJumpSpeed + tolerance) {
        notes.add('Implied ${impliedSpeed.toStringAsFixed(0)} m/s between fixes');
        return _reject(GnssRejectReason.impossibleJump, fix, notes);
      }

      final prevSpeed = _lastAcceptedSpeed;
      if (prevSpeed != null) {
        impliedAccel = (impliedSpeed - prevSpeed).abs() / dtSeconds;
        final accelTolerance = tolerance / math.max(dtSeconds, 0.2);
        if (impliedAccel > _config.maxImpliedAccel + accelTolerance) {
          notes.add(
              'Implied ${impliedAccel.toStringAsFixed(1)} m/s² between fixes');
          return _reject(GnssRejectReason.impossibleAcceleration, fix, notes);
        }
      }

      // Heading only means anything once the vehicle is genuinely moving; at a
      // standstill the bearing of a 5 m noise hop is meaningless.
      final bearing = fix.bearingDeg;
      final prevBearing = previous.bearingDeg;
      if (bearing != null &&
          prevBearing != null &&
          (fix.speedMps ?? 0) > 2 &&
          (previous.speedMps ?? 0) > 2) {
        final rate =
            NavMath.angleDiffDeg(bearing, prevBearing).abs() / dtSeconds;
        // Grip, not geometry, limits how fast a vehicle can change heading:
        // yawRate <= lateralAccel / speed.
        final speedNow = math.max(fix.speedMps ?? 0, 1.0);
        final limit = math.min(
          _config.maxHeadingRateDegPerSec,
          NavMath.radToDeg * _config.maxLateralAccel / speedNow,
        );
        if (rate > limit) {
          notes.add('${rate.toStringAsFixed(0)}°/s heading change');
          return _reject(GnssRejectReason.impossibleHeadingChange, fix, notes);
        }
      }
    }

    // ------------------------------------------------------------- scoring
    var score = _accuracyScore(fix.accuracyM);

    final oscillating = _detectOscillation(inertialSpeedMps);
    if (oscillating) {
      notes.add('Position oscillating while the vehicle is moving');
      score *= 0.5;
    }

    double? headingDisagreement;
    if (inertialHeadingDeg != null &&
        fix.bearingDeg != null &&
        (fix.speedMps ?? 0) > 3 &&
        (inertialSpeedMps ?? 0) > 3) {
      headingDisagreement =
          NavMath.angleDiffDeg(fix.bearingDeg!, inertialHeadingDeg).abs();
      if (headingDisagreement > _config.integrityHeadingDisagreeDeg) {
        notes.add(
            'GNSS bearing disagrees with inertial by ${headingDisagreement.toStringAsFixed(0)}°');
        score *= 0.6;
      }
    }

    if (inertialSpeedMps != null && fix.speedMps != null) {
      final speedGap = (fix.speedMps! - inertialSpeedMps).abs();
      if (speedGap > 10) {
        notes.add('GNSS speed differs from inertial by '
            '${speedGap.toStringAsFixed(1)} m/s');
        score *= 0.7;
      }
    }

    // A device that is definitely stationary should not be moving on GNSS.
    if (inertialSpeedMps != null &&
        inertialSpeedMps < 0.3 &&
        (impliedSpeed ?? 0) > 8) {
      notes.add('Large GNSS movement while the vehicle is stationary');
      score *= 0.4;
    }

    score = score.clamp(0.0, 1.0);
    final strike = score < 0.5 || oscillating;
    final integrity = _updateIntegrity(strike);

    _lastAccepted = fix;
    _lastAcceptedSpeed = impliedSpeed ?? fix.speedMps;
    _consecutiveRejections = 0;
    _pushRecent(fix);

    // §12: covariance grows as the score falls, so a degraded fix nudges the
    // state instead of yanking it.
    final inflation = 1 / math.max(score, 0.2);
    final horizontalSigma = fix.accuracyM * inflation;

    final speedAccuracy = fix.speedAccuracyMps;
    final useVelocity = fix.speedMps != null &&
        fix.accuracyM <= _config.minAccuracyForVelocity &&
        integrity != GnssIntegrity.anomaly;

    return GnssAssessment(
      quality: _classify(score, fix.accuracyM),
      score: score,
      reason: GnssRejectReason.none,
      integrity: integrity,
      horizontalSigmaM: horizontalSigma,
      verticalSigmaM:
          (fix.verticalAccuracyM ?? fix.accuracyM * 2) * inflation,
      velocitySigmaMps:
          useVelocity ? math.max(speedAccuracy ?? 1.0, 0.3) * inflation : null,
      useVelocity: useVelocity,
      notes: notes,
    );
  }

  double _accuracyScore(double accuracy) {
    if (accuracy <= _config.excellentAccuracy) return 1.0;
    if (accuracy <= _config.goodAccuracy) {
      return _lerp(1.0, 0.75, accuracy, _config.excellentAccuracy,
          _config.goodAccuracy);
    }
    if (accuracy <= _config.degradedAccuracy) {
      return _lerp(
          0.75, 0.45, accuracy, _config.goodAccuracy, _config.degradedAccuracy);
    }
    return _lerp(0.45, 0.1, accuracy, _config.degradedAccuracy,
        _config.maxUsableAccuracy);
  }

  GnssQualityClass _classify(double score, double accuracy) {
    if (score >= 0.9 && accuracy <= _config.excellentAccuracy) {
      return GnssQualityClass.excellent;
    }
    if (score >= 0.7) return GnssQualityClass.good;
    if (score >= 0.45) return GnssQualityClass.degraded;
    return GnssQualityClass.poor;
  }

  /// Urban-canyon signature: the last N fixes all sit inside a small radius
  /// while the inertial solution says the vehicle is genuinely moving (§23).
  bool _detectOscillation(double? inertialSpeedMps) {
    if (inertialSpeedMps == null || inertialSpeedMps < 3) return false;
    if (_recent.length < _config.oscillationWindow) return false;

    var sumLat = 0.0, sumLon = 0.0;
    for (final f in _recent) {
      sumLat += f.latitudeDeg;
      sumLon += f.longitudeDeg;
    }
    final meanLat = sumLat / _recent.length;
    final meanLon = sumLon / _recent.length;
    for (final f in _recent) {
      final d = NavMath.horizontalDistance(
        lat0: meanLat,
        lon0: meanLon,
        lat1: f.latitudeDeg,
        lon1: f.longitudeDeg,
      );
      if (d > _config.oscillationRadius) return false;
    }
    return true;
  }

  GnssIntegrity _updateIntegrity(bool strike) {
    _strikes.addLast(strike);
    while (_strikes.length > _config.integrityStrikeWindow) {
      _strikes.removeFirst();
    }
    final count = _strikes.where((s) => s).length;
    if (count >= _config.integrityStrikesForAnomaly) {
      return GnssIntegrity.anomaly;
    }
    if (count >= 2) return GnssIntegrity.unreliable;
    if (count == 1) return GnssIntegrity.degraded;
    return GnssIntegrity.healthy;
  }

  void _pushRecent(GnssObservation fix) {
    _recent.addLast(fix);
    while (_recent.length > _config.oscillationWindow) {
      _recent.removeFirst();
    }
  }

  GnssAssessment _reject(
    GnssRejectReason reason,
    GnssObservation fix,
    List<String> notes,
  ) {
    _consecutiveRejections++;
    // A rejection is a strike against the source, not just this fix.
    final integrity = _updateIntegrity(true);
    return GnssAssessment(
      quality: GnssQualityClass.invalid,
      score: 0,
      reason: reason,
      integrity: integrity,
      horizontalSigmaM:
          fix.accuracyM.isFinite && fix.accuracyM > 0 ? fix.accuracyM : 0,
      notes: notes,
    );
  }

  static double _lerp(
      double from, double to, double x, double x0, double x1) {
    if (x1 <= x0) return to;
    final t = ((x - x0) / (x1 - x0)).clamp(0.0, 1.0);
    return from + (to - from) * t;
  }
}
