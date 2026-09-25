import 'dart:math' as math;

import 'ai/ai_fusion.dart';
import 'ai/ai_types.dart';
import 'alignment/mount_alignment.dart';
import 'alignment/mount_quality.dart';
import 'anchors/portal_anchor.dart';
import 'calibration/sensor_calibration.dart';
import 'ekf/navigation_filter.dart';
import 'gnss/gnss_quality.dart';
import 'ins/ins_state.dart';
import 'map/map_matcher.dart';
import 'map/road_graph.dart';
import 'math/nav_math.dart';
import 'model/correction_explainer.dart';
import 'model/nav_snapshot.dart';
import 'model/outage_recovery.dart';
import 'monitor/fault_monitor.dart';
import 'motion/gyro_bias.dart';
import 'motion/hand_held_tracker.dart';
import 'motion/motion_classifier.dart';
import 'motion/phone_handling.dart';
import 'motion/turn_speed.dart';
import 'motion/vibration_speed.dart';
import 'nav_config.dart';
import 'sensors/barometer.dart';
import 'sensors/sensor_fault_detector.dart';
import 'sensors/sensor_health.dart';
import 'sensors/sensor_sample.dart';
import 'sensors/time_sync.dart';

/// Rolling per-source accounting for the "Why this position?" panel (§51).
///
/// Each accepted measurement contributes the horizontal position variance
/// it actually removed (m²), decayed over a few seconds and normalised.
/// Every source therefore reports in the same unit and the shares mean
/// something: "of the position certainty we have right now, this is where
/// it came from". It is not a probability that any source is correct.
class _ContributionTracker {
  static const double _halfLifeSeconds = 6;

  double _gnss = 0;
  double _inertial = 0;
  double _ai = 0;
  double _map = 0;
  double _anchor = 0;
  int? _lastUs;

  void decayTo(int monotonicUs) {
    final last = _lastUs;
    _lastUs = monotonicUs;
    if (last == null) return;
    final dt = (monotonicUs - last) / 1e6;
    if (dt <= 0) return;
    final factor = math.pow(0.5, dt / _halfLifeSeconds).toDouble();
    _gnss *= factor;
    _inertial *= factor;
    _ai *= factor;
    _map *= factor;
    _anchor *= factor;
  }

  /// Adds the position variance (m²) a source just removed.
  void add(String source, double varianceRemoved) {
    if (!(varianceRemoved > 0) || !varianceRemoved.isFinite) return;
    final information = varianceRemoved;
    switch (source) {
      case 'gnss':
        _gnss += information;
        break;
      case 'inertial':
        _inertial += information;
        break;
      case 'ai':
        _ai += information;
        break;
      case 'map':
        _map += information;
        break;
      case 'anchor':
        _anchor += information;
        break;
    }
  }

  FusionContribution get snapshot {
    final total = _gnss + _inertial + _ai + _map + _anchor;
    if (total <= 0) return FusionContribution.none;
    return FusionContribution(
      gnss: _gnss / total,
      inertial: _inertial / total,
      ai: _ai / total,
      map: _map / total,
      anchor: _anchor / total,
    );
  }

  void reset() {
    _gnss = 0;
    _inertial = 0;
    _ai = 0;
    _map = 0;
    _anchor = 0;
    _lastUs = null;
  }
}

/// The navigation engine: the one place that turns sensors and fixes into a
/// position (§72).
///
/// Pure Dart, no Flutter, no plugins, no timers — every input is pushed in and
/// every output is a value. That is what makes it replay-deterministic (§37)
/// and unit-testable without a device.
///
/// Inputs are **phone-frame** and raw; the engine calibrates them, works out
/// the phone-to-vehicle transform, and only then runs the filter.
class NavigationEngine {
  NavigationEngine({
    NavConfig config = NavConfig.defaults,
    SensorCalibration? calibration,
    VehicleClass vehicleClass = VehicleClass.car,
    RoadGraph? roadGraph,
  })  : _config = config,
        _matcher = MapMatcher(
          graph: roadGraph ?? RoadGraph.empty(),
          config: config,
          vehicle: vehicleClass == VehicleClass.car
              ? VehicleAccess.cars
              : VehicleAccess.twoWheelers,
        ),
        _calibration = calibration ?? SensorCalibration.none,
        _filter = NavigationFilter(config: config),
        _gnssQuality = GnssQualityEngine(config: config),
        _alignmentEstimator = MountAlignmentEstimator(config: config),
        _motion = MotionClassifier(config: config, vehicleClass: vehicleClass),
        _timeSync = TimeSync(config: config),
        _faults = SensorFaultDetector(config: config),
        _barometer = BarometerProcessor(config: config),
        _ai = AiFusion(config),
        _turn = TurnSpeedEstimator(config: config),
        _vib = VibrationSpeedEstimator(config: config),
        _handling = PhoneHandlingDetector(config: config),
        _handHeldStop = HandHeldStopDetector(config: config),
        _handHeldTracker = HandHeldTracker(config: config),
        _gyroBias = GyroBiasEstimator(config: config),
        _health = SensorHealthMonitor(config: config),
        _mountQualityEstimator = MountQualityEstimator(config: config),
        _faultMonitor = FaultMonitor(config: config);

  final NavConfig _config;
  final NavigationFilter _filter;
  final GnssQualityEngine _gnssQuality;
  final MountAlignmentEstimator _alignmentEstimator;
  final MotionClassifier _motion;
  final TimeSync _timeSync;
  final MapMatcher _matcher;
  final SensorFaultDetector _faults;
  final BarometerProcessor _barometer;
  final AiFusion _ai;
  final TurnSpeedEstimator _turn;
  final VibrationSpeedEstimator _vib;
  final PhoneHandlingDetector _handling;
  final HandHeldStopDetector _handHeldStop;
  final HandHeldTracker _handHeldTracker;
  final GyroBiasEstimator _gyroBias;
  final SensorHealthMonitor _health;
  final MountQualityEstimator _mountQualityEstimator;
  final FaultMonitor _faultMonitor;
  final _ContributionTracker _contribution = _ContributionTracker();

  SensorCalibration _calibration;

  NavMode _mode = NavMode.boot;
  NavigationSnapshot? _snapshot;
  final List<ModeTransition> _transitions = [];
  final List<MeasurementResult> _recentMeasurements = [];
  final CorrectionExplainer _explainer = CorrectionExplainer();

  int _sequence = 0;
  int? _lastImuUs;
  int? _lastGnssUs;
  int _lastMatchUs = 0;
  double? _lastGnssSpeed;
  int? _reacquiringUntilUs;
  int? _outageStartedUs;
  double _outageDistanceM = 0;
  int? _lastAcceptedFixUs;
  double _sinceFixDistanceM = 0;
  OutageRecovery? _lastRecovery;
  double? _lastTemperatureC;
  GnssAssessment? _lastAssessment;

  /// The last usable fix received before the mount was known. It is the
  /// reported position during calibration.
  GnssObservation? _lastUnalignedFix;
  int _lastSnapshotUs = 0;

  /// Mount-change detection (§ mount-change detection): bumped whenever
  /// `MountAlignmentEstimator` resets from a gravity-drift event, so the
  /// engine can tell "just moved, recalibrating" apart from "never
  /// converged" — the snapshot note differs and this clears once the fit has
  /// converged again.
  int _lastMountChangeEventsSeen = 0;
  int? _mountChangedAtUs;

  static const int _maxTransitions = 200;
  static const int _maxRecentMeasurements = 50;

  // ---------------------------------------------------------------- getters

  NavConfig get config => _config;
  NavigationSnapshot? get snapshot => _snapshot;
  NavMode get mode => _mode;
  SensorCalibration get calibration => _calibration;
  MountAlignment? get alignment => _alignmentEstimator.alignment;
  NavigationFilter get filter => _filter;
  MotionSnapshot get motion => _motion.snapshot;

  /// Diagnostics only - the hand-held gyro bias estimate (§ hand-held mode).
  double get debugHandHeldBiasRadPerS => _gyroBias.biasRadPerS;

  /// Mode transitions, oldest first, each with its trigger (§25, §53).
  List<ModeTransition> get transitions => List.unmodifiable(_transitions);

  /// The last measurement results, for the research view (§79).
  List<MeasurementResult> get recentMeasurements =>
      List.unmodifiable(_recentMeasurements);

  MapMatchResult? get mapMatch => _matcher.last;

  /// Per source, what the filter last did with its measurements and why, in
  /// plain words (the "Why" view). Newest first.
  List<CorrectionExplanation> get corrections =>
      _explainer.explain(nowUs: _lastImuUs ?? _lastGnssUs ?? 0);

  /// What the coordinated-turn speedometer has seen and done.
  TurnSpeedDiagnostics get turnSpeedDiagnostics => _turn.diagnostics;

  /// What the tyre-vibration speedometer has seen and done.
  VibrationSpeedDiagnostics get vibrationSpeedDiagnostics => _vib.diagnostics;

  /// Per-sensor fault diagnoses (§29).
  Map<SensorType, SensorDiagnosis> get sensorDiagnoses => _faults.diagnoses;

  /// Latest barometric estimate, or null without a barometer (§18).
  BarometerEstimate? get barometer => _barometer.last;

  /// How much evidence the mount alignment has gathered (§79 research view).
  /// Useful when it is *not* converging and someone needs to know why.
  int get alignmentSamples => _alignmentEstimator.acceptedSamples;
  int get alignmentEvents => _alignmentEstimator.speedChangeEvents;
  bool get hasLevelling => _alignmentEstimator.hasLevelling;

  /// Gravity direction in phone coordinates ("up"), or null before it settles.
  Vector3? get upInPhone => _alignmentEstimator.upInPhone;

  /// True when a road graph is loaded at all (§83).
  bool get hasRoadGraph => _matcher.isAvailable;

  /// Hands the matcher the roads around the vehicle. The graph comes from the
  /// offline map and is replaced as the vehicle moves, so this may be called
  /// many times; an empty graph turns matching off again.
  void setRoadGraph(RoadGraph graph) => _matcher.useGraph(graph);

  set vehicleClass(VehicleClass value) {
    _motion.vehicleClass = value;
    // The bundled road graph has driving access only. Never imply a safe
    // walking route by snapping a pedestrian to a car or motorcycle edge.
    if (value == VehicleClass.pedestrian) _matcher.reset();
    _matcher.vehicle = value == VehicleClass.car
        ? VehicleAccess.cars
        : VehicleAccess.twoWheelers;
  }

  VehicleClass get vehicleClass => _motion.vehicleClass;

  void setCalibration(SensorCalibration calibration) {
    _calibration = calibration;
  }

  // ------------------------------------------------------------------ input

  /// Feeds one raw IMU frame in the **phone** frame.
  ///
  /// Returns a fresh snapshot when one is due (at most at the configured UI
  /// rate), else null. Callers notify observers only on a non-null return.
  NavigationSnapshot? onImu({
    required Vector3 accelPhone,
    required Vector3 gyroPhone,
    required int monotonicUs,
    Vector3? magPhone,
    double? pressureHpa,
    double? temperatureC,
  }) {
    if (temperatureC != null && temperatureC.isFinite) {
      _lastTemperatureC = temperatureC;
    }

    // Fault detection first: a frozen or absurd sensor must be caught before
    // anything downstream integrates it (§29).
    _faults.observe(
      type: SensorType.accelerometer,
      values: [accelPhone.x, accelPhone.y, accelPhone.z],
      monotonicUs: monotonicUs,
    );
    _faults.observe(
      type: SensorType.gyroscope,
      values: [gyroPhone.x, gyroPhone.y, gyroPhone.z],
      monotonicUs: monotonicUs,
    );
    if (magPhone != null) {
      _faults.observe(
        type: SensorType.magnetometer,
        values: [magPhone.x, magPhone.y, magPhone.z],
        monotonicUs: monotonicUs,
      );
    }
    if (pressureHpa != null && pressureHpa.isFinite) {
      _faults.observe(
        type: SensorType.barometer,
        values: [pressureHpa],
        monotonicUs: monotonicUs,
      );
      _updateBarometer(pressureHpa, monotonicUs);
    }
    _faults.checkStaleness(monotonicUs);

    // Navigation Hardware Check + mount quality: raw phone-frame samples, fed
    // unconditionally so they stay warm whether or not hand-held mode or the
    // mount transform is ready (§ hardware check, § mount quality).
    _health.observeImu(
      accelPhone: accelPhone,
      gyroPhone: gyroPhone,
      magPhone: magPhone,
      monotonicUs: monotonicUs,
    );

    // Push through the time sync so drops and rates are measured even when the
    // engine consumes the samples directly (§4, §64).
    _timeSync.add(SensorSample(
      type: SensorType.accelerometer,
      monotonicUs: monotonicUs,
      values: [accelPhone.x, accelPhone.y, accelPhone.z],
    ));
    _timeSync.add(SensorSample(
      type: SensorType.gyroscope,
      monotonicUs: monotonicUs,
      values: [gyroPhone.x, gyroPhone.y, gyroPhone.z],
    ));
    if (magPhone != null) {
      _timeSync.add(SensorSample(
        type: SensorType.magnetometer,
        monotonicUs: monotonicUs,
        values: [magPhone.x, magPhone.y, magPhone.z],
      ));
    }
    _timeSync.drain(monotonicUs);

    if (!_finite(accelPhone) || !_finite(gyroPhone)) {
      return _maybeSnapshot(monotonicUs, force: false);
    }

    final accel = _calibration.correctAccel(accelPhone);
    final gyro = _calibration.correctGyro(gyroPhone);
    final magUsable =
        magPhone != null && _faults.isUsable(SensorType.magnetometer);
    final mag = magUsable ? _calibration.correctMag(magPhone) : null;

    // The AI path (P2/P3): what is shaking the phone right now, and what the
    // filter should therefore believe. Neutral, and free, while it is off.
    _ai.observeAccel(accel, monotonicUs);
    final ai = _ai.scales(monotonicUs);

    _alignmentEstimator.add(
      accelPhone: accel,
      gyroPhone: gyro,
      monotonicUs: monotonicUs,
      gnssSpeedMps: _gnssSpeedForAlignment(monotonicUs),
      gnssUs: _lastGnssUs,
      hold: ai.holdUpdates,
    );

    final mountChangeEvents = _alignmentEstimator.mountChangeEvents;
    if (mountChangeEvents != _lastMountChangeEventsSeen) {
      _lastMountChangeEventsSeen = mountChangeEvents;
      _mountChangedAtUs = monotonicUs;
    }
    if (_mountChangedAtUs != null && _alignmentEstimator.isConverged) {
      _mountChangedAtUs = null;
    }

    // Hand-held dead reckoning needs no phone-to-vehicle mount, so it is fed
    // on every frame regardless of alignment status: that keeps it warm for
    // an instant handover if the mount later slips and resets (§6).
    if (_config.features.handHeldMode) {
      final beforeLat = _handHeldTracker.latitudeDeg;
      final beforeLon = _handHeldTracker.longitudeDeg;
      final yawRate = _handling.add(
        accelPhone: accel,
        gyroPhone: gyro,
        monotonicUs: monotonicUs,
      );
      final handlingNow = _handling.isHandling;
      final stationaryNow = _handHeldStop.add(
        accelMagnitude: accel.length,
        monotonicUs: monotonicUs,
      );
      _gyroBias.observeImu(
        yawRateRadPerS: yawRate,
        handling: handlingNow,
        monotonicUs: monotonicUs,
      );
      final freshGnssSpeed = _gnssSpeedForAlignment(monotonicUs);
      final gnssStopped =
          freshGnssSpeed != null && freshGnssSpeed < _config.handHeld.biasStopSpeedMps;
      _gyroBias.observeGnssStop(
        stationary: gnssStopped,
        yawRateRadPerS: yawRate,
        handling: handlingNow,
      );
      _handHeldTracker.predict(
        yawRateRadPerS: yawRate - _gyroBias.biasRadPerS,
        handling: handlingNow,
        stationary: stationaryNow,
        monotonicUs: monotonicUs,
      );
      _accumulateHandHeldDistance(beforeLat, beforeLon);
      _runMapMatchHandHeld(monotonicUs);
    }

    final mount = _alignmentEstimator.alignment;
    if (mount == null) {
      // Without a phone-to-vehicle transform the vehicle body frame is
      // unknown, so nothing here can be propagated through the mounted EKF -
      // say so rather than integrating in the wrong frame (§6, §83).
      // `_updateMode` routes to the hand-held tracker above when it is on and
      // has a position to report.
      _updateMode(monotonicUs);
      return _maybeSnapshot(monotonicUs, force: false);
    }

    final accelVehicle = mount.toVehicle(accel);
    final gyroVehicle = mount.toVehicle(gyro);
    final magVehicle = mag == null ? null : mount.toVehicle(mag);

    _faultMonitor.onImuStep(
      monotonicUs: monotonicUs,
      yawRateVehicleRadPerS: gyroVehicle.z,
    );

    final dt = _stepSeconds(monotonicUs);
    _lastImuUs = monotonicUs;

    final state = _filter.state;
    _motion.addSample(
      accelBody: accelVehicle,
      gyroBody: gyroVehicle,
      monotonicUs: monotonicUs,
      gnssSpeedMps: _liveGnssSpeed(monotonicUs),
      filterSpeedMps: state?.groundSpeed,
      rollRad: state == null
          ? null
          : NavMath.eulerFromQuaternion(state.qBodyToNav)[0],
      shockHold: ai.holdUpdates,
    );

    if (dt != null && _filter.isInitialised) {
      final moved = _filter.state;
      _filter.predict(
        accelBody: accelVehicle,
        gyroBody: gyroVehicle,
        dt: dt,
        processNoiseScale: ai.processNoise,
      );
      _accumulateOutageDistance(moved, _filter.state);
      _applyConstraints(
        gyroVehicle: gyroVehicle,
        magVehicle: magVehicle,
        ai: ai,
      );
      _applyTurnSpeed(accelVehicle, gyroVehicle, monotonicUs);
      _applyVibrationSpeed(accelVehicle, monotonicUs);
      _contribution.decayTo(monotonicUs);
      _runMapMatch(monotonicUs);
    }

    _updateMode(monotonicUs);
    return _maybeSnapshot(monotonicUs, force: false);
  }

  /// Feeds one GNSS fix. Every fix goes in, accepted or not — the quality
  /// engine needs the rejected ones to judge the source (§13).
  NavigationSnapshot? onGnss(GnssObservation fix) {
    final state = _filter.state;
    final predictedHorizontalSigmaM = _filter.horizontalPositionSigma;
    final assessment = _gnssQuality.assess(
      fix,
      inertialHeadingDeg: state?.headingDeg,
      inertialSpeedMps: state?.groundSpeed,
    );
    _faultMonitor.onGnssStep(
      fix: fix,
      assessment: assessment,
      predictedState: state,
      predictedHorizontalSigmaM: predictedHorizontalSigmaM,
      filterGyroBiasRadPerS: state?.gyroBias,
    );
    _lastAssessment = assessment;
    _lastGnssUs = fix.monotonicUs;
    _health.observeGnssFix(fix.monotonicUs);
    _lastGnssSpeed = assessment.usable ? fix.speedMps : null;
    if (_config.features.vibrationSpeed && _lastGnssSpeed != null) {
      _vib.addGnssSpeed(speedMps: _lastGnssSpeed!, monotonicUs: fix.monotonicUs);
    }
    if (assessment.usable && assessment.useVelocity && fix.speedMps != null) {
      // The neural speed is graded against the Doppler speed while GNSS speaks.
      _ai.gradeWithGnss(fix.speedMps!, fix.monotonicUs);
    }

    if (!assessment.usable) {
      _updateMode(fix.monotonicUs);
      return _maybeSnapshot(fix.monotonicUs, force: true);
    }

    if (!_filter.isInitialised) {
      // No body frame yet means no propagation is possible, and a filter
      // that cannot propagate would sit still while the vehicle drives off
      // and then reject every fix as an impossible jump. Until the mount is
      // known the GNSS fix *is* the position, and the snapshot says so.
      if (_alignmentEstimator.alignment == null) {
        _lastUnalignedFix = fix;
        if (_config.features.handHeldMode) {
          _handHeldTracker.onFix(
            latitudeDeg: fix.latitudeDeg,
            longitudeDeg: fix.longitudeDeg,
            bearingDeg: fix.bearingDeg,
            speedMps: fix.speedMps,
            horizontalSigmaM: assessment.horizontalSigmaM,
            monotonicUs: fix.monotonicUs,
          );
          _gyroBias.onFix(
            latitudeDeg: fix.latitudeDeg,
            longitudeDeg: fix.longitudeDeg,
            speedMps: fix.speedMps,
            handling: _handling.isHandling,
            monotonicUs: fix.monotonicUs,
          );
          _lastAcceptedFixUs = fix.monotonicUs;
          _sinceFixDistanceM = 0;
          _endOutage();
        }
        _updateMode(fix.monotonicUs);
        return _maybeSnapshot(fix.monotonicUs, force: true);
      }
      _filter.initialise(
        latitudeDeg: fix.latitudeDeg,
        longitudeDeg: fix.longitudeDeg,
        altitudeM: fix.altitudeM ?? 0,
        headingRad: (fix.bearingDeg ?? 0) * NavMath.degToRad,
        gravityBody: _levelledGravity(),
        positionSigma: assessment.horizontalSigmaM,
        initialVelocityNed: _velocityFrom(fix),
        headingSigma:
            (fix.bearingDeg == null || (fix.speedMps ?? 0) < 3) ? null : 0.35,
        timestampUs: fix.monotonicUs,
      );
      _contribution.decayTo(fix.monotonicUs);
      _endOutage();
      _lastAcceptedFixUs = fix.monotonicUs;
      _sinceFixDistanceM = 0;
      _setMode(NavMode.gnssLocked, 'first usable fix', fix.monotonicUs);
      return _maybeSnapshot(fix.monotonicUs, force: true);
    }

    final wasDeadReckoning = _mode.isDeadReckoning;
    final beforeFix = wasDeadReckoning ? _filter.state : null;
    final sigmaBeforeFix =
        wasDeadReckoning ? _filter.horizontalPositionSigma : null;
    // With adaptive covariance off, the receiver's own accuracy is taken at
    // face value — which is the behaviour the ablation baseline needs.
    // A model's GNSS trust (P3) divides the measurement variance: sigma is
    // scaled by 1/sqrt(trust), and by exactly 1.0 when there is none.
    final gnssScale = _ai.gnssSigmaScale(fix.monotonicUs);
    final horizontalSigma = (_config.features.adaptiveGnssCovariance
            ? assessment.horizontalSigmaM
            : fix.accuracyM) *
        gnssScale;
    final verticalSigma = _config.features.adaptiveGnssCovariance
        ? assessment.verticalSigmaM
        : fix.verticalAccuracyM;
    final result = _filter.updatePosition(
      latitudeDeg: fix.latitudeDeg,
      longitudeDeg: fix.longitudeDeg,
      altitudeM: fix.altitudeM,
      horizontalSigma: horizontalSigma,
      verticalSigma: verticalSigma == null ? null : verticalSigma * gnssScale,
    );
    _record(result);
    if (result.accepted) {
      _contribution.decayTo(fix.monotonicUs);
      _contribution.add('gnss', result.positionVarianceReduction);
      if (beforeFix != null) {
        _scoreRecovery(beforeFix, sigmaBeforeFix, fix);
      }
      _lastAcceptedFixUs = fix.monotonicUs;
      _sinceFixDistanceM = 0;
      _endOutage();
      _anchorBarometer(fix);
    }

    if (_config.features.gnssVelocity &&
        assessment.useVelocity &&
        fix.speedMps != null &&
        fix.bearingDeg != null) {
      final bearing = fix.bearingDeg! * NavMath.degToRad;
      final sigma = (assessment.velocitySigmaMps ?? 1.0) * gnssScale;
      final velocityResult = _filter.updateVelocityNed(
        velocityNed: Vector3(
          fix.speedMps! * math.cos(bearing),
          fix.speedMps! * math.sin(bearing),
          0,
        ),
        sigmas: Vector3(sigma, sigma, sigma * 3),
      );
      _record(velocityResult);
      if (velocityResult.accepted) {
        _contribution.add('gnss', velocityResult.positionVarianceReduction);
      }
    }

    // Reacquisition is a real state correction, then a settling window during
    // which the UI says so (§26).
    if (wasDeadReckoning && result.accepted) {
      _reacquiringUntilUs =
          fix.monotonicUs + const Duration(seconds: 3).inMicroseconds;
    }

    _updateMode(fix.monotonicUs);
    return _maybeSnapshot(fix.monotonicUs, force: true);
  }

  /// Tells the engine GNSS is gone (switched off, permission revoked, tunnel).
  void onGnssLost(int monotonicUs) {
    _lastGnssSpeed = null;
    _startOutage(monotonicUs);
    _updateMode(monotonicUs);
  }

  /// Folds one locally registered physical portal into the filter.
  ///
  /// The caller must already have passed the QR/AprilTag through
  /// [PortalAnchorPolicy]. This second gate prevents accidental use outside a
  /// GNSS outage. The coordinate is applied through the EKF's normal
  /// innovation gate; it is never assigned directly to the state.
  MeasurementResult? onPortalAnchor(
    PortalAnchorMeasurement measurement, {
    required int monotonicUs,
    String measurementName = 'portal_anchor',
  }) {
    if (_outageStartedUs == null || !_filter.isInitialised) return null;

    final anchor = measurement.anchor;
    final result = _filter.updatePosition(
      latitudeDeg: anchor.latitudeDeg,
      longitudeDeg: anchor.longitudeDeg,
      horizontalSigma: measurement.horizontalSigmaM,
      name: measurementName,
    );
    _record(result);
    if (result.accepted) {
      _contribution.decayTo(monotonicUs);
      _contribution.add('anchor', result.positionVarianceReduction);
      _runMapMatch(monotonicUs);
    }
    _updateMode(monotonicUs);
    _maybeSnapshot(monotonicUs, force: true);
    return result;
  }

  // ----------------------------------------------------------- AI inputs (P1-P3)

  /// Feeds one neural forward-speed prediction (P1).
  ///
  /// Gated (see [AiSpeedGate]) and, only if it passes, folded into the filter
  /// as a forward-speed measurement. While GNSS is healthy it is not applied:
  /// it is compared with the GNSS-anchored speed, which is how the model earns
  /// the right to be used in an outage. Always returns the decision, so a
  /// caller and the diagnostics can say why an observation was refused.
  ///
  /// Does nothing (and says `disabled`) while `AiConfig.enabled` is false.
  AiSpeedDecision onAiSpeed(AiSpeedObservation observation) {
    final outcome = _ai.applySpeed(
      obs: observation,
      filter: _filter,
      engineUs: _lastImuUs,
      mountKnown: _alignmentEstimator.alignment != null,
      outage: _outageStartedUs != null || !_config.power.idleAiWhenGnssHealthy,
    );
    final result = outcome.result;
    if (result != null) {
      _record(result);
      if (result.accepted) {
        _contribution.add('ai', result.positionVarianceReduction);
      }
    }
    return outcome.decision;
  }

  /// Feeds a disturbance estimate from the vibration and motion-quality models
  /// (P2). It replaces the statistical estimate's vibration score and quality
  /// while it is fresh (`AiConfig.modelOutputTtl`); shocks seen by either count.
  void onDisturbance(DisturbanceEstimate estimate) =>
      _ai.setModelDisturbance(estimate);

  /// Feeds an AI fusion confidence (P3): GNSS and INS trust in (0, 1]. Stale or
  /// absent, the engine uses 1.0 for both.
  void onFusionConfidence(FusionConfidence confidence) =>
      _ai.setFusionConfidence(confidence);

  /// What the AI path is doing right now; [AiDiagnostics.off] while disabled.
  AiDiagnostics get aiDiagnostics => _ai.diagnostics(_lastImuUs ?? 0);

  /// Ties the barometer's absolute scale to a GNSS altitude, but only a good
  /// one: a bad vertical fix would poison every height afterwards.
  void _anchorBarometer(GnssObservation fix) {
    final altitude = fix.altitudeM;
    final pressure = _barometer.last?.pressureHpa;
    if (altitude == null || pressure == null) return;
    final vertical = fix.verticalAccuracyM ?? fix.accuracyM * 2;
    if (vertical > _config.barometer.maxUsableSigmaM) return;
    _barometer.anchorToGnss(
      altitudeM: altitude,
      pressureHpa: pressure,
      monotonicUs: fix.monotonicUs,
    );
  }

  void reset() {
    _filter.reset();
    _gnssQuality.reset();
    _alignmentEstimator.reset();
    _motion.reset();
    _timeSync.reset();
    _matcher.reset();
    _faults.reset();
    _barometer.reset();
    _contribution.reset();
    _ai.reset();
    _turn.reset();
    _vib.reset();
    _handling.reset();
    _handHeldStop.reset();
    _handHeldTracker.reset();
    _gyroBias.reset();
    _faultMonitor.reset();
    _mode = NavMode.boot;
    _snapshot = null;
    _transitions.clear();
    _recentMeasurements.clear();
    _explainer.reset();
    _sequence = 0;
    _lastImuUs = null;
    _lastGnssUs = null;
    _lastGnssSpeed = null;
    _reacquiringUntilUs = null;
    _outageStartedUs = null;
    _outageDistanceM = 0;
    _lastAcceptedFixUs = null;
    _sinceFixDistanceM = 0;
    _lastRecovery = null;
    _lastUnalignedFix = null;
    _lastMatchUs = 0;
    _lastSnapshotUs = 0;
  }

  // ------------------------------------------------------------- internals

  /// GNSS speed for the alignment regression — only while fixes are fresh, and
  /// never a dead-reckoned value, which would make the fit circular (§6).
  double? _gnssSpeedForAlignment(int monotonicUs) {
    final last = _lastGnssUs;
    if (last == null || _lastGnssSpeed == null) return null;
    if (monotonicUs - last > _config.gnss.staleAfter.inMicroseconds) {
      return null;
    }
    return _lastGnssSpeed;
  }

  double? _liveGnssSpeed(int monotonicUs) =>
      _gnssSpeedForAlignment(monotonicUs);

  double? _stepSeconds(int monotonicUs) {
    final last = _lastImuUs;
    if (last == null) return null;
    final dt = (monotonicUs - last) / 1e6;
    if (dt <= 0) return null;
    // Cap the prediction rate: predicting faster buys nothing and costs
    // battery (§31).
    if (dt < 1 / _config.sensors.maxFusionHz) return null;
    return dt;
  }

  /// Nav-frame velocity implied by a fix, when it reports both speed and
  /// bearing. Starting the filter at zero while the vehicle is already
  /// moving guarantees the first few fixes look like impossible jumps.
  Vector3? _velocityFrom(GnssObservation fix) {
    final speed = fix.speedMps;
    final bearing = fix.bearingDeg;
    if (speed == null || bearing == null || speed < 0.5) return null;
    final rad = bearing * NavMath.degToRad;
    return Vector3(speed * math.cos(rad), speed * math.sin(rad), 0);
  }

  Vector3? _levelledGravity() {
    final up = _alignmentEstimator.upInPhone;
    final mount = _alignmentEstimator.alignment;
    if (up == null || mount == null) return null;
    // Gravity as the *vehicle* frame sees it.
    return mount.toVehicle(up * NavMath.gravity);
  }

  /// The stillness and vehicle constraints, with their noise scaled for the
  /// disturbance [ai] reports (P2): a shaken phone is a worse witness, so ZUPT,
  /// ZARU and NHC are believed less. A held shock also suspends ZARU, whose
  /// "measurement" is the gyro reading the shock has just corrupted; ZUPT
  /// carries on, because "the vehicle is not moving" does not depend on it.
  void _applyConstraints({
    required Vector3 gyroVehicle,
    Vector3? magVehicle,
    required AiScales ai,
  }) {
    final snapshot = _motion.snapshot;
    final sigmaScale = ai.measurementSigma;
    final ekf = _config.ekf;

    final features = _config.features;
    if (snapshot.isStationary) {
      if (features.zeroVelocityUpdate) {
        _recordInertial(_filter.updateZeroVelocity(
            sigma: ekf.zuptVelocitySigma * sigmaScale));
      }
      if (features.zeroAngularRateUpdate && !ai.holdUpdates) {
        _recordInertial(_filter.updateZeroAngularRate(
          gyroBody: gyroVehicle,
          sigma: ekf.zaruSigma * sigmaScale,
        ));
      }
    } else if (snapshot.nhcApplicable && features.nonHolonomicConstraint) {
      _recordInertial(_filter.updateNonHolonomic(
        lateralSigma: _motion.nhcLateralSigmaFor(
                rollRateRad: features.leanAwareNhc ? gyroVehicle.x : 0) *
            sigmaScale,
      ));
    }

    // The magnetometer is the only absolute heading reference a phone has
    // offline, but it is also the easiest to disturb. It is only used when the
    // calibration actually fitted a hard-iron offset (§29).
    if (magVehicle != null &&
        features.magnetometerHeading &&
        _calibration.magQuality != null) {
      final quality = _calibration.magQuality!;
      final sigma = _config.ekf.magYawSigma / math.max(quality, 0.1);
      _recordInertial(
          _filter.updateMagnetometer(magBody: magVehicle, sigma: sigma));
    }
  }

  /// Records a measurement that came from the inertial side of the system:
  /// the zero-velocity and non-holonomic constraints, and the magnetometer.
  /// They are what carries the position between fixes.
  void _recordInertial(MeasurementResult result) {
    _record(result);
    if (result.accepted) {
      _contribution.add('inertial', result.positionVarianceReduction);
    }
  }

  /// Feeds the barometer and, while its altitude is still anchored tightly
  /// enough to be worth anything, hands it to the filter (§18).
  ///
  /// Secondary evidence, never truth: the sigma grows with time since the
  /// last GNSS altitude, and past `maxUsableSigmaM` the update is simply not
  /// made rather than made badly.
  void _updateBarometer(double pressureHpa, int monotonicUs) {
    final estimate = _barometer.add(
      pressureHpa: pressureHpa,
      monotonicUs: monotonicUs,
    );
    if (estimate == null || !_filter.isInitialised) return;
    final altitude = estimate.absoluteAltitudeM;
    final sigma = estimate.sigmaM;
    if (altitude == null || sigma == null) return;
    if (sigma > _config.barometer.maxUsableSigmaM) return;
    _recordInertial(_filter.updateAltitude(
      altitudeM: altitude,
      sigma: sigma,
    ));
  }

  /// Matches the fused position to the road network and, when the match is
  /// strong enough, feeds the road's heading back as a soft measurement.
  ///
  /// Heading only. The map never pushes the *position* into the filter
  /// state: doing so would let a wrong match hide a genuine sensor
  /// disagreement, which is exactly what §58 forbids. The snapped position
  /// is published for drawing, alongside the raw one.
  void _runMapMatch(int monotonicUs) {
    if (_motion.vehicleClass == VehicleClass.pedestrian) return;
    if (!_matcher.isAvailable) return;
    final feedHeading = _config.features.mapHeading;
    // Matching costs a spatial query and a bounded Dijkstra; twice a second
    // is plenty for something that only changes when the vehicle moves.
    if (monotonicUs - _lastMatchUs < 500000) return;
    _lastMatchUs = monotonicUs;

    final state = _filter.state;
    final sigma = _filter.horizontalPositionSigma;
    if (state == null || sigma == null) return;

    final result = _matcher.update(
      lat: state.latitudeDeg,
      lon: state.longitudeDeg,
      sigmaM: sigma,
      headingRad: state.headingDeg * NavMath.degToRad,
      speedMps: state.groundSpeed,
    );
    if (result == null || !result.snapped || !feedHeading) return;
    if (result.confidence < _config.mapMatch.headingFeedbackMinConfidence) {
      return;
    }
    final heading = result.matchedHeadingRad;
    if (heading == null) return;

    // A confident match still only constrains heading loosely: roads have
    // width, lanes curve, and the polyline is a simplification.
    final sigmaRad = _config.ekf.magYawSigma / result.confidence;
    final applied = _filter.updateHeading(
      measuredHeadingRad: heading,
      sigma: sigmaRad,
      name: 'map_heading',
    );
    _record(applied);
    if (applied.accepted) {
      _contribution.add('map', applied.positionVarianceReduction);
    }
  }

  /// The hand-held path's counterpart to [_runMapMatch]: same matcher, same
  /// "heading only, never position" rule (§58) - just fed the hand-held
  /// tracker's own position/heading/speed instead of the EKF state, and
  /// correcting `HandHeldTracker`'s scalar heading/sigma instead of the
  /// filter's covariance. This is what bounds the open-loop gyro-bias drift
  /// a mounted vehicle would otherwise never see uncorrected for so long: on
  /// a matched road, the yaw rate only breaks the tie at a junction, and the
  /// road's own heading carries the rest (§ hand-held mode, part 2).
  ///
  /// Only runs while the mount has not converged - once it has, the mounted
  /// path leads and this tracker is background-only.
  void _runMapMatchHandHeld(int monotonicUs) {
    if (_alignmentEstimator.alignment != null) return;
    if (_motion.vehicleClass == VehicleClass.pedestrian) return;
    if (!_matcher.isAvailable || !_config.features.mapHeading) return;
    if (monotonicUs - _lastMatchUs < 500000) return;
    _lastMatchUs = monotonicUs;

    final lat = _handHeldTracker.latitudeDeg;
    final lon = _handHeldTracker.longitudeDeg;
    final headingDeg = _handHeldTracker.headingDeg;
    if (lat == null || lon == null || headingDeg == null) return;

    final result = _matcher.update(
      lat: lat,
      lon: lon,
      sigmaM: _handHeldTracker.horizontalSigmaM,
      headingRad: headingDeg * NavMath.degToRad,
      speedMps: _handHeldTracker.speedMps ?? 0,
    );
    if (result == null || !result.snapped) return;
    if (result.confidence < _config.mapMatch.headingFeedbackMinConfidence) {
      return;
    }
    final heading = result.matchedHeadingRad;
    if (heading == null) return;
    final sigmaRad = _config.ekf.magYawSigma / result.confidence;
    _handHeldTracker.applyHeadingMeasurement(
      headingRad: heading,
      sigmaRad: sigmaRad,
    );
  }

  /// Same accounting as [_accumulateOutageDistance], for the hand-held
  /// tracker's plain lat/lon instead of a full [InsState].
  void _accumulateHandHeldDistance(double? beforeLat, double? beforeLon) {
    if (beforeLat == null || beforeLon == null) return;
    final afterLat = _handHeldTracker.latitudeDeg;
    final afterLon = _handHeldTracker.longitudeDeg;
    if (afterLat == null || afterLon == null) return;
    final step = NavMath.horizontalDistance(
      lat0: beforeLat,
      lon0: beforeLon,
      lat1: afterLat,
      lon1: afterLon,
    );
    if (_lastAcceptedFixUs != null) _sinceFixDistanceM += step;
    if (_outageStartedUs != null) _outageDistanceM += step;
  }

  void _accumulateOutageDistance(InsState? before, InsState? after) {
    if (before == null || after == null) return;
    final step = NavMath.horizontalDistance(
      lat0: before.latitudeDeg,
      lon0: before.longitudeDeg,
      lat1: after.latitudeDeg,
      lon1: after.longitudeDeg,
    );
    if (_lastAcceptedFixUs != null) _sinceFixDistanceM += step;
    if (_outageStartedUs != null) _outageDistanceM += step;
  }

  /// Scores the outage a returning fix ends: the core's position just
  /// before the update against the fix, over the span since the last
  /// accepted fix. Blips below the report thresholds are fix noise, not
  /// outages, and are not reported.
  void _scoreRecovery(InsState before, double? sigma, GnssObservation fix) {
    final lastFix = _lastAcceptedFixUs;
    if (lastFix == null) return;
    final report = _config.outageReport;
    final durationUs = fix.monotonicUs - lastFix;
    if (durationUs < report.minOutage.inMicroseconds) return;
    if (_sinceFixDistanceM < report.minDistanceM) return;
    _lastRecovery = OutageRecovery(
      durationS: durationUs / 1e6,
      distanceM: _sinceFixDistanceM,
      errorM: NavMath.horizontalDistance(
        lat0: before.latitudeDeg,
        lon0: before.longitudeDeg,
        lat1: fix.latitudeDeg,
        lon1: fix.longitudeDeg,
      ),
      fixAccuracyM: fix.accuracyM,
      predictedSigmaM: sigma,
      endedAtUs: fix.monotonicUs,
      coreLed: _snapshot?.canLeadPosition ?? false,
    );
  }

  /// Coordinated-turn speed (v = a_lat / omega), taken in the level frame
  /// through the filter's attitude and biases. Graded against GNSS while
  /// it is live; applied only in an outage, through the filter's own
  /// innovation gate, and never once GNSS has disowned it.
  void _applyTurnSpeed(
      Vector3 accelVehicle, Vector3 gyroVehicle, int monotonicUs) {
    if (!_config.features.turnSpeed) return;
    if (_motion.vehicleClass == VehicleClass.pedestrian) return;
    final state = _filter.state;
    if (state == null) return;
    final level = TurnSpeedEstimator.levelFrame(
      qBodyToNav: state.qBodyToNav,
      specificForceBody: accelVehicle - state.accelBias,
      angularRateBody: gyroVehicle - state.gyroBias,
    );
    _turn.add(
      lateralAccel: level.lateralAccel,
      yawRate: level.yawRate,
      monotonicUs: monotonicUs,
    );
    final obs = _turn.poll(monotonicUs);
    if (obs == null) return;
    final lastGnss = _lastGnssUs;
    final gnssSpeed = _lastGnssSpeed;
    if (gnssSpeed != null &&
        lastGnss != null &&
        monotonicUs - lastGnss <=
            _config.turnSpeed.validationMaxFixAge.inMicroseconds) {
      _turn.grade(obs, gnssSpeedMps: gnssSpeed);
    }
    if (_outageStartedUs == null || !_turn.trusted) return;
    final result = _filter.updateForwardSpeed(
      speedMps: obs.speedMps,
      sigma: obs.sigmaMps,
      name: 'turn_speed',
    );
    _recordInertial(result);
    if (result.outcome != MeasurementOutcome.skipped) {
      _turn.noteApplied(accepted: result.accepted);
    }
  }

  /// Tyre-vibration speed: learned against steady GNSS speed while GNSS is
  /// live, applied only in an outage and only once the learned scale is
  /// trusted, through the filter's own innovation gate.
  void _applyVibrationSpeed(Vector3 accelVehicle, int monotonicUs) {
    if (!_config.features.vibrationSpeed) return;
    if (_motion.vehicleClass == VehicleClass.pedestrian) return;
    _vib.add(verticalAccel: accelVehicle.z, monotonicUs: monotonicUs);
    final obs = _vib.poll(monotonicUs);
    if (obs == null) return;
    if (_outageStartedUs == null) {
      _vib.learn(obs);
      return;
    }
    final speed = obs.speedMps, sigma = obs.sigmaMps;
    if (speed == null || sigma == null) return;
    final result = _filter.updateForwardSpeed(
      speedMps: speed,
      sigma: sigma,
      name: 'vibration_speed',
    );
    _recordInertial(result);
    if (result.outcome != MeasurementOutcome.skipped) {
      _vib.noteApplied(accepted: result.accepted);
    }
  }

  void _startOutage(int monotonicUs) {
    if (_outageStartedUs != null) return;
    _outageStartedUs = monotonicUs;
    _outageDistanceM = 0;
  }

  void _endOutage() {
    _outageStartedUs = null;
    _outageDistanceM = 0;
  }

  void _record(MeasurementResult result) {
    if (result.outcome == MeasurementOutcome.skipped) return;
    _explainer.record(result, _lastImuUs ?? _lastGnssUs ?? 0);
    _recentMeasurements.add(result);
    while (_recentMeasurements.length > _maxRecentMeasurements) {
      _recentMeasurements.removeAt(0);
    }
  }

  void _updateMode(int monotonicUs) {
    final availability = _timeSync.availability;
    final sawAccelerometer =
        _timeSync.statsFor(SensorType.accelerometer).received > 0;
    if (sawAccelerometer &&
        (!availability.hasMinimumViableSet ||
            !_faults.hasMinimumViableSensors)) {
      _setMode(
          NavMode.sensorFailure, 'minimum sensor set unavailable', monotonicUs);
      return;
    }
    if (_filter.hasFailed) {
      _setMode(NavMode.sensorFailure, _filter.failureReason ?? 'filter failed',
          monotonicUs);
      return;
    }
    if (_alignmentEstimator.alignment == null) {
      if (_config.features.handHeldMode && _handHeldTracker.hasPosition) {
        _updateModeHandHeld(monotonicUs);
        return;
      }
      _setMode(NavMode.calibrating, 'awaiting phone-to-vehicle alignment',
          monotonicUs);
      return;
    }
    if (!_filter.isInitialised) {
      _setMode(NavMode.gnssSearch, 'no position yet', monotonicUs);
      return;
    }

    final reacquiringUntil = _reacquiringUntilUs;
    if (reacquiringUntil != null && monotonicUs < reacquiringUntil) {
      _setMode(
          NavMode.reacquiring, 'settling after a fix returned', monotonicUs);
      return;
    }
    _reacquiringUntilUs = null;

    final lastGnss = _lastGnssUs;
    final gnssFresh = lastGnss != null &&
        monotonicUs - lastGnss <= _config.gnss.staleAfter.inMicroseconds;
    final assessment = _lastAssessment;

    if (!gnssFresh || assessment == null || !assessment.usable) {
      _startOutage(monotonicUs);
      final matched = _matcher.last;
      _setMode(
        matched != null && matched.snapped
            ? NavMode.mapAssistedDeadReckoning
            : NavMode.deadReckoning,
        !gnssFresh
            ? 'no fix within ${_config.gnss.staleAfter.inSeconds}s'
            : 'fix rejected: ${assessment?.reason.name ?? 'unknown'}',
        monotonicUs,
      );
      return;
    }

    if (assessment.integrity == GnssIntegrity.anomaly ||
        assessment.integrity == GnssIntegrity.unreliable) {
      _setMode(NavMode.gnssUnreliable, assessment.integrity.label, monotonicUs);
      return;
    }
    if (assessment.quality == GnssQualityClass.degraded ||
        assessment.quality == GnssQualityClass.poor) {
      _setMode(NavMode.gnssDegraded, 'fix quality ${assessment.quality.name}',
          monotonicUs);
      return;
    }
    // A faulted non-critical sensor degrades a feature, not the position, but
    // the driver is told rather than left to guess (§29).
    final faulted = _faults.faultedSensors;
    if (faulted.isNotEmpty) {
      _setMode(
        NavMode.sensorDegraded,
        '${faulted.map((s) => s.label).join(', ')} unusable',
        monotonicUs,
      );
      return;
    }
    _setMode(NavMode.gnssLocked, 'healthy fix stream', monotonicUs);
  }

  /// Mode dispatch for the hand-held tracker: no mount, so none of the
  /// mounted checks (filter failure, reacquiring, GNSS quality classes,
  /// sensor faults) apply to it - only whether a fix is still fresh.
  void _updateModeHandHeld(int monotonicUs) {
    final lastGnss = _lastGnssUs;
    final gnssFresh = lastGnss != null &&
        monotonicUs - lastGnss <= _config.gnss.staleAfter.inMicroseconds;
    if (!gnssFresh) {
      _startOutage(monotonicUs);
      _setMode(
        NavMode.deadReckoning,
        'hand-held: no fix within ${_config.gnss.staleAfter.inSeconds}s',
        monotonicUs,
      );
    } else {
      _endOutage();
      _setMode(NavMode.gnssLocked, 'hand-held: healthy fix stream', monotonicUs);
    }
  }

  void _setMode(NavMode next, String reason, int monotonicUs) {
    if (_mode == next) return;
    _transitions.add(ModeTransition(
      from: _mode,
      to: next,
      reason: reason,
      monotonicUs: monotonicUs,
    ));
    while (_transitions.length > _maxTransitions) {
      _transitions.removeAt(0);
    }
    _mode = next;
  }

  NavIntegrity _integrity() {
    if (_filter.hasFailed) return NavIntegrity.invalid;
    if (!_filter.isInitialised) {
      // Hand-held: honest about what this model is. It never claims better
      // than medium — there is no known vehicle frame to be more sure of —
      // and drops further while the phone is actively being handled, or once
      // its own sigma says it has drifted too far to be worth using.
      if (_config.features.handHeldMode && _handHeldTracker.hasPosition) {
        final sigma = _handHeldTracker.horizontalSigmaM;
        if (!sigma.isFinite) return NavIntegrity.invalid;
        if (sigma > 150) return NavIntegrity.invalid;
        if (_handling.isHandling || sigma > 60) return NavIntegrity.low;
        return NavIntegrity.medium;
      }
      return NavIntegrity.invalid;
    }
    final sigma = _filter.horizontalPositionSigma;
    if (sigma == null || !sigma.isFinite) return NavIntegrity.invalid;
    if (sigma > _config.ekf.maxPositionSigma) return NavIntegrity.invalid;

    if (_motion.snapshot.state == VehicleState.sensorAnomaly) {
      return NavIntegrity.low;
    }
    final gnssAnomaly = _lastAssessment?.integrity == GnssIntegrity.anomaly;
    if (gnssAnomaly) return NavIntegrity.low;

    // A mount that has not converged means the body frame — and therefore the
    // direction of travel — is only approximate, however tight the covariance.
    if (!_alignmentEstimator.isConverged) return NavIntegrity.medium;

    if (sigma > 60) return NavIntegrity.low;
    if (sigma > 20) return NavIntegrity.medium;
    return NavIntegrity.high;
  }

  NavigationSnapshot? _maybeSnapshot(int monotonicUs, {required bool force}) {
    final minInterval = 1000000 ~/ _config.power.uiHz;
    if (!force && monotonicUs - _lastSnapshotUs < minInterval) return null;
    _lastSnapshotUs = monotonicUs;

    final state = _filter.state;
    final handHeldActive = state == null &&
        _config.features.handHeldMode &&
        _handHeldTracker.hasPosition;
    final unaligned = (state == null && !handHeldActive) ? _lastUnalignedFix : null;
    final recalibratingMount = _mountChangedAtUs != null;
    final notes = <String>[];
    if (recalibratingMount) {
      notes.add('Mount change detected — previous calibration '
          'invalidated. Recalibrating vehicle frame…');
    } else if (_alignmentEstimator.alignment == null) {
      notes.add(handHeldActive
          ? 'Hand-held mode: no phone-to-vehicle mount'
          : 'Phone-to-vehicle alignment not established');
    } else if (!_alignmentEstimator.isConverged) {
      notes.add('Mount alignment still converging');
    }
    if (_calibration.isEmpty) {
      notes.add('Sensors not calibrated');
    } else if (_calibration.isStale(
      nowMs: DateTime.fromMicrosecondsSinceEpoch(monotonicUs)
          .millisecondsSinceEpoch,
      temperatureC: _lastTemperatureC,
      config: _config,
    )) {
      notes.add('Stored calibration is stale; re-calibrate');
    }
    final assessment = _lastAssessment;
    if (assessment != null) notes.addAll(assessment.notes);
    for (final diagnosis in _faults.diagnoses.values) {
      if (diagnosis.samples > 0 && !diagnosis.usable) {
        notes.add('${diagnosis.type.label}: ${diagnosis.fault.label}');
      }
    }

    final healthReport = _health.evaluate(monotonicUs: monotonicUs);
    final mountQuality = _mountQualityEstimator.evaluate(
      orientationWobbleDeg: _health.orientationWobbleDeg,
      handling: _health.isHandling,
      vibrationScore: _ai.effectiveDisturbance(monotonicUs).vibrationScore,
      magneticFieldMicroTesla:
          _faults.diagnoses[SensorType.magnetometer]?.magnitude,
      alignmentConfidence: _alignmentEstimator.alignment?.confidence,
    );

    _snapshot = NavigationSnapshot(
      sequence: ++_sequence,
      monotonicUs: monotonicUs,
      mode: _mode,
      integrity: _integrity(),
      latitude: state?.latitudeDeg ??
          (handHeldActive ? _handHeldTracker.latitudeDeg : unaligned?.latitudeDeg),
      longitude: state?.longitudeDeg ??
          (handHeldActive ? _handHeldTracker.longitudeDeg : unaligned?.longitudeDeg),
      altitude: state?.altitudeM ?? unaligned?.altitudeM,
      speedMps: state?.groundSpeed ??
          (handHeldActive ? _handHeldTracker.speedMps : unaligned?.speedMps),
      headingDeg: state?.headingDeg ??
          (handHeldActive ? _handHeldTracker.headingDeg : unaligned?.bearingDeg),
      horizontalSigmaM: _filter.horizontalPositionSigma ??
          (handHeldActive ? _handHeldTracker.horizontalSigmaM : null),
      verticalSigmaM: _filter.verticalPositionSigma,
      speedSigmaMps: _filter.speedSigma ??
          (handHeldActive ? _handHeldTracker.speedSigmaMps : null),
      headingSigmaDeg: _filter.headingSigmaDeg ??
          (handHeldActive ? _handHeldTracker.headingSigmaDeg : null),
      gnss: assessment,
      motion: _motion.snapshot,
      sensorStats: _timeSync.stats,
      sensorFaults: _faults.diagnoses,
      barometer: _barometer.last,
      alignmentConfidence: _alignmentEstimator.alignment?.confidence,
      calibrationQuality: _calibration.gyroBiasQuality,
      contribution: _contribution.snapshot,
      // Unavailable until a model has genuinely spoken to the engine (§83).
      ai: _aiHealth(aiDiagnostics),
      aiDiagnostics: aiDiagnostics,
      mapMatch: _mapHealth(),
      mapMatchResult: _matcher.last,
      outageDuration: _outageStartedUs == null
          ? Duration.zero
          : Duration(microseconds: monotonicUs - _outageStartedUs!),
      outageDistanceM: _outageDistanceM,
      lastRecovery: _lastRecovery,
      positionSource: (state != null || handHeldActive)
          ? (_mode.isDeadReckoning ? DataSource.estimated : DataSource.real)
          : (unaligned == null ? DataSource.unavailable : DataSource.real),
      notes: notes,
      handHeld: handHeldActive,
      sensorHealth: healthReport,
      mountQuality: mountQuality,
      recalibratingMount: recalibratingMount,
      faultFlags: _faultMonitor.flags,
    );
    return _snapshot;
  }

  SubsystemHealth _aiHealth(AiDiagnostics d) {
    if (!d.enabled) {
      return const SubsystemHealth(
        available: false,
        source: DataSource.unavailable,
        detail: 'Neural velocity disabled',
      );
    }
    if (d.speedObserved == 0 && d.disturbance?.source != EstimateSource.model) {
      return const SubsystemHealth(
        available: false,
        source: DataSource.unavailable,
        detail: 'Model not loaded',
      );
    }
    return SubsystemHealth(
      available: d.speedApplied > 0,
      // Derived by the filter from a model's output, not measured.
      source: DataSource.estimated,
      detail: d.summary,
    );
  }

  SubsystemHealth _mapHealth() {
    if (!_matcher.isAvailable) {
      return const SubsystemHealth(
        available: false,
        source: DataSource.unavailable,
        detail: 'No road graph',
      );
    }
    final result = _matcher.last;
    if (result == null) {
      return const SubsystemHealth(
        available: true,
        source: DataSource.real,
        detail: 'Waiting for a position to match',
      );
    }
    return SubsystemHealth(
      available: true,
      source: DataSource.real,
      score: result.snapped ? result.confidence : null,
      detail: result.reason,
    );
  }

  static bool _finite(Vector3 v) =>
      v.x.isFinite && v.y.isFinite && v.z.isFinite;
}
