import 'package:flutter/foundation.dart';

/// AI in the navigation loop: a neural forward-speed measurement (P1),
/// disturbance-aware noise (P2) and AI-scaled fusion trust (P3).
///
/// Lives beside `NavConfig` (which re-exports it) so the AI knobs read in one
/// place. The rule of that file still holds: nothing under `lib/core/nav/` may
/// hard-code a threshold, and every default here is an **engineering prior**,
/// not a measurement.
@immutable
class AiConfig {
  const AiConfig({
    this.enabled = false,
    this.speedMeasurement = true,
    this.disturbanceAdaptation = true,
    this.fusionTrust = true,
    this.feedHz = 10,
    this.windowSamples = 20,
    this.warmupWindows = 10,
    this.maxLatencyMs = 40,
    this.maxFeatureZ = 6.0,
    this.minContribution = 0.0,
    this.maxContribution = 0.8,
    this.physicsDisagreeSigma = 4.0,
    this.floorSigma = 0.4,
    this.maxSpeed = 45.0,
    this.validationMinSamples = 30,
    this.validationMaxRmse = 1.0,
    this.validationMaxBias = 0.3,
    this.validationWindowSamples = 100,
    this.validationPairWindow = const Duration(milliseconds: 250),
    this.modelOutputTtl = const Duration(seconds: 1),
    this.minGnssTrust = 0.2,
    this.minInsTrust = 0.25,
    this.perVehicleCalibration = false,
    this.calibrationWindowSamples = 300,
    this.calibrationMinSamples = 30,
    this.calibrationMinSpeedSpreadMps = 2.0,
    this.calibrationScaleMin = 0.7,
    this.calibrationScaleMax = 1.4,
  });

  /// **Off by default.** Master switch: while false the engine ignores every
  /// AI input and behaves exactly as it did before the AI path existed
  /// (bit-identical, which `ai_disabled_identity_test.dart` pins).
  ///
  /// It stays off until a replay shows the AI helps: the shipped model's own
  /// benchmark (`ml/evaluation/metrics/08_*.json`) reports worse drift than
  /// classical DR, the vibration and motion-quality assets are still Git-LFS
  /// pointers, and the synthetic evidence in `test/nav/ai_speed_replay_test.dart`
  /// is a bound on the mechanism, not a field measurement (§8, §83).
  final bool enabled;

  /// Sub-switches, effective only while [enabled] is true, so an ablation can
  /// attribute a result to one part.
  final bool speedMeasurement;
  final bool disturbanceAdaptation;
  final bool fusionTrust;

  final int feedHz;
  final int windowSamples;

  /// Model outputs are ignored until this many windows have been fed.
  final int warmupWindows;

  /// Inference slower than this is dropped from the fusion — a late velocity
  /// is worse than none (§9). The age of the observation (how long it sat
  /// before the engine saw it) counts as latency too.
  final int maxLatencyMs;

  /// Largest standardised feature value still considered in-distribution.
  final double maxFeatureZ;

  /// The share of the innovation one AI update may apply (its Kalman gain) is
  /// clamped to this range; the model never owns the estimate outright (§8
  /// "the fusion layer decides how much to trust it"). Implemented by
  /// inflating the measurement variance until the gain fits.
  final double minContribution;
  final double maxContribution;

  /// Disagreement with the INS forward speed beyond this many combined sigmas
  /// (the model's and the filter's) closes the gate.
  final double physicsDisagreeSigma;

  /// Floor on the model's reported sigma — a heteroscedastic head can be
  /// overconfident, and a zero sigma would dominate every other measurement.
  final double floorSigma; // m/s

  final double maxSpeed; // m/s

  /// Online validation against GNSS Doppler speed while GNSS is healthy.
  ///
  /// The physics gate alone cannot catch a *biased* model on a long outage: the
  /// INS's own uncertainty grows, and with it the disagreement that is still
  /// "plausible". So the model has to earn the right first. Whenever a usable
  /// fix carries a Doppler speed, the model's newest prediction (within
  /// [validationPairWindow] of it) is compared with that speed: a reference that
  /// does not share the INS's failure modes, and the reason this is not the
  /// filter's own forward speed (which lags, and is biased, exactly where the
  /// model is most needed). The model is let into an outage only if, over at
  /// least [validationMinSamples] such pairs, the RMS error stayed under
  /// [validationMaxRmse] and the mean error under [validationMaxBias] (m/s).
  /// [validationWindowSamples] is how many recent pairs those averages remember.
  final int validationMinSamples;
  final double validationMaxRmse;
  final double validationMaxBias;
  final int validationWindowSamples;
  final Duration validationPairWindow;

  /// A model disturbance estimate or fusion confidence older than this falls
  /// back to the statistical estimate and to a neutral 1.0.
  final Duration modelOutputTtl;

  /// Floors on the AI trust factors, so a model that says "trust nothing" can
  /// inflate a noise term by at most 1/min (5x GNSS variance, 4x INS process
  /// noise by default) and never switch a sensor off.
  final double minGnssTrust;
  final double minInsTrust;

  /// Correct the model's speed per vehicle (gnss ≈ scale · model + offset,
  /// see `SpeedCalibration`) before it is validated or applied. Off until a
  /// real replay shows it helps.
  final bool perVehicleCalibration;

  /// Pairs remembered, pairs needed before correcting, the speed spread
  /// (1-sigma, m/s) needed before the scale (not only the offset) is fitted,
  /// and the band a plausible scale lies in.
  final int calibrationWindowSamples;
  final int calibrationMinSamples;
  final double calibrationMinSpeedSpreadMps;
  final double calibrationScaleMin;
  final double calibrationScaleMax;

  bool get speedActive => enabled && speedMeasurement;
  bool get disturbanceActive => enabled && disturbanceAdaptation;
  bool get fusionActive => enabled && fusionTrust;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'speedMeasurement': speedMeasurement,
        'disturbanceAdaptation': disturbanceAdaptation,
        'fusionTrust': fusionTrust,
        'feedHz': feedHz,
        'maxLatencyMs': maxLatencyMs,
        'maxFeatureZ': maxFeatureZ,
        'maxContribution': maxContribution,
        'physicsDisagreeSigma': physicsDisagreeSigma,
        'floorSigma': floorSigma,
        'validationMaxRmse': validationMaxRmse,
        'validationMaxBias': validationMaxBias,
        'perVehicleCalibration': perVehicleCalibration,
      };
}

/// Statistical disturbance estimation from the accelerometer alone, and how a
/// disturbance turns into noise inflation (P2).
///
/// The estimator needs no model: it high-passes the accelerometer, measures the
/// vibration energy in two bands and watches for shocks. When the vibration and
/// motion-quality TFLite models exist their output replaces the vibration score
/// and quality (never the shock detection), and this is the fallback.
@immutable
class DisturbanceConfig {
  const DisturbanceConfig({
    this.gravityTauS = 2.0,
    this.highPassTauS = 0.08,
    this.bandTauS = 0.02,
    this.energyTauS = 1.0,
    this.halfSaturationRms = 0.6,
    this.highBandWeight = 1.0,
    this.lowScoreBelow = 0.2,
    this.highScoreAbove = 0.6,
    this.joltAccel = 6.0,
    this.shockRmsRatio = 4.0,
    this.energyClipAccel = 2.0,
    this.shockHold = const Duration(milliseconds: 1200),
    this.shockMotionQuality = 0.35,
    this.vibrationQualityWeight = 0.6,
    this.measurementNoiseGain = 2.0,
    this.processNoiseGain = 1.5,
    this.minMotionQuality = 0.25,
    this.maxMeasurementScale = 16.0,
    this.maxProcessScale = 8.0,
    this.maxGap = const Duration(milliseconds: 500),
  });

  /// Time constant of the slow low-pass that tracks gravity, which is what
  /// tells "vertical" from "horizontal" without knowing how the phone is
  /// mounted.
  final double gravityTauS;

  /// Time constant of the high-pass that separates vibration from vehicle
  /// manoeuvres (0.08 s is a corner near 2 Hz: a driver's inputs sit below it,
  /// road texture and engine harmonics above).
  final double highPassTauS;

  /// Time constant of the second, higher corner (0.02 s is near 8 Hz). The
  /// energy above it is the "engine and road-texture" band; the share of the
  /// total is the band ratio.
  final double bandTauS;

  /// Averaging time of the vibration energy.
  final double energyTauS;

  /// High-passed RMS (m/s²) at which the vibration score reads 0.5.
  final double halfSaturationRms;

  /// How much extra weight energy in the upper band gets: vibration that
  /// reaches the sampling limit aliases and rectifies into apparent bias.
  final double highBandWeight;

  /// Class edges on the vibration score: LOW below the first, HIGH from the
  /// second, NORMAL between.
  final double lowScoreBelow;
  final double highScoreAbove;

  /// A horizontal transient this large (m/s²) that the vertical one does not
  /// dominate is a phone knocked in its mount, not a bump. Vertical shocks
  /// reuse `MotionConfig.speedBreakerNetAccel` / `potholeNetAccel`.
  final double joltAccel;

  /// A shock must also stand this many times above the vibration already
  /// there, so a rough road's own texture is not read as a string of potholes.
  final double shockRmsRatio;

  /// One sample's high-passed excursion counts for at most this much towards
  /// the vibration energy: a pothole is a shock, reported and held as one, and
  /// should not also read as seconds of violent vibration.
  final double energyClipAccel;

  /// A shock holds updates that trust the raw readings (ZARU, tilt learning,
  /// the stillness test) for this long after its last sample. Longer than the
  /// motion classifier's one-second window, so the shock has left the
  /// variance it looks at before the hold ends.
  final Duration shockHold;

  /// Motion quality while a shock is being held.
  final double shockMotionQuality;

  /// `quality = 1 - weight * vibrationScore` for the statistical estimate.
  final double vibrationQualityWeight;

  /// The 2.0 and 1.5 of `ml/README.md`:
  /// `R = R0 (1 + 2 V) / Q` and `Qins = Q0 (1 + 1.5 V) / Q`.
  final double measurementNoiseGain;
  final double processNoiseGain;

  /// Motion quality is never divided by less than this, and the two scales are
  /// capped, so a broken model cannot turn a noise term into infinity.
  final double minMotionQuality;
  final double maxMeasurementScale;
  final double maxProcessScale;

  /// A gap between accelerometer samples longer than this restarts the
  /// filters instead of integrating a stale value across it.
  final Duration maxGap;

  Map<String, dynamic> toJson() => {
        'halfSaturationRms': halfSaturationRms,
        'shockRmsRatio': shockRmsRatio,
        'energyClipAccel': energyClipAccel,
        'shockHoldMs': shockHold.inMilliseconds,
        'measurementNoiseGain': measurementNoiseGain,
        'processNoiseGain': processNoiseGain,
        'minMotionQuality': minMotionQuality,
        'maxMeasurementScale': maxMeasurementScale,
        'maxProcessScale': maxProcessScale,
      };
}
