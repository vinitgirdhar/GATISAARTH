import 'package:flutter/foundation.dart';

import '../../../core/nav/model/nav_snapshot.dart' show NavIntegrity;

/// Driver-facing trust level for the current position solution.
///
/// Ordered worst-to-best for hysteresis purposes: red > orange > amber >
/// green. [waiting] is a separate, neutral state ("no position yet") and is
/// never ranked against the others — moving into or out of it is immediate,
/// not subject to the de-escalation delay below.
enum TrustLevel { waiting, green, amber, orange, red }

/// Everything [classifyRaw] needs, gathered from both the heuristic pipeline
/// (GNSS/outage state) and the navigation core's snapshot. Immutable so a
/// classification can be unit-tested without a running controller.
@immutable
class TrustInput {
  const TrustInput({
    required this.hadFix,
    required this.locationLive,
    required this.secondsSinceLastFix,
    required this.uncertaintyM,
    required this.engineLeading,
    required this.integrity,
    required this.roadLocked,
    this.uncertaintyGrowthMPerS,
    this.gnssAccuracyM,
  });

  /// False until the very first real GNSS fix of this session arrives.
  final bool hadFix;

  /// True only while a fresh fix is arriving right now (mirrors
  /// `LiveLocationService.isLive`).
  final bool locationLive;

  /// Seconds since the last real fix; 0 while [locationLive] is true.
  final double secondsSinceLastFix;

  /// Current modelled/covariance position uncertainty (m), or null when
  /// there is no basis for one yet.
  final double? uncertaintyM;

  /// How fast [uncertaintyM] is growing right now (m/s), or null when it
  /// cannot be measured yet (fewer than two samples).
  final double? uncertaintyGrowthMPerS;

  /// Whether the navigation core is currently leading the position.
  final bool engineLeading;

  final NavIntegrity integrity;

  /// True while the dead-reckoned marker is locked to the road network, so a
  /// road-locked outage reads as AMBER rather than bare heading integration.
  final bool roadLocked;

  /// The receiver's last reported horizontal accuracy (m), or null.
  final double? gnssAccuracyM;
}

/// What the controller decided, and everything a view needs to render it
/// without recomputing anything — the single source every screen consumes.
@immutable
class TrustAssessment {
  const TrustAssessment({
    required this.level,
    required this.headline,
    required this.reason,
    required this.limited,
    this.displayPrecisionM,
  });

  final TrustLevel level;

  /// Driver-facing headline, e.g. "Position reliable".
  final String headline;

  /// One short clause explaining why, e.g. "GNSS accuracy 6 m".
  final String reason;

  /// True only at [TrustLevel.red]: the UI must switch to Limited Navigation
  /// Mode — no metre-precise coordinates, turn/speed guidance paused.
  final bool limited;

  /// Rounding step (m) for any uncertainty number a view still shows, or
  /// null when there is no fix-derived number to show at all ([waiting]).
  final double? displayPrecisionM;

  static const TrustAssessment waitingForFix = TrustAssessment(
    level: TrustLevel.waiting,
    headline: 'Waiting for a fix',
    reason: 'No position yet',
    limited: false,
  );
}

/// Every threshold the safety controller uses, named and justified — mirrors
/// the "nothing hard-coded" rule `core/nav/nav_config.dart` applies inside
/// the core. This controller sits in the domain layer instead (it reads both
/// the heuristic pipeline's outage state and the core's snapshot), so its
/// tunables live here rather than in `NavConfig`.
class NavSafetyThresholds {
  const NavSafetyThresholds._();

  /// AMBER ceiling: "uncertainty still modest". Matches the EKF's own
  /// medium/low integrity boundary (`NavigationEngine._integrity`, sigma>60
  /// -> low) so the badge never disagrees with the integrity the engine is
  /// already reporting.
  static const double amberSigmaMaxM = 60.0;

  /// ORANGE ceiling: uncertainty is high but not yet a hard failure. Matches
  /// the hand-held-mode invalid threshold (150 m) used elsewhere in the core.
  static const double orangeSigmaMaxM = 150.0;

  /// RED hard limit: beyond this the estimate is not worth showing as a
  /// number, only as "> N m".
  static const double redHardLimitM = 300.0;

  /// Growing faster than this (m of uncertainty per second) counts as
  /// "growing fast" for ORANGE even before [orangeSigmaMaxM] is crossed —
  /// warns the driver a few seconds ahead of the hard threshold rather than
  /// jumping straight from AMBER to RED.
  static const double orangeGrowthMPerS = 3.0;

  /// GNSS accuracy (m) beyond which a *live* fix still counts as "poor
  /// accuracy, GNSS degraded" for ORANGE. Matches `GnssConfig.degradedAccuracy`.
  static const double orangeGnssAccuracyM = 50.0;

  /// Dead reckoning running this long without a real correction is RED even
  /// if the modelled sigma has not yet crossed the hard limit: a model's own
  /// confidence in an unbounded outage cannot be trusted forever. Chosen
  /// inside the window the drift benchmark already reports out to
  /// (`test/nav/drift_benchmark_test.dart`, 300 s).
  static const double drTooLongSeconds = 240.0;

  /// De-escalation hysteresis: a *better* condition must hold this long
  /// before the badge steps down, so one good tick at 10 Hz cannot flicker
  /// the level. Escalation to a worse level is always immediate.
  static const Duration deescalateDelay = Duration(seconds: 4);
}

/// Pure classification, no hysteresis — see [NavigationSafetyController] for
/// the stateful, flicker-resistant wrapper the app actually uses.
TrustLevel classifyRaw(TrustInput i) {
  if (!i.hadFix) return TrustLevel.waiting;
  if (i.integrity == NavIntegrity.invalid) return TrustLevel.red;

  final sigma = i.uncertaintyM;
  if (sigma == null || !sigma.isFinite) return TrustLevel.red;
  if (sigma > NavSafetyThresholds.redHardLimitM) return TrustLevel.red;
  if (i.secondsSinceLastFix > NavSafetyThresholds.drTooLongSeconds) {
    return TrustLevel.red;
  }

  if (i.integrity == NavIntegrity.low) return TrustLevel.orange;
  if (sigma > NavSafetyThresholds.orangeSigmaMaxM) return TrustLevel.orange;

  final growth = i.uncertaintyGrowthMPerS;
  if (growth != null && growth > NavSafetyThresholds.orangeGrowthMPerS) {
    return TrustLevel.orange;
  }

  if (i.locationLive && !i.engineLeading) {
    final acc = i.gnssAccuracyM;
    if (acc != null && acc > NavSafetyThresholds.orangeGnssAccuracyM) {
      return TrustLevel.orange;
    }
  }

  final inOutage = !i.locationLive || i.secondsSinceLastFix > 0;
  if (inOutage && sigma > NavSafetyThresholds.amberSigmaMaxM) {
    return TrustLevel.orange;
  }
  if (inOutage || i.roadLocked) return TrustLevel.amber;
  return TrustLevel.green;
}

TrustAssessment _assessmentFor(TrustLevel level, TrustInput i) {
  switch (level) {
    case TrustLevel.waiting:
      return TrustAssessment.waitingForFix;

    case TrustLevel.green:
      return TrustAssessment(
        level: level,
        headline: 'Position reliable',
        reason: i.gnssAccuracyM != null
            ? 'GNSS accuracy ±${i.gnssAccuracyM!.round()} m'
            : 'Live GNSS fix',
        limited: false,
        displayPrecisionM: 1,
      );

    case TrustLevel.amber:
      return TrustAssessment(
        level: level,
        headline: 'Dead reckoning active',
        reason: i.roadLocked
            ? 'No GNSS fix — following the road network'
            : 'No GNSS fix — estimating from sensors',
        limited: false,
        displayPrecisionM: 10,
      );

    case TrustLevel.orange:
      final poorAccuracy = i.locationLive &&
          (i.gnssAccuracyM ?? 0) > NavSafetyThresholds.orangeGnssAccuracyM;
      return TrustAssessment(
        level: level,
        headline: 'High uncertainty',
        // NavIntegrity.low is the core's own confidence (sigma or a GNSS
        // anomaly), so it is reported as low integrity, not as an anomaly.
        reason: i.integrity == NavIntegrity.low
            ? 'Navigation integrity low'
            : poorAccuracy
                ? 'GNSS signal degraded'
                : 'Position uncertainty growing quickly',
        limited: false,
        displayPrecisionM: 25,
      );

    case TrustLevel.red:
      final tooLong =
          i.secondsSinceLastFix > NavSafetyThresholds.drTooLongSeconds;
      return TrustAssessment(
        level: level,
        headline: 'Position unreliable',
        reason: i.integrity == NavIntegrity.invalid
            ? 'Navigation filter failed'
            : tooLong
                ? 'No GNSS correction for too long'
                : 'Uncertainty beyond the safe limit',
        limited: true,
        displayPrecisionM: 50,
      );
  }
}

/// "± N m" normally, "> N m" once [TrustAssessment.limited] hides exact
/// numbers — never a bare unrounded metric in Limited Navigation Mode, and
/// never a made-up number when there is nothing to measure yet.
String formatUncertainty(TrustAssessment assessment, double? sigmaM) {
  final precision = assessment.displayPrecisionM;
  if (sigmaM == null || precision == null) return '--';
  final rounded = (sigmaM / precision).ceil() * precision;
  return assessment.limited ? '> ${rounded.round()} m' : '± ${rounded.round()} m';
}

int _severity(TrustLevel l) {
  switch (l) {
    case TrustLevel.waiting:
      return -1;
    case TrustLevel.green:
      return 0;
    case TrustLevel.amber:
      return 1;
    case TrustLevel.orange:
      return 2;
    case TrustLevel.red:
      return 3;
  }
}

/// Stateful wrapper around [classifyRaw] that applies the de-escalation
/// hysteresis (§ [NavSafetyThresholds.deescalateDelay]): the level can jump
/// straight to a worse one, but a step back to a better one only sticks once
/// the better condition has held for the full delay. This is what keeps the
/// badge from flickering GREEN/AMBER/GREEN at 10 Hz right at a threshold.
class NavigationSafetyController {
  NavigationSafetyController({
    Duration deescalateDelay = NavSafetyThresholds.deescalateDelay,
  }) : _deescalateDelay = deescalateDelay;

  final Duration _deescalateDelay;

  TrustLevel? _level;
  TrustLevel? _pendingBetter;
  DateTime? _pendingSince;

  /// Feed one tick's worth of input and get back what the UI should show.
  TrustAssessment update(TrustInput input, DateTime now) {
    final raw = classifyRaw(input);
    final current = _level;

    final immediate = current == null ||
        raw == TrustLevel.waiting ||
        current == TrustLevel.waiting ||
        _severity(raw) >= _severity(current);

    if (immediate) {
      _level = raw;
      _pendingBetter = null;
      _pendingSince = null;
    } else if (_pendingBetter != raw) {
      // A new (better) candidate — start its clock.
      _pendingBetter = raw;
      _pendingSince = now;
    } else if (now.difference(_pendingSince!) >= _deescalateDelay) {
      _level = raw;
      _pendingBetter = null;
      _pendingSince = null;
    }

    return _assessmentFor(_level!, input);
  }
}
