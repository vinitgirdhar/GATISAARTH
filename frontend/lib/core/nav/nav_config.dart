import 'package:flutter/foundation.dart';

import 'ai/ai_config.dart';

export 'ai/ai_config.dart';

/// Every tunable the navigation core has, in one versioned place (§70).
///
/// Nothing in `lib/core/nav/` may hard-code a threshold, a covariance or a
/// timeout: it comes from here, so a change is reviewable, diffable and can be
/// recorded alongside a drive log for reproducibility.
///
/// The defaults are **engineering priors**, not measured results. Any value
/// documented as "measured" must cite the drive it came from.
@immutable
class NavConfig {
  const NavConfig({
    this.version = currentVersion,
    this.sensors = const SensorConfig(),
    this.calibration = const CalibrationConfig(),
    this.alignment = const AlignmentConfig(),
    this.sensorFault = const SensorFaultConfig(),
    this.barometer = const BarometerConfig(),
    this.ins = const InsConfig(),
    this.ekf = const EkfConfig(),
    this.gnss = const GnssConfig(),
    this.motion = const MotionConfig(),
    this.ai = const AiConfig(),
    this.disturbance = const DisturbanceConfig(),
    this.mapMatch = const MapMatchConfig(),
    this.roadFollow = const RoadFollowConfig(),
    this.power = const PowerConfig(),
    this.features = const FeatureFlags(),
  });

  /// Bumped whenever a default changes in a way that alters trajectories, so a
  /// replay can refuse to compare results produced under different constants.
  static const int currentVersion = 1;

  final int version;
  final SensorConfig sensors;
  final CalibrationConfig calibration;
  final AlignmentConfig alignment;
  final SensorFaultConfig sensorFault;
  final BarometerConfig barometer;
  final InsConfig ins;
  final EkfConfig ekf;
  final GnssConfig gnss;
  final MotionConfig motion;
  final AiConfig ai;
  final DisturbanceConfig disturbance;
  final MapMatchConfig mapMatch;
  final RoadFollowConfig roadFollow;
  final PowerConfig power;
  final FeatureFlags features;

  static const NavConfig defaults = NavConfig();

  /// v3.1 phone policy. The model must pass live GNSS validation before any
  /// outage update. Disturbance handling uses the statistical estimator;
  /// proxy-trained neural trust models remain excluded from production fusion.
  /// Real replay evidence: docs/evidence/codex_ai_ablation_*.json.
  static const NavConfig live = NavConfig(
    ai: AiConfig(enabled: true, fusionTrust: false),
  );

  NavConfig copyWith({
    SensorConfig? sensors,
    CalibrationConfig? calibration,
    AlignmentConfig? alignment,
    SensorFaultConfig? sensorFault,
    BarometerConfig? barometer,
    InsConfig? ins,
    EkfConfig? ekf,
    GnssConfig? gnss,
    MotionConfig? motion,
    AiConfig? ai,
    DisturbanceConfig? disturbance,
    MapMatchConfig? mapMatch,
    RoadFollowConfig? roadFollow,
    PowerConfig? power,
    FeatureFlags? features,
  }) =>
      NavConfig(
        version: version,
        sensors: sensors ?? this.sensors,
        calibration: calibration ?? this.calibration,
        alignment: alignment ?? this.alignment,
        sensorFault: sensorFault ?? this.sensorFault,
        barometer: barometer ?? this.barometer,
        ins: ins ?? this.ins,
        ekf: ekf ?? this.ekf,
        gnss: gnss ?? this.gnss,
        motion: motion ?? this.motion,
        ai: ai ?? this.ai,
        disturbance: disturbance ?? this.disturbance,
        mapMatch: mapMatch ?? this.mapMatch,
        roadFollow: roadFollow ?? this.roadFollow,
        power: power ?? this.power,
        features: features ?? this.features,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'sensors': sensors.toJson(),
        'ekf': ekf.toJson(),
        'gnss': gnss.toJson(),
        'motion': motion.toJson(),
        'ai': ai.toJson(),
        'disturbance': disturbance.toJson(),
        'features': features.toJson(),
      };
}

/// Which parts of the fusion are switched on (§40).
///
/// Exists so an ablation can be *measured* rather than argued about: turn
/// one constraint off, replay the same log, compare the drift. A claim that
/// a component helps is only worth making when this has been run.
@immutable
class FeatureFlags {
  const FeatureFlags({
    this.zeroVelocityUpdate = true,
    this.zeroAngularRateUpdate = true,
    this.nonHolonomicConstraint = true,
    this.magnetometerHeading = true,
    this.mapHeading = true,
    this.adaptiveGnssCovariance = true,
    this.gnssVelocity = true,
    this.neuralVelocity = false,
  });

  /// Everything off: pure inertial propagation, corrected only by GNSS
  /// position. The baseline every other row is measured against.
  static const FeatureFlags rawInertial = FeatureFlags(
    zeroVelocityUpdate: false,
    zeroAngularRateUpdate: false,
    nonHolonomicConstraint: false,
    magnetometerHeading: false,
    mapHeading: false,
    adaptiveGnssCovariance: false,
    gnssVelocity: false,
  );

  final bool zeroVelocityUpdate;
  final bool zeroAngularRateUpdate;
  final bool nonHolonomicConstraint;
  final bool magnetometerHeading;
  final bool mapHeading;

  /// Scale the GNSS measurement covariance by the quality score (§12), or
  /// take the receiver's reported accuracy at face value.
  final bool adaptiveGnssCovariance;

  final bool gnssVelocity;

  /// Off, and it stays off until a real model loads and a replay shows it
  /// helps. Mirrors `AiConfig.enabled` (§8, §83).
  final bool neuralVelocity;

  FeatureFlags copyWith({
    bool? zeroVelocityUpdate,
    bool? zeroAngularRateUpdate,
    bool? nonHolonomicConstraint,
    bool? magnetometerHeading,
    bool? mapHeading,
    bool? adaptiveGnssCovariance,
    bool? gnssVelocity,
    bool? neuralVelocity,
  }) =>
      FeatureFlags(
        zeroVelocityUpdate: zeroVelocityUpdate ?? this.zeroVelocityUpdate,
        zeroAngularRateUpdate:
            zeroAngularRateUpdate ?? this.zeroAngularRateUpdate,
        nonHolonomicConstraint:
            nonHolonomicConstraint ?? this.nonHolonomicConstraint,
        magnetometerHeading:
            magnetometerHeading ?? this.magnetometerHeading,
        mapHeading: mapHeading ?? this.mapHeading,
        adaptiveGnssCovariance:
            adaptiveGnssCovariance ?? this.adaptiveGnssCovariance,
        gnssVelocity: gnssVelocity ?? this.gnssVelocity,
        neuralVelocity: neuralVelocity ?? this.neuralVelocity,
      );

  Map<String, dynamic> toJson() => {
        'zupt': zeroVelocityUpdate,
        'zaru': zeroAngularRateUpdate,
        'nhc': nonHolonomicConstraint,
        'mag': magnetometerHeading,
        'mapHeading': mapHeading,
        'adaptiveGnss': adaptiveGnssCovariance,
        'gnssVelocity': gnssVelocity,
        'neuralVelocity': neuralVelocity,
      };
}

/// Sampling and time-synchronisation limits (§4).
@immutable
class SensorConfig {
  const SensorConfig({
    this.maxFusionHz = 100,
    this.reorderWindow = const Duration(milliseconds: 200),
    this.staleSample = const Duration(milliseconds: 500),
    this.queueLimit = 512,
    this.rateEstimatorAlpha = 0.05,
    this.gapFactor = 3.0,
    this.excellentJitterRatio = 0.15,
    this.goodJitterRatio = 0.35,
    this.degradedDropRate = 0.05,
    this.capabilityProbe = const Duration(seconds: 3),
  });

  /// Upper bound on EKF prediction rate. Phones can deliver 200-500 Hz in
  /// "fastest" mode; predicting that often buys nothing and costs battery.
  final int maxFusionHz;

  /// How far out of order a sample may arrive and still be re-sequenced.
  final Duration reorderWindow;

  /// Beyond this, the last sample of a stream no longer counts as live.
  final Duration staleSample;

  /// Per-stream bounded buffer. Overflow drops oldest and counts it (§46).
  final int queueLimit;

  /// EWMA weight for the per-sensor interval estimate.
  final double rateEstimatorAlpha;

  /// A gap longer than this many expected intervals is counted as dropped
  /// samples rather than jitter.
  final double gapFactor;

  /// Jitter (stddev/mean of the interval) below this is `excellent`.
  final double excellentJitterRatio;

  /// ...and below this, `good`.
  final double goodJitterRatio;

  /// Above this drop fraction a stream is `degraded` regardless of jitter.
  final double degradedDropRate;

  /// A sensor that emits nothing within this window is reported unavailable
  /// rather than "still waiting" (§3 capability detection).
  final Duration capabilityProbe;

  Map<String, dynamic> toJson() => {
        'maxFusionHz': maxFusionHz,
        'reorderWindowMs': reorderWindow.inMilliseconds,
        'queueLimit': queueLimit,
        'gapFactor': gapFactor,
      };
}

/// Calibration estimation and persistence (§5).
@immutable
class CalibrationConfig {
  const CalibrationConfig({
    this.quickDuration = const Duration(seconds: 15),
    this.fullDuration = const Duration(seconds: 60),
    this.stillAccelStd = 0.08,
    this.stillGyroStd = 0.015,
    this.minSamples = 200,
    this.maxGyroBias = 0.2,
    this.maxAccelBias = 1.5,
    this.magFitMinSpread = 8.0,
    this.staleAfter = const Duration(days: 14),
    this.invalidateOnTempDeltaC = 15.0,
  });

  final Duration quickDuration;
  final Duration fullDuration;

  /// Accelerometer magnitude stddev (m/s²) under which the phone counts as
  /// still enough to average a bias from.
  final double stillAccelStd;

  /// Gyroscope magnitude stddev (rad/s) for the same test.
  final double stillGyroStd;

  /// Minimum still samples before a bias estimate is published at all.
  final int minSamples;

  /// Estimates beyond these are rejected as a bad calibration rather than
  /// stored (a moving phone, or a genuinely faulty sensor).
  final double maxGyroBias; // rad/s
  final double maxAccelBias; // m/s²

  /// Minimum µT spread across each axis before a hard-iron fit is trusted.
  final double magFitMinSpread;

  /// Stored calibration older than this is re-estimated.
  final Duration staleAfter;

  /// MEMS bias moves with die temperature; a swing this large invalidates a
  /// stored calibration (§5 "invalidated when device conditions change").
  final double invalidateOnTempDeltaC;
}

/// Phone-to-vehicle frame alignment (§6).
@immutable
class AlignmentConfig {
  const AlignmentConfig({
    this.gravityAlpha = 0.998,
    this.minLongitudinalAccel = 0.5,
    this.maxYawRateWhileFitting = 0.08,
    this.maxGravityDrift = 0.25,
    this.minSamples = 400,
    this.minEvents = 20,
    this.dvdtHoldFor = const Duration(milliseconds: 1500),
    this.dvdtConsistencyMin = 0.4,
    this.dvdtConsistencyMax = 2.5,
    this.minExcitation = 0.6,
    this.minR2 = 0.45,
    this.minStability = 0.85,
    this.convergedConfidence = 0.6,
    this.reestimateAfter = const Duration(minutes: 20),
  });

  /// Low-pass weight for the gravity estimate in the phone frame. Higher is
  /// slower and steadier; the mount does not move, so slow is right.
  final double gravityAlpha;

  /// Only accelerate/brake events above this (m/s², from the GNSS speed
  /// derivative) carry forward-axis information. Noise around zero carries
  /// none and would pull the estimate towards whatever direction the noise
  /// happens to sit in.
  final double minLongitudinalAccel;

  /// Fitting only happens while the vehicle is going straight; in a turn the
  /// horizontal acceleration is dominated by the lateral component.
  final double maxYawRateWhileFitting; // rad/s

  /// If the gravity direction in the phone frame moves more than this
  /// (radians) the phone has shifted in its mount and the fit restarts.
  final double maxGravityDrift;

  /// Minimum accepted IMU samples before any estimate is published.
  final int minSamples;

  /// Minimum number of distinct GNSS speed-change intervals the fit must
  /// have seen.
  ///
  /// This, not the raw sample count, is the real information measure: GNSS
  /// arrives at 1 Hz, so one braking event contributes one independent
  /// longitudinal-acceleration observation however many IMU samples fall
  /// inside it. The IMU samples still help, by averaging down accelerometer
  /// noise on the direction, but they are not independent evidence that the
  /// vehicle changed speed.
  final int minEvents;

  /// How long a GNSS-derived acceleration stays applicable to incoming IMU
  /// samples. Beyond this the vehicle may have stopped accelerating.
  final Duration dvdtHoldFor;

  /// A sample is only used when its measured horizontal acceleration is within
  /// these factors of the GNSS-derived one.
  ///
  /// The GNSS derivative is an average over a whole second, while the
  /// accelerometer is instantaneous, so the two disagree badly exactly where
  /// the vehicle stops accelerating: the held value says 1.8 m/s² while the
  /// phone reads nothing. Feeding those samples in tells the regression that a
  /// large acceleration produced no measurable force, which drags the fit and
  /// tanks its R². Requiring rough agreement keeps only the samples where the
  /// two instruments are describing the same event, and incidentally throws out
  /// bumps and turns for free.
  final double dvdtConsistencyMin;
  final double dvdtConsistencyMax;

  /// Minimum standard deviation of the longitudinal acceleration across the
  /// fit (m/s²). Without real speed changes there is nothing to regress on.
  final double minExcitation;

  /// Minimum regression R² for the fit to be believed.
  final double minR2;

  /// Minimum agreement (cosine) between the first and second half of the fit.
  final double minStability;

  /// Confidence at or above which the UI may say "Mount calibrated" (§6).
  final double convergedConfidence;

  /// Re-run the estimate this often even after convergence — phones slip.
  final Duration reestimateAfter;
}

/// Sensor fault detection (§29).
@immutable
class SensorFaultConfig {
  const SensorFaultConfig({
    this.windowSamples = 50,
    this.frozenSamples = 50,
    this.maxAccelMagnitude = 100,
    this.maxGyroMagnitude = 35,
    this.maxAccelNoise = 12,
    this.maxGyroNoise = 6,
    this.minFieldMicroTesla = 15,
    this.maxFieldMicroTesla = 90,
  });

  final int windowSamples;

  /// Consecutive byte-identical readings before a sensor counts as frozen.
  /// Real MEMS always jitters at the least significant bit.
  final int frozenSamples;

  /// Physical limits. A phone that reads beyond these has a fault, not a
  /// manoeuvre: 100 m/s² is 10 g, 35 rad/s is 2000 deg/s.
  final double maxAccelMagnitude; // m/s²
  final double maxGyroMagnitude; // rad/s

  /// Noise beyond this is a broken sensor rather than a rough road. Indian
  /// roads are why these are generous.
  final double maxAccelNoise; // m/s² std
  final double maxGyroNoise; // rad/s std

  /// Earth's magnetic field is 25-65 µT everywhere on the surface. Readings
  /// outside this band are measuring the vehicle, not the planet.
  final double minFieldMicroTesla;
  final double maxFieldMicroTesla;
}

/// Barometric altitude (§18).
@immutable
class BarometerConfig {
  const BarometerConfig({
    this.smoothing = 0.85,
    this.motionRateMps = 0.35,
    this.levelChangeM = 2.5,
    this.baseSigmaM = 1.5,
    this.driftSigmaMPerHour = 9.0,
    this.maxUsableSigmaM = 25.0,
  });

  final double smoothing;

  /// Vertical rate above which the vehicle counts as climbing or descending.
  final double motionRateMps;

  /// Height step that counts as a new level — a car-park floor or a ramp.
  final double levelChangeM;

  /// Uncertainty of a freshly anchored barometric altitude.
  final double baseSigmaM;

  /// How fast that uncertainty grows once the GNSS anchor goes stale.
  ///
  /// Sea-level pressure moves with the weather by roughly a hectopascal an
  /// hour, and a hectopascal is about 8 m. This is why a barometer is a
  /// relative instrument that happens to be anchorable, not an altimeter.
  final double driftSigmaMPerHour;

  /// Past this the barometric altitude is too vague to be worth a filter
  /// update at all.
  final double maxUsableSigmaM;
}

/// Strapdown mechanization limits (§10, §62).
@immutable
class InsConfig {
  const InsConfig({
    this.maxDt = 0.2,
    this.minDt = 0.0005,
    this.maxSpeed = 90.0,
    this.maxAccel = 60.0,
    this.maxAngularRate = 20.0,
    this.quaternionRenormEvery = 1,
  });

  /// A gap longer than this is a dropout, not an integration step; the INS
  /// coasts instead of integrating a stale rate across it.
  final double maxDt;
  final double minDt;

  /// Hard sanity limits. Exceeding them marks the state invalid rather than
  /// letting a spike propagate (§62).
  final double maxSpeed; // m/s (~324 km/h)
  final double maxAccel; // m/s²
  final double maxAngularRate; // rad/s

  final int quaternionRenormEvery;
}

/// Error-state filter noise and gating (§11, §12, §14).
@immutable
class EkfConfig {
  const EkfConfig({
    this.initialPositionSigma = 25.0,
    this.initialVelocitySigma = 2.0,
    this.initialAttitudeSigma = 0.35,
    this.levelledAttitudeSigma = 0.05,
    this.initialYawSigma = 1.6,
    this.initialAccelBiasSigma = 0.25,
    this.initialGyroBiasSigma = 0.02,
    this.accelNoiseDensity = 0.08,
    this.gyroNoiseDensity = 0.006,
    this.accelBiasRandomWalk = 0.0008,
    this.gyroBiasRandomWalk = 5e-5,
    this.accelBiasTau = 600.0,
    this.gyroBiasTau = 600.0,
    this.zuptVelocitySigma = 0.02,
    this.zaruSigma = 0.004,
    this.nhcSigmaCar = 0.15,
    this.nhcSigmaTwoWheeler = 0.6,
    this.baroSigma = 1.5,
    this.magYawSigma = 0.25,
    this.covarianceFloor = 1e-12,
    this.minAccelBiasSigma = 0.03,
    this.minGyroBiasSigma = 0.0012,
    this.maxPositionSigma = 5000.0,
    this.gateConfidence = 0.99,
    this.consecutiveRejectLimit = 8,
  });

  final double initialPositionSigma; // m
  final double initialVelocitySigma; // m/s
  /// Roll/pitch prior when the attitude was NOT seeded from gravity.
  final double initialAttitudeSigma; // rad

  /// Roll/pitch prior when the attitude WAS seeded from a settled gravity
  /// estimate (about 3 degrees).
  ///
  /// This one matters more than it looks. Seeding from gravity and then
  /// declaring the seed +/-20 deg uncertain lets the filter discard it and
  /// explain an accelerometer bias as tilt instead — and tilt is a 9.8 m/s^2
  /// per radian lever on horizontal acceleration, so a few degrees of wrong
  /// pitch dwarfs every other dead-reckoning error.
  final double levelledAttitudeSigma; // rad
  final double initialYawSigma; // rad, yaw is nearly unobservable at rest
  final double initialAccelBiasSigma; // m/s²
  final double initialGyroBiasSigma; // rad/s

  /// Continuous-time noise densities for a mid-range phone MEMS IMU.
  /// Units: m/s²/√Hz and rad/s/√Hz.
  final double accelNoiseDensity;
  final double gyroNoiseDensity;

  /// Bias random-walk driving terms and Gauss-Markov correlation times (s).
  final double accelBiasRandomWalk;
  final double gyroBiasRandomWalk;
  final double accelBiasTau;
  final double gyroBiasTau;

  /// Measurement sigmas for the pseudo-measurements.
  final double zuptVelocitySigma; // m/s
  final double zaruSigma; // rad/s
  final double nhcSigmaCar; // m/s lateral/vertical
  final double nhcSigmaTwoWheeler; // m/s, looser: the bike leans
  final double baroSigma; // m
  final double magYawSigma; // rad

  /// Diagonal floor so a covariance can never collapse to singular (§62).
  final double covarianceFloor;

  /// Floors on how well the biases can ever be claimed to be known.
  ///
  /// Without these the filter drives its bias variance towards zero while
  /// GNSS is healthy, then enters an outage believing it knows the bias
  /// exactly. It does not: accelerometer bias is entangled with tilt (see
  /// the class docs on NavigationFilter), both move with temperature, and
  /// neither is observable during steady cruise. Measured consequence:
  /// without the floor, a 300 s outage produced 404 m of error while the
  /// filter still reported a 65 m sigma — wrong *and* confident, which is
  /// the one failure mode §28 exists to prevent.
  final double minAccelBiasSigma; // m/s²
  final double minGyroBiasSigma; // rad/s

  /// Beyond this the estimate is not usable and integrity drops to INVALID.
  final double maxPositionSigma;

  /// Chi-square gate confidence for measurement acceptance.
  final double gateConfidence;

  /// This many consecutive rejections of one measurement type means the filter
  /// (not the measurement) is probably wrong — it inflates covariance rather
  /// than rejecting forever.
  final int consecutiveRejectLimit;

  Map<String, dynamic> toJson() => {
        'accelNoiseDensity': accelNoiseDensity,
        'gyroNoiseDensity': gyroNoiseDensity,
        'zuptVelocitySigma': zuptVelocitySigma,
        'nhcSigmaCar': nhcSigmaCar,
        'gateConfidence': gateConfidence,
      };
}

/// GNSS quality scoring, rejection and integrity (§13, §14, §15).
@immutable
class GnssConfig {
  const GnssConfig({
    this.staleAfter = const Duration(seconds: 6),
    this.excellentAccuracy = 8.0,
    this.goodAccuracy = 20.0,
    this.degradedAccuracy = 50.0,
    this.maxUsableAccuracy = 120.0,
    this.maxJumpSpeed = 90.0,
    this.maxImpliedAccel = 15.0,
    this.maxHeadingRateDegPerSec = 120.0,
    this.maxLateralAccel = 8.0,
    this.minAccuracyForVelocity = 35.0,
    this.oscillationWindow = 8,
    this.oscillationRadius = 6.0,
    this.integrityJumpSigma = 8.0,
    this.integrityHeadingDisagreeDeg = 60.0,
    this.integrityStrikeWindow = 5,
    this.integrityStrikesForAnomaly = 3,
  });

  /// A fix older than this stops counting as live. Matches the existing
  /// `LiveLocationService.staleAfter` so behaviour does not shift under the
  /// migration.
  final Duration staleAfter;

  /// Horizontal-accuracy band edges (m) for the quality classes.
  final double excellentAccuracy;
  final double goodAccuracy;
  final double degradedAccuracy;

  /// Worse than this and the fix is not used as a measurement at all.
  final double maxUsableAccuracy;

  /// Rejection limits (§14). A fix implying more than this is not physics.
  final double maxJumpSpeed; // m/s between consecutive fixes
  final double maxImpliedAccel; // m/s²
  /// Absolute ceiling on turn rate (deg/s), for a low-speed pivot.
  final double maxHeadingRateDegPerSec;

  /// Hard-cornering lateral acceleration (m/s²). Combined with speed this
  /// bounds the turn rate far more tightly than the absolute ceiling: at
  /// 20 m/s, 8 m/s² of grip is only 23 deg/s, so a GNSS bearing that swings
  /// 170 deg in a second is not a vehicle manoeuvre.
  final double maxLateralAccel;

  /// GNSS velocity is only used as a measurement when the fix is at least
  /// this accurate; below that the Doppler speed is usually noise.
  final double minAccuracyForVelocity;

  /// Multipath signature: N recent fixes confined to a small radius while the
  /// IMU says the vehicle is moving (§23).
  final int oscillationWindow;
  final double oscillationRadius; // m

  /// Integrity (§15): a fix this many sigmas from the prediction, or a GNSS
  /// heading disagreeing with inertial heading by this much, is a strike.
  final double integrityJumpSigma;
  final double integrityHeadingDisagreeDeg;
  final int integrityStrikeWindow;
  final int integrityStrikesForAnomaly;

  Map<String, dynamic> toJson() => {
        'staleAfterMs': staleAfter.inMilliseconds,
        'maxUsableAccuracy': maxUsableAccuracy,
        'maxJumpSpeed': maxJumpSpeed,
        'maxImpliedAccel': maxImpliedAccel,
      };
}

/// Motion classification, ZUPT and vehicle constraints (§7, §16, §17).
@immutable
class MotionConfig {
  const MotionConfig({
    this.zuptAccelStd = 0.22,
    this.zuptMaxHorizontalAccel = 0.8,
    this.zuptGyroStd = 0.035,
    this.zuptEnterDelay = const Duration(milliseconds: 600),
    this.zuptExitDelay = const Duration(milliseconds: 250),
    this.zuptMaxGnssSpeed = 0.6,
    this.zuptMaxFilterSpeed = 2.5,
    this.turningYawRate = 0.15,
    this.sharpTurnYawRate = 0.5,
    this.nhcMaxYawRate = 0.6,
    this.roughRms = 1.6,
    this.severeRms = 3.2,
    this.potholeNetAccel = 7.0,
    this.speedBreakerNetAccel = 4.5,
    this.anomalyRefractory = const Duration(milliseconds: 2500),
    this.hardBrakingAccel = -3.0,
    this.leanRateThreshold = 0.25,
  });

  /// Stationary gate. Unlike the old variance-only rule this is *combined*
  /// with gyro stillness and, when present, GNSS speed, so a smooth cruise no
  /// longer looks like a stop (§16).
  final double zuptAccelStd; // m/s²

  /// Maximum horizontal specific force (m/s²) in the vehicle frame for the
  /// vehicle to count as stopped.
  ///
  /// This is the test a variance-based gate cannot do: a *constant*
  /// acceleration has no variance at all, so pulling away from a light at a
  /// steady 1.8 m/s² looks perfectly still to it, and a stale GNSS speed will
  /// not veto it for up to a second. The horizontal specific force, by
  /// contrast, is 1.8 immediately.
  ///
  /// The limit is what a stationary vehicle on a slope reads: 0.8 m/s² is a
  /// 4.7 degree gradient, so a stop on a steeper hill than that will be
  /// missed, and no zero-velocity update applied. Missing a stop costs
  /// accuracy; inventing one corrupts the attitude, which is far worse.
  final double zuptMaxHorizontalAccel; // m/s²
  final double zuptGyroStd; // rad/s

  /// Hysteresis: the gate must hold this long to enter, and clear this long
  /// to exit, which stops moving/stopped chatter.
  final Duration zuptEnterDelay;
  final Duration zuptExitDelay;

  /// If GNSS is live and reports more than this, never declare a stop.
  final double zuptMaxGnssSpeed;

  /// If the filter already believes the vehicle is going faster than this,
  /// do not declare a stop on IMU stillness alone. A smooth cruise and a stop
  /// are genuinely indistinguishable to an IMU; this prior stops the old
  /// false-stop failure without the previous 3 s fudge.
  final double zuptMaxFilterSpeed;

  final double turningYawRate; // rad/s
  final double sharpTurnYawRate; // rad/s

  /// Above this yaw rate the non-holonomic assumption is weakest (tyre slip,
  /// body roll), so the NHC update is suppressed (§17).
  final double nhcMaxYawRate;

  final double roughRms;
  final double severeRms;
  final double potholeNetAccel;
  final double speedBreakerNetAccel;
  final Duration anomalyRefractory;
  final double hardBrakingAccel;

  /// Roll rate above which a two-wheeler counts as leaning, which relaxes the
  /// lateral constraint instead of forcing a car-like zero.
  final double leanRateThreshold; // rad/s

  Map<String, dynamic> toJson() => {
        'zuptAccelStd': zuptAccelStd,
        'zuptGyroStd': zuptGyroStd,
        'nhcMaxYawRate': nhcMaxYawRate,
      };
}

/// HMM map matching (§19, §20, §21).
@immutable
class MapMatchConfig {
  const MapMatchConfig({
    this.enabled = false,
    this.searchRadius = 60.0,
    this.maxCandidates = 8,
    this.windowSize = 10,
    this.headingToleranceDeg = 45.0,
    this.transitionBeta = 12.0,
    this.snapThreshold = 0.6,
    this.runnerUpMargin = 0.15,
    this.maxSnapDistanceSigma = 2.5,
    this.headingFeedbackMinConfidence = 0.75,
    this.continuationDeg = 25.0,
  });

  /// **Off by default** — `maps/processed_graphs/road_edges.json` is
  /// `{"edges": []}`. There is no graph to match against yet (§19, §83).
  final bool enabled;

  final double searchRadius; // m
  final int maxCandidates;
  final int windowSize;
  final double headingToleranceDeg;

  /// Transition-probability decay: |route distance - straight distance| / beta.
  final double transitionBeta;

  /// Only snap when the best candidate clears this posterior...
  final double snapThreshold;

  /// ...and beats the runner-up by this margin. Parallel roads and flyovers
  /// are exactly where a confident-looking single candidate is wrong (§21).
  final double runnerUpMargin;

  /// How far from the road the estimate may be, in filter sigmas, and still
  /// be snapped onto it.
  ///
  /// The posterior alone cannot carry this: it is a softmax over the roads
  /// *considered*, so a single road 50 m away scores 1.0 simply because
  /// nothing competed with it. This is the separate question of whether the
  /// vehicle is plausibly on a road at all.
  final double maxSnapDistanceSigma;

  /// Road heading only feeds the filter above this match confidence (§58).
  final double headingFeedbackMinConfidence;

  /// Two edges that share a node and differ in direction by less than this are
  /// one road (a graph cut at every junction splits a road into a chain), so
  /// their probability is pooled instead of counted as rivals.
  final double continuationDeg;
}

/// Locking the dead-reckoned marker onto the road network (`RoadFollower`).
///
/// Real graphs come from vector tiles: one long edge runs through many
/// crossings and neighbouring tiles overlap, so nothing here relies on node
/// ids. Everything is geometric, which is why so many of these are metres.
@immutable
class RoadFollowConfig {
  const RoadFollowConfig({
    this.headingWeightMPerDeg = 0.1,
    this.joinToleranceM = 3.0,
    this.lookAheadM = 8.0,
    this.minExitLengthM = 1.0,
    this.maxExitDeviationDeg = 120.0,
    this.straightBiasDeg = 12.0,
    this.turnYawThresholdDeg = 35.0,
    this.turnRelockRadiusM = 30.0,
    this.turnRelockHeadingTolDeg = 35.0,
    this.yawLeakMeters = 200.0,
    this.maxHopsPerAdvance = 64,
    this.rebindRadiusM = 8.0,
    this.correctMinPerpM = 25.0,
    this.candidateLimit = 32,
    this.ringMinLengthM = 20.0,
    this.recentEdgeWindowM = 30.0,
  });

  /// Metres of perpendicular distance one degree of heading disagreement
  /// costs when choosing a road: 0.1 makes a 180 degree mismatch worth 18 m,
  /// enough to pick the right one of two parallel roads, not enough to snap
  /// to a road that is far away just because it points the right way.
  final double headingWeightMPerDeg;

  /// How far from the end of an edge another edge may pass and still count as
  /// joined to it. Tile borders and digitising leave gaps of a metre or two.
  final double joinToleranceM;

  /// How far along an exit road its bearing is measured. Longer than the
  /// digitising jitter at the junction, shorter than a bend.
  final double lookAheadM;

  /// An exit needs at least this much road ahead of the join, otherwise the
  /// "join" is the far end of a stub and taking it goes nowhere.
  final double minExitLengthM;

  /// Exits turning further than this from where the vehicle is pointing are
  /// never taken, so a U-turn is impossible while a T's +/-90 degree exits
  /// stay legal.
  final double maxExitDeviationDeg;

  /// Exits within this many degrees of the best one are ranked by road name,
  /// class and only then by angle, so a vehicle carries on along the same
  /// road through a crossing instead of being tugged by a side street.
  final double straightBiasDeg;

  /// Vehicle turning the road's own curvature does not explain, beyond which
  /// the vehicle is assumed to be turning off onto a crossing road that sits
  /// mid-edge.
  final double turnYawThresholdDeg;

  /// How far around the vehicle a crossing road is looked for once a turn is
  /// detected. Covers a driver who starts the turn early or late.
  final double turnRelockRadiusM;

  /// How well a crossing road's bearing must match the detected turn.
  final double turnRelockHeadingTolDeg;

  /// Distance over which unexplained turning fades to 1/e. Gyroscope bias
  /// integrates without bound; this bounds it (a 0.02 deg/m bias settles at
  /// 4 degrees) while a real turn, done in tens of metres, survives.
  final double yawLeakMeters;

  /// Junctions crossed in one `advance` call. A guard against a degenerate
  /// graph, never reached on a real one at 1 m steps.
  final int maxHopsPerAdvance;

  /// Search radius when the graph is swapped under a locked follower. The
  /// same road in the new graph sits on top of the old position.
  final double rebindRadiusM;

  /// A noisy fix this far off the road (or 2 sigma, if larger) is not evidence
  /// about where along the road the vehicle is.
  final double correctMinPerpM;

  /// A closed edge shorter than this is a digitising artefact (a sliver cut
  /// off at a junction), not a roundabout or a loop street. Treating one as a
  /// ring traps the follower on it, going round and round.
  final double ringMinLengthM;

  /// A junction exit is never onto an edge entered within this many metres of
  /// driving: that is the road just left, and taking it again is how a chain
  /// of slivers becomes a loop.
  final double recentEdgeWindowM;

  /// Candidate roads examined per lookup. Bounds the cost in a dense junction.
  final int candidateLimit;
}

/// Thermal and battery operating modes (§30, §31).
@immutable
class PowerConfig {
  const PowerConfig({
    this.balancedTempC = 42.0,
    this.powerSaveTempC = 45.0,
    this.thermalSaveTempC = 48.0,
    this.lowBatteryPercent = 20,
    this.criticalBatteryPercent = 10,
    this.idleAiWhenGnssHealthy = true,
    this.uiHz = 10,
    this.reducedUiHz = 4,
  });

  final double balancedTempC;
  final double powerSaveTempC;
  final double thermalSaveTempC;
  final int lowBatteryPercent;
  final int criticalBatteryPercent;

  /// While GNSS is healthy the neural model has nothing to add, so it idles
  /// (§31). This is already how the current app behaves; keep it.
  final bool idleAiWhenGnssHealthy;

  final int uiHz;
  final int reducedUiHz;
}
