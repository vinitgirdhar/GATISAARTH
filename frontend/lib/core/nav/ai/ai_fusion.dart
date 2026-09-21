import 'dart:math' as math;

import '../ekf/navigation_filter.dart';
import '../math/nav_math.dart';
import '../nav_config.dart';
import 'accel_disturbance_estimator.dart';
import 'ai_speed_gate.dart';
import 'ai_types.dart';

/// The noise factors and holds the AI path asks of the filter at one instant.
///
/// All 1.0 / false when the AI path is off or has nothing to say, which is what
/// makes the disabled engine bit-identical to the engine before the AI existed.
class AiScales {
  const AiScales({
    this.measurementVariance = 1.0,
    this.processNoise = 1.0,
    this.gnssSigma = 1.0,
    this.holdUpdates = false,
  });

  static const AiScales neutral = AiScales();

  /// Factor on the *variance* of speed, NHC, ZUPT and ZARU measurements.
  final double measurementVariance;

  /// Factor on the INS process noise (disturbance and INS trust together).
  final double processNoise;

  /// Factor on a GNSS *sigma* (`1 / sqrt(trust)`).
  final double gnssSigma;

  /// A shock is being held: ZUPT, ZARU and tilt learning wait.
  final bool holdUpdates;

  /// Factor on the sigma of a measurement whose variance is scaled by
  /// [measurementVariance].
  double get measurementSigma => math.sqrt(measurementVariance);
}

/// Everything the AI path keeps between calls: the statistical estimator, the
/// last model outputs, the speed gate. Owned by the navigation engine.
///
/// Pure and deterministic like the engine around it: every input carries its own
/// timestamp on the IMU timeline, and there is no clock, timer or randomness.
class AiFusion {
  AiFusion(this._config)
      : gate = AiSpeedGate(_config.ai),
        _statistical = AccelDisturbanceEstimator(config: _config);

  final NavConfig _config;

  /// The forward-speed gate, with its counters and its validation record.
  final AiSpeedGate gate;
  final AccelDisturbanceEstimator _statistical;

  DisturbanceEstimate? _model;
  FusionConfidence? _fusion;

  AiConfig get _ai => _config.ai;

  void reset() {
    gate.reset();
    _statistical.reset();
    _model = null;
    _fusion = null;
  }

  /// Feeds the accelerometer to the statistical fallback. O(1); a no-op unless
  /// disturbance adaptation is on.
  void observeAccel(Vector3 accel, int monotonicUs) {
    if (_ai.disturbanceActive) _statistical.add(accel, monotonicUs);
  }

  /// A disturbance estimate from the vibration / motion-quality models. Values
  /// are clamped to their ranges; anything non-finite is ignored.
  void setModelDisturbance(DisturbanceEstimate estimate) {
    if (!estimate.vibrationScore.isFinite || !estimate.motionQuality.isFinite) {
      return;
    }
    final last = _model;
    if (last != null && estimate.monotonicUs < last.monotonicUs) return;
    _model = DisturbanceEstimate(
      vibrationScore: _unit(estimate.vibrationScore),
      vibrationClass: estimate.vibrationClass,
      motionQuality: _unit(estimate.motionQuality),
      monotonicUs: estimate.monotonicUs,
      shock: estimate.shock,
      source: EstimateSource.model,
    );
  }

  /// A fusion confidence from a model. Trusts are clamped to (0, 1]; anything
  /// non-finite is ignored.
  void setFusionConfidence(FusionConfidence confidence) {
    if (!confidence.gnssTrust.isFinite || !confidence.insTrust.isFinite) return;
    final last = _fusion;
    if (last != null && confidence.monotonicUs < last.monotonicUs) return;
    _fusion = confidence;
  }

  /// The disturbance estimate the filter should act on at [us]: the model's
  /// while it is fresh, the statistical one otherwise. A shock seen by either
  /// counts, because a 10 Hz model can miss a 60 ms pothole the statistical
  /// estimator saw, and holding too much is the safe error.
  DisturbanceEstimate effectiveDisturbance(int us) {
    final statistical = _statistical.latest;
    final model = _model;
    if (model == null ||
        us - model.monotonicUs > _ai.modelOutputTtl.inMicroseconds) {
      return statistical;
    }
    if (statistical.isShock) return model.copyWith(shock: statistical.shock);
    final held =
        us - model.monotonicUs <= _config.disturbance.shockHold.inMicroseconds;
    return held ? model : model.copyWith(shock: ShockKind.none);
  }

  FusionConfidence? _freshFusion(int us) {
    final fusion = _fusion;
    if (fusion == null) return null;
    return us - fusion.monotonicUs > _ai.modelOutputTtl.inMicroseconds
        ? null
        : fusion;
  }

  /// The factors for the current instant.
  ///
  /// `R = R0 (1 + 2 V) / Q` on speed, NHC, ZUPT and ZARU;
  /// `Qins = Q0 (1 + 1.5 V) / trust` on the process noise, where `trust` is the
  /// model's INS trust when it has one and the motion quality `Q` otherwise;
  /// `sigma_gnss = sigma / sqrt(gnssTrust)`.
  AiScales scales(int us) {
    if (!_ai.enabled) return AiScales.neutral;
    final fusion = _ai.fusionTrust ? _freshFusion(us) : null;
    final insTrust = fusion?.effectiveInsTrust(_ai);
    final d = _ai.disturbanceAdaptation ? effectiveDisturbance(us) : null;
    var process = 1.0;
    if (d != null) {
      process = d.processNoiseScale(_config.disturbance, insTrust: insTrust);
    } else if (insTrust != null) {
      process = 1 / insTrust;
    }
    return AiScales(
      measurementVariance: d?.measurementNoiseScale(_config.disturbance) ?? 1.0,
      processNoise: process,
      gnssSigma: fusion?.gnssSigmaScale(_ai) ?? 1.0,
      holdUpdates: d?.isShock ?? false,
    );
  }

  /// Judges one speed observation and, when the gate passes it, folds it into
  /// [filter] as a pre-gated forward-speed measurement.
  ///
  /// [engineUs] is the engine's newest IMU time (null before the mount is
  /// known), [mountKnown] whether a phone-to-vehicle transform exists, [outage]
  /// whether GNSS is out (only then is the observation applied; otherwise it
  /// only grades the model). The [MeasurementResult] is returned so the engine
  /// can record it and credit the AI in its contribution accounting.
  ({AiSpeedDecision decision, MeasurementResult? result}) applySpeed({
    required AiSpeedObservation obs,
    required NavigationFilter filter,
    required int? engineUs,
    required bool mountKnown,
    required bool outage,
  }) {
    if (!_ai.speedActive) {
      return (
        decision: gate.reject(AiRejectReason.disabled, obs),
        result: null
      );
    }
    final predicted = filter.forwardSpeed;
    final variance = filter.forwardSpeedVariance;
    if (engineUs == null ||
        !mountKnown ||
        predicted == null ||
        variance == null) {
      return (
        decision: gate.reject(AiRejectReason.notReady, obs),
        result: null
      );
    }
    final decision = gate.evaluate(
      obs: obs,
      engineUs: engineUs,
      predictedMps: predicted,
      predictedVariance: variance,
      applyNow: outage,
      sigmaScale: scales(engineUs).measurementSigma,
    );
    if (!decision.applied) return (decision: decision, result: null);
    final result = filter.updateForwardSpeed(
      speedMps: obs.speedMps,
      sigma: decision.sigmaUsedMps!,
      name: 'ai_forward_speed',
      preGated: true,
    );
    return result.accepted
        ? (decision: decision, result: result)
        : (decision: gate.filterRefused(), result: result);
  }

  /// A usable fix reported a Doppler speed: the model's newest prediction is
  /// graded against it (see [AiSpeedGate.gradeAgainstGnss]).
  void gradeWithGnss(double gnssSpeedMps, int fixUs) {
    if (_ai.speedActive) {
      gate.gradeAgainstGnss(gnssSpeedMps: gnssSpeedMps, fixUs: fixUs);
    }
  }

  /// Factor on a GNSS sigma at [us]: 1.0 unless a fresh model fusion
  /// confidence says otherwise.
  double gnssSigmaScale(int us) {
    if (!_ai.fusionActive) return 1.0;
    return _freshFusion(us)?.gnssSigmaScale(_ai) ?? 1.0;
  }

  /// What the AI path is doing, for the snapshot.
  AiDiagnostics diagnostics(int us) {
    if (!_ai.enabled) return AiDiagnostics.off;
    final s = scales(us);
    return AiDiagnostics(
      enabled: true,
      speedActive: _ai.speedMeasurement,
      disturbanceActive: _ai.disturbanceAdaptation,
      fusionActive: _ai.fusionTrust,
      speedObserved: gate.observed,
      speedApplied: gate.applied,
      speedValidatedOnly: gate.validatedOnly,
      speedRejected: gate.rejected,
      lastRejectReason: gate.lastReject,
      validated: gate.validated,
      validationRmseMps: gate.validationRmseMps,
      validationBiasMps: gate.validationBiasMps,
      lastSpeed: gate.lastObservation,
      lastInnovationMps: gate.lastInnovationMps,
      disturbance: _ai.disturbanceAdaptation ? effectiveDisturbance(us) : null,
      fusion: _ai.fusionTrust ? _freshFusion(us) : null,
      measurementNoiseScale: s.measurementVariance,
      processNoiseScale: s.processNoise,
      gnssSigmaScale: s.gnssSigma,
      shockHeld: s.holdUpdates,
    );
  }

  static double _unit(double v) => math.min(1.0, math.max(0.0, v));
}
