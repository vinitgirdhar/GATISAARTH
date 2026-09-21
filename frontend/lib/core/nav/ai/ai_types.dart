import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ai_config.dart';

/// Where a disturbance estimate came from. The UI and the diagnostics say which,
/// so a statistical fallback is never mistaken for a neural model (§83).
enum EstimateSource { statistical, model }

/// How much the road and the engine are shaking the phone.
enum DisturbanceClass { low, normal, high }

/// A transient large enough that the raw readings around it cannot be trusted.
enum ShockKind {
  none,

  /// Speed breaker or expansion joint: a slow vertical ramp.
  bump,

  /// Pothole: a sharp vertical impulse.
  pothole,

  /// The phone was knocked or slid in its mount: a horizontal transient.
  jolt,
}

/// One forward-speed prediction of the neural model, stamped on the engine's
/// timeline (the IMU clock).
///
/// `speedMps` and `sigmaMps` are the model's two heads (`sigma = exp(logVar/2)`).
/// The rest is what the gate needs to decide whether to believe it: how long
/// inference took, how far the newest input window sat from the training
/// distribution (largest |z-score| over the window), and how many windows the
/// estimator has been fed since it last restarted.
@immutable
class AiSpeedObservation {
  const AiSpeedObservation({
    required this.speedMps,
    required this.sigmaMps,
    required this.monotonicUs,
    this.latencyMs = 0,
    this.featureZMax = 0,
    this.windowsFed = 1 << 20,
  });

  final double speedMps;
  final double sigmaMps;
  final int monotonicUs;
  final double latencyMs;
  final double featureZMax;
  final int windowsFed;

  @override
  String toString() => 'AiSpeed(${speedMps.toStringAsFixed(2)} '
      '+/-${sigmaMps.toStringAsFixed(2)} m/s, ${latencyMs.toStringAsFixed(1)} ms, '
      'z=${featureZMax.toStringAsFixed(1)}, windows=$windowsFed)';
}

/// What is disturbing the accelerometer right now (P2).
///
/// [vibrationScore] and [motionQuality] are in [0, 1]: 0 is a still cabin and
/// 1 is as violent as the scale goes; quality is 1 when the readings can be
/// taken at face value and falls towards 0 as they cannot.
@immutable
class DisturbanceEstimate {
  const DisturbanceEstimate({
    required this.vibrationScore,
    required this.vibrationClass,
    required this.motionQuality,
    required this.monotonicUs,
    this.shock = ShockKind.none,
    this.source = EstimateSource.model,
  });

  static const DisturbanceEstimate calm = DisturbanceEstimate(
    vibrationScore: 0,
    vibrationClass: DisturbanceClass.low,
    motionQuality: 1,
    monotonicUs: 0,
    source: EstimateSource.statistical,
  );

  final double vibrationScore;
  final DisturbanceClass vibrationClass;
  final double motionQuality;
  final int monotonicUs;
  final ShockKind shock;
  final EstimateSource source;

  bool get isShock => shock != ShockKind.none;

  /// Factor on a measurement *variance* (speed, NHC, ZUPT, ZARU):
  /// `(1 + 2 V) / Q`, from `ml/README.md`, capped. Never below 1.
  double measurementNoiseScale(DisturbanceConfig config) => _scale(
        config.measurementNoiseGain,
        config.maxMeasurementScale,
        config,
        _quality(config),
      );

  /// Factor on the INS process noise: `(1 + 1.5 V) / trust`, capped, where
  /// `trust` is [insTrust] when a model fusion confidence supplied one (it
  /// *replaces* the motion quality here, so the same quantity is never divided
  /// by twice) and this estimate's own motion quality otherwise.
  double processNoiseScale(DisturbanceConfig config, {double? insTrust}) =>
      _scale(
        config.processNoiseGain,
        config.maxProcessScale,
        config,
        insTrust ?? _quality(config),
      );

  double _quality(DisturbanceConfig config) => motionQuality.isFinite
      ? _clamp(motionQuality, config.minMotionQuality, 1)
      : 1.0;

  double _scale(double gain, double cap, DisturbanceConfig config, double q) {
    final v = vibrationScore.isFinite ? _clamp(vibrationScore, 0, 1) : 0.0;
    return _clamp((1 + gain * v) / q, 1, cap);
  }

  DisturbanceEstimate copyWith({ShockKind? shock}) => DisturbanceEstimate(
        vibrationScore: vibrationScore,
        vibrationClass: vibrationClass,
        motionQuality: motionQuality,
        monotonicUs: monotonicUs,
        shock: shock ?? this.shock,
        source: source,
      );

  @override
  String toString() => 'Disturbance(${vibrationClass.name} '
      'V=${vibrationScore.toStringAsFixed(2)} '
      'Q=${motionQuality.toStringAsFixed(2)} shock=${shock.name} '
      '${source.name})';
}

/// How much the fusion should trust each side right now (P3), in (0, 1].
///
/// 1 is "as configured". GNSS trust divides the GNSS measurement variance
/// (`R / trust`); INS trust divides the strapdown process noise
/// (`Q / trust`). Both are clamped by [AiConfig] so a model can soften a sensor
/// but never silence it. A fresh INS trust *replaces* the motion quality in the
/// process-noise factor (`Q (1 + 1.5 V) / trust`), so a model that derives it
/// from motion quality is not counted twice.
@immutable
class FusionConfidence {
  const FusionConfidence({
    this.gnssTrust = 1.0,
    this.insTrust = 1.0,
    this.monotonicUs = 0,
  });

  /// What the engine uses when no model has spoken: no scaling at all.
  static const FusionConfidence neutral = FusionConfidence();

  final double gnssTrust;
  final double insTrust;
  final int monotonicUs;

  bool get isNeutral => gnssTrust == 1.0 && insTrust == 1.0;

  /// Multiplier on a GNSS *sigma*: `1 / sqrt(trust)`, so the variance scales by
  /// `1 / trust`.
  double gnssSigmaScale(AiConfig config) =>
      1 / math.sqrt(_trust(gnssTrust, config.minGnssTrust));

  /// The INS trust after clamping, in [`minInsTrust`, 1].
  double effectiveInsTrust(AiConfig config) =>
      _trust(insTrust, config.minInsTrust);

  static double _trust(double value, double floor) =>
      value.isFinite ? _clamp(value, floor, 1) : 1.0;

  @override
  String toString() => 'Fusion(gnss=${gnssTrust.toStringAsFixed(2)}, '
      'ins=${insTrust.toStringAsFixed(2)})';
}

/// Why an AI speed observation was not used (kept, counted, shown).
enum AiRejectReason {
  /// The AI path, or its speed part, is switched off.
  disabled,

  /// No filter position yet, or the phone-to-vehicle mount is not known.
  notReady,

  /// A non-finite or negative speed, or a non-positive sigma.
  invalid,

  /// Not newer than the last observation.
  outOfOrder,

  /// The estimator has not been fed enough windows yet.
  warmup,

  /// Inference plus the time it sat in a queue exceeded the limit.
  latency,

  /// The input window sat too far from the training distribution.
  offDistribution,

  /// Faster than any vehicle this engine will believe.
  overSpeed,

  /// The model has not (or has not yet) agreed with the GNSS-anchored speed.
  unvalidated,

  /// Too far from the INS forward speed for both sigmas to explain.
  physicsDisagreement,

  /// The filter could not apply it.
  filterRefused,
}

extension AiRejectReasonLabel on AiRejectReason {
  String get label {
    switch (this) {
      case AiRejectReason.disabled:
        return 'disabled';
      case AiRejectReason.notReady:
        return 'not ready';
      case AiRejectReason.invalid:
        return 'invalid';
      case AiRejectReason.outOfOrder:
        return 'out of order';
      case AiRejectReason.warmup:
        return 'warming up';
      case AiRejectReason.latency:
        return 'too slow';
      case AiRejectReason.offDistribution:
        return 'off-distribution input';
      case AiRejectReason.overSpeed:
        return 'over max speed';
      case AiRejectReason.unvalidated:
        return 'not validated against GNSS';
      case AiRejectReason.physicsDisagreement:
        return 'disagrees with INS';
      case AiRejectReason.filterRefused:
        return 'filter refused';
    }
  }
}

/// What the gate decided about one speed observation.
enum AiSpeedOutcome {
  /// Folded into the filter.
  applied,

  /// GNSS is healthy, so it only counted towards validating the model.
  validatedOnly,

  /// Refused; see [AiSpeedDecision.reason].
  rejected,
}

@immutable
class AiSpeedDecision {
  const AiSpeedDecision.rejected(AiRejectReason this.reason)
      : outcome = AiSpeedOutcome.rejected,
        sigmaUsedMps = null,
        innovationMps = null;

  const AiSpeedDecision.validatedOnly({this.innovationMps})
      : outcome = AiSpeedOutcome.validatedOnly,
        reason = null,
        sigmaUsedMps = null;

  const AiSpeedDecision.applied({
    required double this.sigmaUsedMps,
    required double this.innovationMps,
  })  : outcome = AiSpeedOutcome.applied,
        reason = null;

  final AiSpeedOutcome outcome;
  final AiRejectReason? reason;

  /// The sigma handed to the filter: floored, inflated for disturbance and
  /// widened until the update's gain fits the contribution clamp.
  final double? sigmaUsedMps;

  /// Observation minus the INS forward speed it was compared with (m/s).
  final double? innovationMps;

  bool get applied => outcome == AiSpeedOutcome.applied;
  bool get rejected => outcome == AiSpeedOutcome.rejected;
}

/// A read-only account of what the AI path is doing, carried on every
/// navigation snapshot so "is AI in the loop?" has an answer that is not a
/// claim (§83).
@immutable
class AiDiagnostics {
  const AiDiagnostics({
    this.enabled = false,
    this.speedActive = false,
    this.disturbanceActive = false,
    this.fusionActive = false,
    this.speedObserved = 0,
    this.speedApplied = 0,
    this.speedValidatedOnly = 0,
    this.speedRejected = const {},
    this.lastRejectReason,
    this.validated = false,
    this.validationRmseMps,
    this.validationBiasMps,
    this.lastSpeed,
    this.lastInnovationMps,
    this.disturbance,
    this.fusion,
    this.measurementNoiseScale = 1.0,
    this.processNoiseScale = 1.0,
    this.gnssSigmaScale = 1.0,
    this.shockHeld = false,
  });

  static const AiDiagnostics off = AiDiagnostics();

  final bool enabled;
  final bool speedActive;
  final bool disturbanceActive;
  final bool fusionActive;

  final int speedObserved;
  final int speedApplied;

  /// Predictions that only served to validate the model (GNSS was healthy).
  final int speedValidatedOnly;
  final Map<AiRejectReason, int> speedRejected;
  final AiRejectReason? lastRejectReason;

  final bool validated;
  final double? validationRmseMps;
  final double? validationBiasMps;

  final AiSpeedObservation? lastSpeed;
  final double? lastInnovationMps;

  /// The disturbance estimate the filter is using, or null when disturbance
  /// adaptation is off. [DisturbanceEstimate.source] says which kind.
  final DisturbanceEstimate? disturbance;

  /// The model fusion confidence in use, or null when none is (neutral).
  final FusionConfidence? fusion;

  /// The factors actually applied this instant: on the variance of speed, NHC,
  /// ZUPT and ZARU; on the INS process noise; on the GNSS sigma. 1.0 = no
  /// change.
  final double measurementNoiseScale;
  final double processNoiseScale;
  final double gnssSigmaScale;

  /// True while ZUPT, ZARU and tilt learning are held for a shock.
  final bool shockHeld;

  int get speedRejectedTotal =>
      speedRejected.values.fold(0, (sum, n) => sum + n);

  /// A single line for the subsystem row and the AI panel.
  String get summary {
    if (!enabled) return 'AI fusion off';
    final parts = <String>[];
    if (speedActive) {
      parts.add('speed $speedApplied used, '
          '$speedRejectedTotal rejected'
          '${lastRejectReason == null ? '' : ' (last: ${lastRejectReason!.label})'}'
          '${validated ? '' : ', not validated yet'}');
    }
    if (disturbanceActive && disturbance != null) {
      parts.add('${disturbance!.vibrationClass.name} vibration '
          '(${disturbance!.source.name})');
    }
    if (fusionActive && fusion != null) parts.add('fusion $fusion');
    return parts.isEmpty ? 'AI fusion on, nothing active' : parts.join(' | ');
  }
}

double _clamp(double v, double lo, double hi) => math.min(hi, math.max(lo, v));
