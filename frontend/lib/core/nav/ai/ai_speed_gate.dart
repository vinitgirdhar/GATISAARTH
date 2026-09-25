import 'dart:math' as math;

import 'ai_config.dart';
import 'ai_types.dart';
import 'speed_calibration.dart';

/// Decides whether one neural forward-speed prediction may touch the filter,
/// and with what noise (P1).
///
/// A gate, not a fuser: it never sees the state, only what it is told about it
/// (`predictedMps`, `predictedVariance`), which keeps it a small deterministic
/// object with no clock and no randomness. Checks run cheapest first and each
/// refusal has its own [AiRejectReason], counted and remembered:
///
///  1. **invalid** - non-finite, negative speed, non-positive sigma;
///  2. **out of order** - not newer than the last observation;
///  3. **warm-up** - too few windows fed since the estimator restarted;
///  4. **latency** - inference time plus the age of the observation;
///  5. **off-distribution** - the input window sat outside the training data;
///  6. **over-speed**;
///  7. (GNSS healthy: **validate only**, see below);
///  8. **unvalidated** - the model has not earned its place;
///  9. **physics disagreement** - the innovation is beyond
///     `physicsDisagreeSigma` combined sigmas of the model and the INS.
///
/// **Validation.** The physics test alone cannot stop a *biased* model on a
/// long outage: the INS's own variance grows, and with it the disagreement that
/// still looks plausible. So while GNSS speaks, the newest prediction that
/// passed checks 1-6 is held back and, when a fix with a Doppler speed arrives
/// within [AiConfig.validationPairWindow], compared with it
/// ([gradeAgainstGnss]) and kept as a running mean and mean-square. The model is
/// let into an outage only when enough pairs agreed (see
/// [AiConfig.validationMaxRmse]). Nothing is learned during an outage: no fix
/// arrives then, and the INS is what is drifting, so it could not grade the
/// model anyway.
///
/// The accepted sigma is the model's, floored at `floorSigma`, scaled by the
/// disturbance factor the caller passes, and finally widened until the update's
/// Kalman gain fits `minContribution..maxContribution`.
class AiSpeedGate {
  AiSpeedGate(this._config) : calibration = SpeedCalibration(_config);

  final AiConfig _config;

  /// Per-vehicle correction; only used while
  /// [AiConfig.perVehicleCalibration] is on.
  final SpeedCalibration calibration;

  int _observed = 0;
  int _applied = 0;
  int _validatedOnly = 0;
  final Map<AiRejectReason, int> _rejected = {};
  AiRejectReason? _lastReject;
  AiSpeedObservation? _lastObservation;
  double? _lastInnovation;
  int? _lastObservationUs;

  AiSpeedObservation? _pending;
  int _validationCount = 0;
  double _validationMean = 0;
  double _validationMeanSquare = 0;

  int get observed => _observed;
  int get applied => _applied;

  /// Predictions that only graded the model, because GNSS was healthy.
  int get validatedOnly => _validatedOnly;
  Map<AiRejectReason, int> get rejected => Map.unmodifiable(_rejected);
  int get rejectedTotal => _rejected.values.fold(0, (sum, n) => sum + n);
  AiRejectReason? get lastReject => _lastReject;
  AiSpeedObservation? get lastObservation => _lastObservation;
  double? get lastInnovationMps => _lastInnovation;

  /// True once the model has agreed with the GNSS-anchored speed for long enough
  /// and closely enough (see the class comment).
  bool get validated =>
      _validationCount >= _config.validationMinSamples &&
      validationRmseMps! <= _config.validationMaxRmse &&
      validationBiasMps!.abs() <= _config.validationMaxBias;

  double? get validationRmseMps =>
      _validationCount == 0 ? null : math.sqrt(_validationMeanSquare);
  double? get validationBiasMps =>
      _validationCount == 0 ? null : _validationMean;

  void reset() {
    _observed = 0;
    _applied = 0;
    _validatedOnly = 0;
    _rejected.clear();
    _lastReject = null;
    _lastObservation = null;
    _lastInnovation = null;
    _lastObservationUs = null;
    _pending = null;
    _validationCount = 0;
    _validationMean = 0;
    _validationMeanSquare = 0;
    calibration.reset();
  }

  /// The model speed as the gate uses it: corrected for this vehicle when
  /// calibration is on and ready.
  double _corrected(double modelMps) => _config.perVehicleCalibration
      ? calibration.apply(modelMps) ?? modelMps
      : modelMps;

  /// Counts a refusal made by the caller before the gate is consulted (the AI
  /// path is off, the engine is not ready, the filter would not take it).
  AiSpeedDecision reject(AiRejectReason reason, AiSpeedObservation obs) {
    _observed++;
    _lastObservation = obs;
    return _refuse(reason);
  }

  /// The filter would not take an observation the gate had passed (singular
  /// innovation covariance, non-finite update): the count moves from applied to
  /// refused, so the two never disagree with what the filter actually did.
  AiSpeedDecision filterRefused() {
    _applied--;
    return _refuse(AiRejectReason.filterRefused);
  }

  /// A usable GNSS fix reported [gnssSpeedMps] at [fixUs]: grades the newest
  /// clean prediction against it, if there is one that close in time. Each
  /// prediction is graded at most once.
  void gradeAgainstGnss({required double gnssSpeedMps, required int fixUs}) {
    final obs = _pending;
    if (obs == null || !gnssSpeedMps.isFinite || gnssSpeedMps < 0) return;
    if ((fixUs - obs.monotonicUs).abs() >
        _config.validationPairWindow.inMicroseconds) {
      return;
    }
    _pending = null;
    // Graded on the correction as it stood *before* this pair: out of sample.
    _grade(_corrected(obs.speedMps) - gnssSpeedMps);
    if (_config.perVehicleCalibration) {
      final wasReady = calibration.isReady;
      calibration.add(modelMps: obs.speedMps, gnssMps: gnssSpeedMps);
      // The grades so far describe the uncorrected model, not the speed the
      // gate will now use: validation starts again on the corrected one.
      if (!wasReady && calibration.isReady) {
        _validationCount = 0;
        _validationMean = 0;
        _validationMeanSquare = 0;
      }
    }
  }

  /// Judges [obs].
  ///
  /// [predictedMps] and [predictedVariance] are the filter's forward speed and
  /// its variance; [engineUs] is the engine's newest IMU time; [applyNow] is
  /// false while GNSS is healthy (the prediction is held for grading, not
  /// used); [sigmaScale] multiplies the model's sigma for the current
  /// disturbance.
  AiSpeedDecision evaluate({
    required AiSpeedObservation obs,
    required int engineUs,
    required double predictedMps,
    required double predictedVariance,
    required bool applyNow,
    required double sigmaScale,
  }) {
    _observed++;
    _lastObservation = obs;

    final dataFault = _dataFault(obs, engineUs);
    if (dataFault != null) return _refuse(dataFault);

    final speed = _corrected(obs.speedMps);
    final innovation = speed - predictedMps;
    _lastInnovation = innovation;
    if (!applyNow) {
      _pending = obs;
      _validatedOnly++;
      return AiSpeedDecision.validatedOnly(innovationMps: innovation);
    }
    if (!validated) return _refuse(AiRejectReason.unvalidated);

    final sigma = math.max(obs.sigmaMps, _config.floorSigma) * sigmaScale;
    final combined = math.sqrt(predictedVariance + sigma * sigma);
    if (innovation.abs() > _config.physicsDisagreeSigma * combined) {
      return _refuse(AiRejectReason.physicsDisagreement);
    }

    _applied++;
    return AiSpeedDecision.applied(
      sigmaUsedMps: _withinContribution(predictedVariance, sigma),
      innovationMps: innovation,
      speedMps: speed,
    );
  }

  /// Checks 1-6: the ones that are about the observation itself.
  AiRejectReason? _dataFault(AiSpeedObservation obs, int engineUs) {
    if (!obs.speedMps.isFinite ||
        obs.speedMps < 0 ||
        !obs.sigmaMps.isFinite ||
        obs.sigmaMps <= 0 ||
        !obs.latencyMs.isFinite ||
        !obs.featureZMax.isFinite) {
      return AiRejectReason.invalid;
    }
    final last = _lastObservationUs;
    if (last != null && obs.monotonicUs <= last) {
      return AiRejectReason.outOfOrder;
    }
    _lastObservationUs = obs.monotonicUs;
    if (obs.windowsFed < _config.warmupWindows) return AiRejectReason.warmup;
    final queuedMs = math.max(0, engineUs - obs.monotonicUs) / 1000;
    if (obs.latencyMs + queuedMs > _config.maxLatencyMs) {
      return AiRejectReason.latency;
    }
    if (obs.featureZMax > _config.maxFeatureZ) {
      return AiRejectReason.offDistribution;
    }
    if (obs.speedMps > _config.maxSpeed) return AiRejectReason.overSpeed;
    return null;
  }

  AiSpeedDecision _refuse(AiRejectReason reason) {
    _rejected[reason] = (_rejected[reason] ?? 0) + 1;
    _lastReject = reason;
    return AiSpeedDecision.rejected(reason);
  }

  /// Folds one prediction-minus-GNSS-speed error into the running mean and
  /// mean-square: a plain average until the window fills, then an exponential
  /// one that remembers about `validationWindowSamples` pairs.
  void _grade(double innovation) {
    _validationCount++;
    final weight =
        1.0 / math.min(_validationCount, _config.validationWindowSamples);
    _validationMean += weight * (innovation - _validationMean);
    _validationMeanSquare +=
        weight * (innovation * innovation - _validationMeanSquare);
  }

  /// The sigma that makes this update's gain `P / (P + sigma^2)` fit the
  /// configured range, or [sigma] itself, untouched, when it already does.
  double _withinContribution(double variance, double sigma) {
    if (!(variance > 0)) return sigma;
    final gain = variance / (variance + sigma * sigma);
    final ceiling = _config.maxContribution;
    final floor = _config.minContribution;
    double? target;
    if (gain > ceiling) {
      target = ceiling;
    } else if (floor > 0 && gain < floor) {
      target = floor;
    }
    if (target == null || target <= 0 || target >= 1) return sigma;
    return math.sqrt(variance * (1 - target) / target);
  }
}
