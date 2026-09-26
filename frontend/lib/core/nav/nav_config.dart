import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ai/ai_config.dart';
import 'map/road_graph.dart' show RoadClass;

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
    this.turnSpeed = const TurnSpeedConfig(),
    this.vibrationSpeed = const VibrationSpeedConfig(),
    this.tunnel = const TunnelConfig(),
    this.parkingLevel = const ParkingLevelConfig(),
    this.outageReport = const OutageReportConfig(),
    this.handHeld = const HandHeldConfig(),
    this.gnssHealth = const GnssHealthConfig(),
    this.gnssCourse = const GnssCourseConfig(),
    this.sensorHealth = const SensorHealthConfig(),
    this.mountQuality = const MountQualityConfig(),
    this.faultMonitor = const FaultMonitorConfig(),
    this.gnssLossPreparation = const GnssLossPreparationConfig(),
    this.route = const RouteConfig(),
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
  final TurnSpeedConfig turnSpeed;
  final VibrationSpeedConfig vibrationSpeed;
  final TunnelConfig tunnel;
  final ParkingLevelConfig parkingLevel;
  final OutageReportConfig outageReport;
  final HandHeldConfig handHeld;
  final GnssHealthConfig gnssHealth;
  final GnssCourseConfig gnssCourse;
  final SensorHealthConfig sensorHealth;
  final MountQualityConfig mountQuality;
  final FaultMonitorConfig faultMonitor;
  final GnssLossPreparationConfig gnssLossPreparation;
  final RouteConfig route;
  final FeatureFlags features;

  static const NavConfig defaults = NavConfig();

  /// Phone policy. The speed model must pass live GNSS validation before any
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
    TurnSpeedConfig? turnSpeed,
    VibrationSpeedConfig? vibrationSpeed,
    TunnelConfig? tunnel,
    ParkingLevelConfig? parkingLevel,
    OutageReportConfig? outageReport,
    HandHeldConfig? handHeld,
    GnssHealthConfig? gnssHealth,
    GnssCourseConfig? gnssCourse,
    SensorHealthConfig? sensorHealth,
    MountQualityConfig? mountQuality,
    FaultMonitorConfig? faultMonitor,
    GnssLossPreparationConfig? gnssLossPreparation,
    RouteConfig? route,
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
        turnSpeed: turnSpeed ?? this.turnSpeed,
        vibrationSpeed: vibrationSpeed ?? this.vibrationSpeed,
        tunnel: tunnel ?? this.tunnel,
        parkingLevel: parkingLevel ?? this.parkingLevel,
        outageReport: outageReport ?? this.outageReport,
        handHeld: handHeld ?? this.handHeld,
        gnssHealth: gnssHealth ?? this.gnssHealth,
        gnssCourse: gnssCourse ?? this.gnssCourse,
        sensorHealth: sensorHealth ?? this.sensorHealth,
        mountQuality: mountQuality ?? this.mountQuality,
        faultMonitor: faultMonitor ?? this.faultMonitor,
        gnssLossPreparation:
            gnssLossPreparation ?? this.gnssLossPreparation,
        route: route ?? this.route,
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
    this.turnSpeed = false,
    this.vibrationSpeed = false,
    this.leanAwareNhc = false,
    this.handHeldMode = false,
    this.speedPrior = false,
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

  /// Coordinated-turn speed (v = a_lat / yaw rate) as a forward-speed
  /// measurement during outages. See `TurnSpeedConfig`.
  final bool turnSpeed;

  /// Tyre-vibration speedometer (speed from the wheel-rate peak of the
  /// vertical accelerometer spectrum). See `VibrationSpeedConfig`.
  final bool vibrationSpeed;

  /// Two-wheeler NHC widened by the phone's sideways swing while the bike
  /// rolls into or out of a lean (mount height × roll rate). Off until a real
  /// two-wheeler drive shows it helps.
  final bool leanAwareNhc;

  /// Let the core lead and dead-reckon with no phone-to-vehicle mount at all -
  /// heading from the orientation-invariant gyro yaw rate, speed held from
  /// the last GNSS speed with a stop detector, no NHC or forward-axis accel
  /// integration (see `motion/hand_held_tracker.dart`). Off until a real
  /// hand-held drive shows it beats hold-last-velocity (§83).
  final bool handHeldMode;

  /// In an outage, the last GNSS speed as a forward-speed measurement whose
  /// sigma grows with time (`GnssCourseConfig.speedPrior*`): a loose phone's
  /// accelerometer cannot be integrated for long.
  final bool speedPrior;

  FeatureFlags copyWith({
    bool? zeroVelocityUpdate,
    bool? zeroAngularRateUpdate,
    bool? nonHolonomicConstraint,
    bool? magnetometerHeading,
    bool? mapHeading,
    bool? adaptiveGnssCovariance,
    bool? gnssVelocity,
    bool? neuralVelocity,
    bool? turnSpeed,
    bool? vibrationSpeed,
    bool? leanAwareNhc,
    bool? handHeldMode,
    bool? speedPrior,
  }) =>
      FeatureFlags(
        zeroVelocityUpdate: zeroVelocityUpdate ?? this.zeroVelocityUpdate,
        zeroAngularRateUpdate:
            zeroAngularRateUpdate ?? this.zeroAngularRateUpdate,
        nonHolonomicConstraint:
            nonHolonomicConstraint ?? this.nonHolonomicConstraint,
        magnetometerHeading: magnetometerHeading ?? this.magnetometerHeading,
        mapHeading: mapHeading ?? this.mapHeading,
        adaptiveGnssCovariance:
            adaptiveGnssCovariance ?? this.adaptiveGnssCovariance,
        gnssVelocity: gnssVelocity ?? this.gnssVelocity,
        neuralVelocity: neuralVelocity ?? this.neuralVelocity,
        turnSpeed: turnSpeed ?? this.turnSpeed,
        vibrationSpeed: vibrationSpeed ?? this.vibrationSpeed,
        leanAwareNhc: leanAwareNhc ?? this.leanAwareNhc,
        handHeldMode: handHeldMode ?? this.handHeldMode,
        speedPrior: speedPrior ?? this.speedPrior,
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
        'turnSpeed': turnSpeed,
        'vibrationSpeed': vibrationSpeed,
        'leanAwareNhc': leanAwareNhc,
        'handHeldMode': handHeldMode,
      };
}

/// Hand-held mode: dead reckoning with no phone-to-vehicle mount (§ hand-held
/// mode). Every value here is an engineering prior tuned against three real
/// Mumbai drives (2026-09-24, git-ignored `field_drives/`), not a measurement
/// in the sense §70 means for the rest of this file - the real yardstick is
/// the outage benchmark run on those drives.
@immutable
class HandHeldConfig {
  const HandHeldConfig({
    this.gravityTauS = 2.0,
    this.handlingWindow = const Duration(seconds: 1),
    this.handlingThresholdDeg = 3.0,
    this.minBearingSpeedMps = 2.0,
    this.headingSigmaAtFixRad = 0.35,
    this.speedSigmaAtFixMps = 0.6,
    this.headingSigmaGrowthRadPerS = 0.09,
    this.headingSigmaGrowthHandlingRadPerS = 0.175,
    this.maxHeadingSigmaRad = 3.0,
    this.speedSigmaGrowthMpsPerS = 0.05,
    this.stationarySpeedSigmaMps = 0.3,
    this.stopAccelStd = 0.6,
    this.stopEnterDelay = const Duration(milliseconds: 800),
    this.stopExitDelay = const Duration(milliseconds: 250),
    this.alongTrackErrorFraction = 1.6,
    this.headingSigmaFromDisplacementRad = 0.5,
    this.maxCourseFixGapS = 6.0,
    this.minCourseDisplacementM = 3.0,
    this.biasMinSpeedMps = 3.0,
    this.biasStopSpeedMps = 0.3,
    this.maxBiasRadPerS = 0.15,
    this.biasStopLearnRate = 0.3,
    this.biasMovingLearnRate = 0.1,
  });

  /// Low-pass time constant for the gravity direction used as the
  /// orientation-invariant vertical. Real drives: gravity direction in the
  /// phone frame wanders >14 deg for 19-40 % of seconds hand-held; 2 s tames
  /// that without lagging a genuine reorientation badly.
  final double gravityTauS;

  /// Window and threshold for the handling flag: the low-passed gravity
  /// direction moving more than [handlingThresholdDeg] within
  /// [handlingWindow] means the phone is being handled right now. Measured to
  /// flag 14-27 % of seconds on the real drives.
  final Duration handlingWindow;
  final double handlingThresholdDeg;
  double get handlingThresholdRad => handlingThresholdDeg * math.pi / 180;

  /// A GNSS bearing is only trusted to seed/correct heading above this speed;
  /// below it course-over-ground is mostly noise.
  final double minBearingSpeedMps;

  /// Sigma a fresh fix resets heading/speed uncertainty to.
  final double headingSigmaAtFixRad;
  final double speedSigmaAtFixMps;

  /// How fast heading uncertainty grows while riding quietly vs. while being
  /// handled - measured hand-held median yaw error (10 s windows) 13-15 deg
  /// outside handling, p90 59-70 deg; handling gets the steeper rate.
  final double headingSigmaGrowthRadPerS;
  final double headingSigmaGrowthHandlingRadPerS;
  final double maxHeadingSigmaRad;

  /// How fast the held-speed's own uncertainty grows - measured 25-38 %
  /// along-track error over 30/60 s hold-last-speed in Mumbai stop-go
  /// traffic.
  final double speedSigmaGrowthMpsPerS;
  final double stationarySpeedSigmaMps;

  /// Stop detector: std(|a|) per second, orientation-invariant (no vehicle
  /// frame needed). Measured ~90 % correct hand-held vs ~99 % mounted.
  final double stopAccelStd;
  final Duration stopEnterDelay;
  final Duration stopExitDelay;

  /// `HandHeldTracker.horizontalSigmaM`'s along-track term: this fraction of
  /// the distance driven since the last fix, honestly reflecting a held
  /// speed's own error rather than a fixed rate per second (measured 25-38 %
  /// along-track error over 30/60 s hold-last-speed in Mumbai stop-go
  /// traffic; 0.30 sits in that band). Tuned against real-drive 3-sigma
  /// consistency, not argued about - see the CLAUDE.md hand-held section.
  final double alongTrackErrorFraction;

  /// Heading source when the fix itself carries no bearing (real receivers
  /// often don't - measured 0/459 fixes on one of the three real drives this
  /// was built from): the course between this fix and the last one, from
  /// their raw lat/lon displacement. Noisier than a native bearing (GPS
  /// jitter on both endpoints, not a Doppler measurement), hence the wider
  /// sigma; only used within [maxCourseFixGapS] of the previous fix and
  /// above [minCourseDisplacementM] of travel between them.
  final double headingSigmaFromDisplacementRad;
  final double maxCourseFixGapS;
  final double minCourseDisplacementM;

  /// Gyro bias estimation (§ hand-held mode, part 1): a GNSS-derived course
  /// rate (from position displacement) is only trusted above this speed, and
  /// a stretch is only "stopped" for the direct stopped-mean bias measurement
  /// below this speed.
  final double biasMinSpeedMps;
  final double biasStopSpeedMps;

  /// The bias estimate is clamped to this magnitude - past it, something is
  /// wrong with the estimate itself (a bad fix, a still-settling gravity
  /// direction), not a genuinely biased gyro.
  final double maxBiasRadPerS;

  /// EMA learn rates for the two bias evidence sources. Stops are the
  /// cleanest evidence (true rotation is genuinely ~0), so they get the
  /// faster rate; the moving estimate is noisier (GNSS position error on top
  /// of the course-rate differencing) so it is trusted more slowly.
  final double biasStopLearnRate;
  final double biasMovingLearnRate;
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
    this.nhcLeanGain = 2.0,
    this.twoWheelerMountHeightM = 1.0,
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

  /// Two-wheeler NHC sigma grows by this factor times sin(lean).
  final double nhcLeanGain;

  /// Height of the phone above the tyre contact line on a two-wheeler (m).
  /// A bike rolling into or out of a lean swings the phone sideways at
  /// height × roll rate even though the tyres do not slip; with
  /// `FeatureFlags.leanAwareNhc` that swing widens the lateral sigma.
  final double twoWheelerMountHeightM;
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
    this.bendRegistration = false,
    this.bendMinDeg = 30.0,
    this.bendSearchM = 80.0,
    this.bendToleranceDeg = 15.0,
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

  /// Bend registration: a bend in the road is a landmark. When the gyro turns
  /// by what a bend up to [bendSearchM] ahead turns, the marker was behind:
  /// jump to that bend. When the road bent by at least [bendMinDeg] and the
  /// gyro only turns later, the marker was ahead: move back to the bend. The
  /// turns must agree within [bendToleranceDeg]. Off until a real drive shows
  /// it helps.
  final bool bendRegistration;
  final double bendMinDeg;
  final double bendSearchM;
  final double bendToleranceDeg;

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

/// Coordinated-turn speedometer (§17 companion): in a steady turn the
/// centripetal force is v * omega, so the forward speed is a_lat / omega.
///
/// It needs no wheel, no model and no GNSS, and its error does not grow with
/// time, which is exactly what along-track dead reckoning lacks. It only
/// speaks in a clear, steady turn; on a straight road the ratio is noise.
/// Every value here is an engineering prior, not a measurement.
@immutable
class TurnSpeedConfig {
  const TurnSpeedConfig({
    this.window = const Duration(seconds: 1),
    this.minWindowFill = 0.8,
    this.updateInterval = const Duration(seconds: 1),
    this.minYawRate = 0.10,
    this.maxYawRate = 1.2,
    this.maxYawRateCv = 0.35,
    this.minLateralAccel = 0.6,
    this.minSpeed = 2.0,
    this.maxSpeed = 45.0,
    this.accelSigma = 0.35,
    this.yawRateSigma = 0.012,
    this.maxSigma = 2.5,
    this.validationWindow = 20,
    this.validationMinPairs = 5,
    this.validationMaxBias = 1.0,
    this.validationMaxRms = 2.0,
    this.validationMaxFixAge = const Duration(milliseconds: 1500),
  });

  /// Averaging window for a_lat and omega.
  final Duration window;

  /// Fraction of [window] that must be filled before it may speak.
  final double minWindowFill;

  /// One observation per interval: overlapping windows are not independent.
  final Duration updateInterval;

  /// rad/s. Below this the ratio amplifies noise; above it the manoeuvre is
  /// not a steady turn (U-turn, spin).
  final double minYawRate;
  final double maxYawRate;

  /// Largest std/|mean| of omega in the window: a steady turn only.
  final double maxYawRateCv;

  /// m/s². The centripetal force must clearly exceed accelerometer noise.
  final double minLateralAccel;

  final double minSpeed;
  final double maxSpeed;

  /// 1-sigma of the windowed lateral acceleration (noise, bank, residual
  /// bias) and of the yaw rate (residual gyro bias), for the error model
  /// sigma_v^2 = (sigma_a / w)^2 + (v * sigma_w / w)^2.
  final double accelSigma;
  final double yawRateSigma;

  /// Observations less certain than this are dropped.
  final double maxSigma;

  /// GNSS comparison: residuals kept, how many before a verdict, and the bias
  /// and RMS beyond which the turn speed is switched off.
  final int validationWindow;
  final int validationMinPairs;
  final double validationMaxBias;
  final double validationMaxRms;

  /// A GNSS speed older than this is not compared with.
  final Duration validationMaxFixAge;
}

/// When a returning fix is used to score the outage it ends (the recovery
/// card). Short blips are not outages and would only report fix noise.
@immutable
class OutageReportConfig {
  const OutageReportConfig({
    this.minOutage = const Duration(seconds: 5),
    this.minDistanceM = 25,
    this.driftTargetPct = 10,
  });

  final Duration minOutage;
  final double minDistanceM;

  /// SIH26168's dead-reckoning benchmark: drift below 10 % of distance.
  final double driftTargetPct;
}

/// Tyre-vibration speedometer: a rolling wheel shakes the car at its rotation
/// rate (tyre non-uniformity, wheel imbalance), so the dominant peak of the
/// vertical accelerometer spectrum moves in proportion to speed:
/// f = v / (2 pi r). The constant 1 / (2 pi r) is learned per vehicle from GNSS
/// speed while GNSS is healthy, so no wheel size is needed.
///
/// Its error does not grow with time. It needs a phone rate well above twice
/// the wheel rate (a 50 Hz phone sees up to 25 Hz, i.e. ~150 km/h on a 0.3 m
/// wheel); the IO-VNBD 10 Hz logs cannot test it, so it stays off until a
/// recorded phone drive shows it helps. Every value here is an engineering
/// prior, not a measurement.
@immutable
class VibrationSpeedConfig {
  const VibrationSpeedConfig({
    this.window = const Duration(seconds: 4),
    this.minWindowFill = 0.9,
    this.updateInterval = const Duration(seconds: 1),
    this.minSampleRateHz = 30,
    this.minHz = 2.0,
    this.maxHz = 20.0,
    this.segments = 3,
    this.minProminence = 12.0,
    this.minSpeed = 4.0,
    this.maxSpeed = 45.0,
    this.calibrationWindow = 40,
    this.calibrationMinPairs = 12,
    this.maxRelativeSpread = 0.08,
    this.minInlierFraction = 0.8,
    this.minSigma = 0.4,
    this.maxSigma = 2.5,
    this.maxSpeedChange = 0.04,
    this.minGnssPerWindow = 3,
  });

  /// Spectrum length: longer resolves frequency finer (0.25 Hz at 4 s) but
  /// smears speed changes.
  final Duration window;

  /// Fraction of [window] that must be covered before a spectrum is taken.
  final double minWindowFill;

  /// One observation per interval.
  final Duration updateInterval;

  /// Below this the wheel band aliases; the estimator stays silent.
  final double minSampleRateHz;

  /// Search band for the wheel-rate peak, Hz.
  final double minHz;
  final double maxHz;

  /// Half-overlapping segments averaged per spectrum (Welch). Averaging tames
  /// the random peaks of a noise-only spectrum; a real line survives it.
  final int segments;

  /// Peak power over the band's median power: a real rotation line stands far
  /// above road noise; a flat spectrum says nothing.
  final double minProminence;

  /// m/s. Below [minSpeed] the wheel line is under [minHz] or buried.
  final double minSpeed;
  final double maxSpeed;

  /// Speed-per-hertz ratios kept and how many before it may speak.
  final int calibrationWindow;
  final int calibrationMinPairs;

  /// A ratio within [maxRelativeSpread] of the median is an inlier. Fewer than
  /// [minInlierFraction] inliers means the peak hops between harmonics and the
  /// scale is not trustworthy; the inliers' own spread sets the sigma.
  final double maxRelativeSpread;
  final double minInlierFraction;

  /// Clamp on the reported 1-sigma, m/s.
  final double minSigma;
  final double maxSigma;

  /// A spectrum is only paired with GNSS when the GNSS speed held steady over
  /// the same window: at least [minGnssPerWindow] fixes, spanning no more than
  /// [maxSpeedChange] of their mean. A changing speed smears the line.
  final double maxSpeedChange;
  final int minGnssPerWindow;
}

/// Tunnel look-ahead from the offline map's `is_tunnel` roads: warn before the
/// portal, then report the tunnel still to drive. Engineering priors.
@immutable
class TunnelConfig {
  const TunnelConfig({
    this.lookaheadM = 2000,
    this.announceWithinM = 1500,
    this.bearingToleranceDeg = 35,
    this.alignToleranceDeg = 50,
    this.joinM = 8,
    this.minLengthM = 40,
    this.insideCorridorM = 25,
  });

  /// Portals farther than this are not considered.
  final double lookaheadM;

  /// The UI warns inside this distance.
  final double announceWithinM;

  /// The portal must lie within this of the heading…
  final double bearingToleranceDeg;

  /// …and the tunnel must run within this of the heading (not a crossing
  /// tunnel under the road).
  final double alignToleranceDeg;

  /// Tunnel pieces whose ends are this close are one tunnel.
  final double joinM;

  /// Shorter covered stretches (a footbridge shadow) are not tunnels here.
  final double minLengthM;

  /// Within this of a tunnel's centreline counts as inside it.
  final double insideCorridorM;
}

/// Car-park floors from barometric height after GNSS is lost.
@immutable
class ParkingLevelConfig {
  const ParkingLevelConfig({
    this.floorHeightM = 3.0,
    this.hysteresis = 0.2,
  });

  /// Floor-to-floor height of a typical multi-level car park (m).
  final double floorHeightM;

  /// Extra fraction of a floor, beyond half, before the level changes.
  final double hysteresis;
}

/// Course over ground from the GNSS fixes themselves, for receivers that
/// report no bearing (`gnss/gnss_course.dart`), and the heading guard that
/// uses it. Values from the 2026-09-26 rickshaw drive (1 Hz fixes, ~10 m
/// accuracy): consecutive phone fixes err together, so their *relative*
/// error is a fraction of the reported accuracy.
@immutable
class GnssCourseConfig {
  const GnssCourseConfig({
    this.minBaselineM = 20,
    this.maxBaselineS = 6,
    this.minSpeedMps = 3,
    this.maxAccuracyM = 30,
    this.maxBendDeg = 20,
    this.relativeErrorFraction = 0.25,
    this.minSigmaDeg = 5,
    this.guardDisagreeDeg = 45,
    this.guardConsecutive = 3,
    this.guardResetSigmaDeg = 20,
    this.dopplerSpeedSigmaMps = 1.0,
    this.speedPriorBaseSigmaMps = 0.5,
    this.speedPriorGrowthMpsPerS = 0.3,
    this.trustWindow = 20,
    this.trustMinSamples = 10,
    this.trustRatio = 1.25,
    this.trustMarginM = 2,
    this.trustMaxGapS = 2.5,
  });

  /// Earned-trust gate: over the last [trustWindow] fixes (at least
  /// [trustMinSamples]), the core's median error predicting each fix must be
  /// within [trustRatio] x + [trustMarginM] of holding the last velocity's.
  /// Fixes further apart than [trustMaxGapS] are not compared.
  final int trustWindow;
  final int trustMinSamples;
  final double trustRatio;
  final double trustMarginM;
  final double trustMaxGapS;

  /// Speed prior in an outage (`FeatureFlags.speedPrior`): sigma =
  /// base + growth * seconds since the last fix.
  final double speedPriorBaseSigmaMps;
  final double speedPriorGrowthMpsPerS;

  /// Floor on the sigma of the receiver's (Doppler) speed, fed as a forward-
  /// speed measurement when a fix has no usable course. Covers the ~1 s lag
  /// of phone GNSS speed during hard acceleration.
  final double dopplerSpeedSigmaMps;

  /// Shortest chord a course is taken over.
  final double minBaselineM;

  /// Oldest fix still used as the start of a chord.
  final double maxBaselineS;

  /// Below this ground speed the chord is mostly noise.
  final double minSpeedMps;

  /// Fixes worse than this are not used for course at all.
  final double maxAccuracyM;

  /// Either half of the chord bending more than this from the whole: a turn,
  /// not a straight course.
  final double maxBendDeg;

  /// Relative error of two fixes a few seconds apart, as a fraction of the
  /// reported accuracy.
  final double relativeErrorFraction;
  final double minSigmaDeg;

  /// Heading guard: the core disagreeing with the GNSS course by more than
  /// this on this many consecutive courses is re-seeded on the course.
  final double guardDisagreeDeg;
  final int guardConsecutive;

  /// Heading sigma after a guard re-seed.
  final double guardResetSigmaDeg;
}

/// Thresholds for `GnssHealthClassifier` (driver-facing GNSS HEALTH state:
/// NORMAL / DEGRADED / MULTIPATH SUSPECTED / INTERFERENCE SUSPECTED /
/// OUTAGE). Engineering priors, not measured — see `core/nav/gnss/gnss_health.dart`.
@immutable
class GnssHealthConfig {
  const GnssHealthConfig({
    this.staleFixSeconds = 6,
    this.fewSatellitesUsed = 6,
    this.weakMeanCn0DbHz = 22,
    this.strongMeanCn0DbHz = 30,
    this.broadbandCn0DropDbHz = 8,
    this.broadbandMinConstellations = 2,
    this.broadbandMinSatellites = 6,
    this.sharpAgcDropDb = 6,
    this.multipathManyMeasurements = 3,
    this.highCn0VarianceDbHz = 36,
    this.lowElevationDegrees = 20,
    this.lowElevationDominanceRatio = 0.6,
    this.rejectWindowSeconds = 60,
    this.jumpRejectsForMultipath = 2,
    this.leaveCleanSeconds = 10,
  });

  /// OUTAGE: no accepted fix for longer than this. Matches the app-wide
  /// "live" freshness window (`LiveLocationService`/root CLAUDE.md).
  final double staleFixSeconds;

  /// DEGRADED: fewer used satellites than this.
  final int fewSatellitesUsed;

  /// DEGRADED: mean C/N0 below this is weak.
  final double weakMeanCn0DbHz;

  /// A mean C/N0 at or above this is "otherwise fine" for the multipath rule.
  final double strongMeanCn0DbHz;

  /// INTERFERENCE: a broadband C/N0 drop of at least this, seen across many
  /// satellites and constellations at once (elevation-independent).
  final double broadbandCn0DropDbHz;
  final int broadbandMinConstellations;
  final int broadbandMinSatellites;

  /// INTERFERENCE: AGC level dropping by at least this many dB is a receiver
  /// gain response consistent with broadband interference.
  final double sharpAgcDropDb;

  /// MULTIPATH: at least this many measurements flagged
  /// `MULTIPATH_INDICATOR_DETECTED`.
  final int multipathManyMeasurements;

  /// MULTIPATH: C/N0 spread (max-min) at or above this, dominated by
  /// low-elevation satellites, is a multipath signature.
  final double highCn0VarianceDbHz;
  final double lowElevationDegrees;
  final double lowElevationDominanceRatio;

  /// Reject-reason counts (position/velocity/heading jumps) are windowed over
  /// this many seconds of fixes.
  final double rejectWindowSeconds;

  /// MULTIPATH: this many position/heading jump rejects within the window,
  /// while C/N0 stays healthy, points at multipath rather than interference.
  final int jumpRejectsForMultipath;

  /// Hysteresis: a worse state is reported the moment it is detected (enter
  /// fast), but recovering to a better state needs this many seconds of
  /// continuously clean (NORMAL) samples first (leave slow, so a momentary
  /// clean reading between real drops does not flicker the UI).
  final double leaveCleanSeconds;
}

/// Sensor health monitor thresholds (§ Navigation Hardware Check). Most of the
/// per-sensor checks reuse the timing (`TimeSync`) and fault
/// (`SensorFaultDetector`) numbers already computed for other reasons; this
/// only adds the two things nothing else measures: gyro-bias drift between
/// stationary windows, and GNSS fix cadence.
@immutable
class SensorHealthConfig {
  const SensorHealthConfig({
    this.minGoodHz = 30,
    this.minAcceptableHz = 15,
    this.gyroBiasWindow = const Duration(seconds: 3),
    this.orientationWobbleDegradedDeg = 8.0,
    this.orientationWobbleFailDeg = 20.0,
    this.gnssGapFactor = 2.5,
    this.gnssStaleAfter = const Duration(seconds: 12),
  });

  /// Measured accel/gyro rate below [minGoodHz] is DEGRADED, below
  /// [minAcceptableHz] is FAIL.
  final double minGoodHz;
  final double minAcceptableHz;

  /// How long a stationary stretch must run before its mean gyro counts as one
  /// bias sample; the drift between two such samples is the bias-stability
  /// check ("--" until a second stationary window has been seen).
  final Duration gyroBiasWindow;

  /// Gravity-direction wobble (deg), measured the same way as
  /// `PhoneHandlingDetector.isHandling`, beyond which the mount counts as
  /// unstable.
  final double orientationWobbleDegradedDeg;
  final double orientationWobbleFailDeg;

  /// A GNSS interval more than this many times the running mean is a gap.
  final double gnssGapFactor;

  /// No fix at all for this long is a FAIL, not just DEGRADED.
  final Duration gnssStaleAfter;
}

/// Mount-quality scoring (§ Dynamic Mount Quality Score): one 0-100 number
/// built from four sub-scores that are already computed elsewhere for other
/// reasons (orientation wobble, the AI vibration estimate, the magnetometer
/// field magnitude and the mount estimator's own confidence) — nothing here
/// measures anything new.
@immutable
class MountQualityConfig {
  const MountQualityConfig({
    this.excellentScore = 85,
    this.goodScore = 65,
    this.fairScore = 40,
    this.unstableWobbleDeg = 8.0,
    this.alignmentKnownScore = 50,
  });

  /// Alignment sub-score below this means the vehicle frame is still being
  /// learned; the overall label is then held at FAIR at best.
  final double alignmentKnownScore;

  final double excellentScore;
  final double goodScore;
  final double fairScore;

  /// Wobble (or active handling) at or beyond this marks the mount unstable.
  final double unstableWobbleDeg;
}

/// Thresholds for `FaultMonitor` (§ Fault Injection Lab): read-only,
/// sliding-window detectors fed from data the engine already computes each
/// step (gyro/accel samples, the filter's own predicted state, its own
/// gyro-bias estimate). None of this feeds back into the filter — it only
/// raises `NavigationSnapshot.faultFlags` for the driver and the lab.
/// Engineering priors, tuned so the bundled clean reference drive raises
/// zero flags (see `test/nav/fault_lab_matrix_test.dart`).
@immutable
class FaultMonitorConfig {
  const FaultMonitorConfig({
    this.courseMinSpeedMps = 3.0,
    this.gyroResidualWindow = 20,
    this.gyroResidualThresholdDegPerS = 0.35,
    this.gyroResidualMinFraction = 0.7,
    this.accelResidualWindow = 10,
    this.accelResidualThresholdMps = 0.15,
    this.accelResidualMinFraction = 0.7,
    this.integrityCusumSlack = 0.5,
    this.integrityCusumThreshold = 15.0,
    this.timestampDelayWindow = 10,
    this.timestampDelayThresholdS = 0.3,
    this.timestampDelayMinSpeedMps = 3.0,
    this.timestampDelayMinFraction = 0.7,
    this.timestampDelayMaxCrossTrackFraction = 0.4,
    this.timestampDelayMinSigmaMultiple = 3.0,
    this.filterGyroBiasJumpRadPerS = 0.03,
  });

  /// A GNSS bearing is only trusted as a course reading above this speed
  /// (matches the jitter floor `GnssQualityEngine` itself uses).
  final double courseMinSpeedMps;

  /// Gyro-bias detector: how many (gyro rate - GNSS course rate) residuals
  /// are kept, the mean magnitude that counts as a persistent bias, and the
  /// fraction of the window that must agree in sign (rather than cancel out
  /// as noise) before it is flagged.
  final int gyroResidualWindow;
  final double gyroResidualThresholdDegPerS;
  final double gyroResidualMinFraction;

  /// Accelerometer-bias detector: same shape as the gyro one, but reads the
  /// EKF's own forward-axis (vehicle x) accel-bias state estimate directly
  /// (m/s²) rather than re-deriving it - see `FaultMonitor._checkAccelBias`.
  final int accelResidualWindow;
  final double accelResidualThresholdMps;
  final double accelResidualMinFraction;

  /// GNSS integrity anomaly (innovation CUSUM): each accepted fix contributes
  /// `max(0, z - slack)` to a running sum, where `z` is the predicted-vs-fix
  /// separation in filter+GNSS sigmas; the slack absorbs ordinary noise so
  /// only a sustained one-sided drift accumulates. Flags once the sum passes
  /// the threshold.
  final double integrityCusumSlack;
  final double integrityCusumThreshold;

  /// Timestamp-delay detector: how many along-track implied-delay samples
  /// are kept, the mean delay that counts as suspicious, the minimum speed
  /// for the implied delay to be meaningful, the fraction of the window that
  /// must agree, and how small the cross-track residual must stay relative
  /// to the along-track one (a real delay is almost pure along-track; a
  /// wrong-direction bias is not).
  final int timestampDelayWindow;
  final double timestampDelayThresholdS;
  final double timestampDelayMinSpeedMps;
  final double timestampDelayMinFraction;
  final double timestampDelayMaxCrossTrackFraction;

  /// The along-track offset must clear this many filter+GNSS sigmas before
  /// it counts as evidence at all, so a long clean drive's own accumulated
  /// uncertainty does not read as a delay by chance.
  final double timestampDelayMinSigmaMultiple;

  /// The EKF's own gyro-bias estimate (already tracked for the filter, read
  /// here only) jumping by more than this between consecutive accepted fixes
  /// is flagged — a sudden re-estimate, not the slow Gauss-Markov drift the
  /// filter expects.
  final double filterGyroBiasJumpRadPerS;
}

/// Tunables for the visible "Simulate GNSS loss" demo control (a driver-
/// triggered bottom sheet — not the hidden tunnel/canyon test hooks): how
/// often the uncertainty-growth series is sampled while it runs, and which
/// durations the sheet offers.
@immutable
class SimulatedOutageConfig {
  const SimulatedOutageConfig({
    this.sigmaSampleInterval = const Duration(seconds: 1),
    this.offeredDurations = const [
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
      Duration(seconds: 45),
      Duration(seconds: 60),
    ],
  });

  final Duration sigmaSampleInterval;
  final List<Duration> offeredDurations;

  static const SimulatedOutageConfig standard = SimulatedOutageConfig();
}

/// "GNSS Loss Preparation Mode" (§ Tunnel-aware pre-lock): how far ahead of a
/// mapped tunnel to arm, and how old a captured pre-lock reading may be before
/// it is too stale to seed dead reckoning with.
@immutable
class GnssLossPreparationConfig {
  const GnssLossPreparationConfig({
    this.prepareDistanceM = 600,
    this.maxSeedAge = const Duration(seconds: 8),
  });

  /// Arm Preparation Mode once the tunnel is within this distance ahead.
  final double prepareDistanceM;

  /// A pre-lock reading older than this at outage start is not used; the
  /// last real fix is trusted instead.
  final Duration maxSeedAge;
}

/// Journey routing and route-locked dead reckoning (`core/nav/route/`).
///
/// Every threshold the planner and the route tracker use. Agents implementing
/// the planner/tracker add fields here (with a doc comment each) rather than
/// hard-coding numbers.
@immutable
class RouteConfig {
  const RouteConfig({
    this.snapRadiusM = 250,
    this.offRouteM = 50,
    this.offRouteObservations = 3,
    this.lockRadiusM = 40,
    this.lockHeadingTolDeg = 60,
    this.divergeYawDeg = 60,
    this.yawWindowM = 80,
    this.arrivalRadiusM = 30,
    this.snapCandidates = 6,
    this.classSpeedMps = const {
      RoadClass.motorway: 22,
      RoadClass.trunk: 17,
      RoadClass.primary: 12,
      RoadClass.secondary: 10,
      RoadClass.tertiary: 8.5,
      RoadClass.residential: 6.5,
      RoadClass.unclassified: 6.5,
      RoadClass.service: 4,
    },
    this.maneuverSlightDeg = 20,
    this.maneuverTurnDeg = 45,
    this.maneuverSharpDeg = 135,
    this.maneuverUTurnDeg = 170,
    this.maneuverMergeM = 15,
    this.maneuverBearingSampleM = 10,
    this.maneuverPassedM = 5,
    this.observeWindowBackM = 150,
    this.observeWindowForwardM = 1000,
    this.observeAlongPenaltyPerM = 0.05,
  });

  /// How far from the nearest road a chosen start or destination may be and
  /// still be routed from/to (m).
  final double snapRadiusM;

  /// A position further than this from the route counts as off it (m); the
  /// receiver's own accuracy widens it.
  final double offRouteM;

  /// Consecutive off-route observations before the tracker says so (one bad
  /// fix is not a missed turn).
  final int offRouteObservations;

  /// Dead reckoning locks onto the route only within this distance (m).
  final double lockRadiusM;

  /// ... and only when the vehicle's heading agrees this well (deg).
  final double lockHeadingTolDeg;

  /// Gyro yaw the route does not explain, over [yawWindowM] of travel, that
  /// means the vehicle has left the route (deg).
  final double divergeYawDeg;

  /// Travel window the yaw disagreement is summed over (m).
  final double yawWindowM;

  /// Within this of the destination the journey counts as arrived (m).
  final double arrivalRadiusM;

  /// How many nearby roads the planner considers as start/destination
  /// candidates, not just the closest one — the closest edge can be a
  /// one-way leading nowhere useful, while the next one over reaches the
  /// destination.
  final int snapCandidates;

  /// Free-flow speed (m/s) assumed for a road class when the map data itself
  /// carries no `maxSpeedMps` (real packs never do — see `tile_roads.dart`).
  /// Also the ceiling the A* heuristic assumes no road can beat, which is
  /// what keeps `distance / fastest class speed` admissible.
  final Map<RoadClass, double> classSpeedMps;

  /// Turn-angle bands a junction's incoming-vs-outgoing bearing falls into
  /// (deg): below [maneuverSlightDeg] the road is "straight" (no maneuver,
  /// unless the road's name changes — see [ManeuverKind.continueOn]); below
  /// [maneuverTurnDeg] a slight turn; below [maneuverSharpDeg] an ordinary
  /// turn; below [maneuverUTurnDeg] a sharp turn; at or beyond it, a U-turn.
  final double maneuverSlightDeg;
  final double maneuverTurnDeg;
  final double maneuverSharpDeg;
  final double maneuverUTurnDeg;

  /// Maneuvers closer together than this along the route (m) are one
  /// instruction — the bigger turn wins — so a junction noded into two
  /// vertices a metre apart does not announce twice.
  final double maneuverMergeM;

  /// A maneuver's incoming/outgoing bearing is measured over this many
  /// metres either side of the junction vertex, long enough that digitising
  /// noise right at the vertex cannot masquerade as a turn.
  final double maneuverBearingSampleM;

  /// A maneuver within this distance behind the vehicle still counts as
  /// passed, so `RouteProgress.next` does not re-announce the one just taken.
  final double maneuverPassedM;

  /// `RouteTracker.observe` first searches this far behind and ahead of the
  /// current progress (m) — restricting to nearby route topology, not just
  /// nearby space, is what stops a loop or a flyover over the same road from
  /// snapping progress to the wrong stretch.
  final double observeWindowBackM;
  final double observeWindowForwardM;

  /// Extra cost per metre of mismatch between a candidate projection's
  /// along-route distance and the current progress, added to its
  /// perpendicular distance when scoring candidates — keeps progress
  /// continuous when two nearby segments are both plausible matches.
  final double observeAlongPenaltyPerM;
}
