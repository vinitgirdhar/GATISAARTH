import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ins/ins_state.dart';
import '../math/matrix.dart';
import '../math/nav_math.dart';
import '../nav_config.dart';

/// Error-state indices (§11). `x_true = x_nominal + dx`, attitude excepted:
/// there the true attitude is `deltaQ(dTheta) * q_nominal` in the nav frame.
class ErrorState {
  const ErrorState._();

  static const int positionN = 0;
  static const int velocityN = 3;
  static const int attitudeN = 6;
  static const int accelBiasN = 9;
  static const int gyroBiasN = 12;
  static const int size = 15;
}

/// Why a measurement was or was not folded into the state.
enum MeasurementOutcome {
  /// Residual passed the chi-square gate and the correction was applied.
  accepted,

  /// Residual failed the gate (§14) — almost certainly a bad measurement.
  rejectedByGate,

  /// The innovation covariance could not be inverted, so no gain exists.
  singular,

  /// The filter is not initialised, or the measurement was not finite.
  skipped,
}

@immutable
class MeasurementResult {
  const MeasurementResult({
    required this.name,
    required this.outcome,
    this.nis,
    this.gateLimit,
    this.residual = const [],
    this.rejectStreak = 0,
    this.positionVarianceReduction = 0,
  });

  final String name;
  final MeasurementOutcome outcome;

  /// Normalised innovation squared, when it could be computed.
  final double? nis;
  final double? gateLimit;
  final List<double> residual;

  /// How many times in a row this measurement has now been rejected (§14).
  final int rejectStreak;

  /// How much horizontal position variance (m²) this update removed.
  ///
  /// The one unit-consistent way to compare what different measurements
  /// did for the position estimate: a GNSS fix, a zero-velocity update and
  /// a road heading all report in m², so they can honestly be added up and
  /// normalised (§51). Summing `1/sigma^2` across metres, m/s² and radians
  /// cannot — those are different quantities.
  final double positionVarianceReduction;

  bool get accepted => outcome == MeasurementOutcome.accepted;

  @override
  String toString() => '$name ${outcome.name}'
      '${nis == null ? '' : ' NIS=${nis!.toStringAsFixed(2)}'}'
      '${gateLimit == null ? '' : '/${gateLimit!.toStringAsFixed(2)}'}';
}

/// Strapdown INS plus a 15-state error-state Kalman filter (§10, §11).
///
/// The INS propagates the nominal state at IMU rate; the filter tracks the
/// *error* in that state and its covariance, and feeds corrections back after
/// each accepted measurement (closed loop, error state reset to zero).
///
/// Everything that can go wrong numerically is contained: a singular
/// innovation covariance skips the update, a non-finite state marks the filter
/// failed rather than emitting garbage, the covariance is re-symmetrised and
/// floored after every step (§62).
///
/// **Observability, stated plainly.** While the vehicle is stationary,
/// accelerometer bias and vehicle tilt are not separately observable: a
/// 0.3 m/s² forward bias and a 1.75° nose-up pitch produce an identical
/// specific-force measurement. A zero-velocity update therefore stops the
/// velocity drift (which is what matters for position) but attributes the
/// cause to whichever of the two the covariance says is more uncertain. Only
/// changing acceleration separates them — which is why §5 calibration asks for
/// a guided movement and §6 alignment needs a short drive. Nothing here should
/// be read as "the filter learns the accelerometer bias at a red light".
class NavigationFilter {
  NavigationFilter({NavConfig config = NavConfig.defaults})
      : _config = config,
        _ekf = config.ekf,
        _ins = config.ins;

  final NavConfig _config;
  final EkfConfig _ekf;
  final InsConfig _ins;

  InsState? _state;
  Matrix _p = Matrix(ErrorState.size, ErrorState.size);
  bool _failed = false;
  String? _failureReason;
  int _predictions = 0;
  int _corrections = 0;
  final Map<String, int> _rejectStreak = {};

  NavConfig get config => _config;

  /// Null until [initialise] has run. Callers must handle that — the app shows
  /// `--` rather than a placeholder position (§65).
  InsState? get state => _state;

  bool get isInitialised => _state != null && !_failed;
  bool get hasFailed => _failed;
  String? get failureReason => _failureReason;
  int get predictionCount => _predictions;
  int get correctionCount => _corrections;

  /// Copy of the covariance. Callers that only want uncertainty should use the
  /// sigma getters below rather than reaching into the matrix.
  Matrix get covariance => _p.copy();

  // ------------------------------------------------------------ uncertainty

  /// 1-sigma horizontal position uncertainty (m), null before initialisation.
  double? get horizontalPositionSigma {
    if (!isInitialised) return null;
    return NavMath.horizontalSigma(
      _p.at(ErrorState.positionN, ErrorState.positionN),
      _p.at(ErrorState.positionN, ErrorState.positionN + 1),
      _p.at(ErrorState.positionN + 1, ErrorState.positionN + 1),
    );
  }

  double? get verticalPositionSigma => isInitialised
      ? math.sqrt(math.max(
          0.0, _p.at(ErrorState.positionN + 2, ErrorState.positionN + 2)))
      : null;

  /// 1-sigma horizontal speed uncertainty (m/s).
  double? get speedSigma {
    if (!isInitialised) return null;
    final vn = _p.at(ErrorState.velocityN, ErrorState.velocityN);
    final ve = _p.at(ErrorState.velocityN + 1, ErrorState.velocityN + 1);
    return math.sqrt(math.max(0.0, vn + ve));
  }

  /// 1-sigma heading uncertainty (deg).
  double? get headingSigmaDeg {
    if (!isInitialised) return null;
    final v = _p.at(ErrorState.attitudeN + 2, ErrorState.attitudeN + 2);
    return math.sqrt(math.max(0.0, v)) * NavMath.radToDeg;
  }

  Vector3? get accelBiasSigma => isInitialised
      ? Vector3(
          math.sqrt(math.max(0.0, _p.at(9, 9))),
          math.sqrt(math.max(0.0, _p.at(10, 10))),
          math.sqrt(math.max(0.0, _p.at(11, 11))),
        )
      : null;

  Vector3? get gyroBiasSigma => isInitialised
      ? Vector3(
          math.sqrt(math.max(0.0, _p.at(12, 12))),
          math.sqrt(math.max(0.0, _p.at(13, 13))),
          math.sqrt(math.max(0.0, _p.at(14, 14))),
        )
      : null;

  // ------------------------------------------------------------ lifecycle

  /// Starts the filter at a known position.
  ///
  /// [positionSigma] should be the GNSS accuracy of the seeding fix; the
  /// default is the config's much looser prior, for a cold start from a cached
  /// position where the real uncertainty is unknown.
  void initialise({
    required double latitudeDeg,
    required double longitudeDeg,
    double altitudeM = 0,
    double headingRad = 0,
    Vector3? gravityBody,
    Vector3? initialVelocityNed,
    Vector3? accelBias,
    Vector3? gyroBias,
    double? positionSigma,
    double? velocitySigma,
    double? headingSigma,
    double? attitudeSigma,
    int timestampUs = 0,
  }) {
    final seeded = InsState.seeded(
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      altitudeM: altitudeM,
      headingRad: headingRad,
      gravityBody: gravityBody,
      timestampUs: timestampUs,
    );
    _state = seeded.copyWith(
      velocityNed: initialVelocityNed,
      accelBias: accelBias,
      gyroBias: gyroBias,
    );

    final pSigma = positionSigma ?? _ekf.initialPositionSigma;
    final vSigma = velocitySigma ?? _ekf.initialVelocitySigma;
    final yawSigma = headingSigma ?? _ekf.initialYawSigma;
    // Roll and pitch are only as uncertain as the gravity vector that set
    // them; claiming otherwise invites the filter to throw the seed away.
    final rpSigma = attitudeSigma ??
        (gravityBody != null
            ? _ekf.levelledAttitudeSigma
            : _ekf.initialAttitudeSigma);
    _p = Matrix.diagonal([
      pSigma * pSigma,
      pSigma * pSigma,
      // Vertical GNSS accuracy is typically 1.5-3x horizontal.
      (pSigma * 2) * (pSigma * 2),
      vSigma * vSigma, vSigma * vSigma, vSigma * vSigma,
      // Gravity observes roll and pitch immediately; yaw does not become
      // observable until the vehicle moves, so it starts wide.
      _sq(rpSigma), _sq(rpSigma),
      yawSigma * yawSigma,
      _sq(_ekf.initialAccelBiasSigma), _sq(_ekf.initialAccelBiasSigma),
      _sq(_ekf.initialAccelBiasSigma),
      _sq(_ekf.initialGyroBiasSigma), _sq(_ekf.initialGyroBiasSigma),
      _sq(_ekf.initialGyroBiasSigma),
    ]);
    _failed = false;
    _failureReason = null;
    _predictions = 0;
    _corrections = 0;
    _rejectStreak.clear();
  }

  void reset() {
    _state = null;
    _p = Matrix(ErrorState.size, ErrorState.size);
    _failed = false;
    _failureReason = null;
    _predictions = 0;
    _corrections = 0;
    _rejectStreak.clear();
  }

  // ------------------------------------------------------------- prediction

  /// One strapdown step and the matching covariance propagation.
  ///
  /// [accelBody] is raw specific force (m/s², gravity included, bias not
  /// removed), [gyroBody] raw angular rate (rad/s). Returns false when the
  /// step was refused — `dt` out of range, non-finite input, or the filter is
  /// not running.
  ///
  /// [processNoiseScale] multiplies the whole process-noise matrix for this
  /// step (1 = as configured). It is how a disturbance estimate or an AI trust
  /// tells the filter the inertial data is worse than nominal right now. A
  /// non-positive or non-finite value is ignored rather than trusted.
  bool predict({
    required Vector3 accelBody,
    required Vector3 gyroBody,
    required double dt,
    double processNoiseScale = 1.0,
  }) {
    final current = _state;
    if (current == null || _failed) return false;
    if (!dt.isFinite || dt < _ins.minDt || dt > _ins.maxDt) return false;
    if (!_finiteVector(accelBody) || !_finiteVector(gyroBody)) return false;

    // A spike this large is a sensor fault, not a manoeuvre (§62).
    if (accelBody.length > _ins.maxAccel ||
        gyroBody.length > _ins.maxAngularRate) {
      return false;
    }

    final fBody = accelBody - current.accelBias;
    final omegaBody = gyroBody - current.gyroBias;

    final cbn = NavMath.rotationMatrix(current.qBodyToNav);
    final Vector3 fNav = cbn * fBody;
    // Specific force plus gravity gives kinematic acceleration. NED has down
    // positive, so at rest fNav is (0,0,-g) and the two cancel.
    final aNav = fNav + Vector3(0, 0, NavMath.gravity);

    final vNext = current.velocityNed + aNav * dt;
    // Trapezoidal position update: using the mean of the two velocities keeps
    // a constant-acceleration segment exact instead of lagging by 0.5*a*dt².
    final meanV = (current.velocityNed + vNext) * 0.5;
    final moved = NavMath.addNed(
      latDeg: current.latitudeDeg,
      lonDeg: current.longitudeDeg,
      altM: current.altitudeM,
      north: meanV.x * dt,
      east: meanV.y * dt,
      down: meanV.z * dt,
    );

    final qNext = NavMath.propagate(current.qBodyToNav, omegaBody, dt);

    // Bias states decay towards zero on their Gauss-Markov time constants.
    final aDecay = math.exp(-dt / _ekf.accelBiasTau);
    final gDecay = math.exp(-dt / _ekf.gyroBiasTau);

    final next = InsState(
      latitudeDeg: moved[0],
      longitudeDeg: moved[1],
      altitudeM: moved[2],
      velocityNed: vNext,
      qBodyToNav: qNext,
      accelBias: current.accelBias * aDecay,
      gyroBias: current.gyroBias * gDecay,
      timestampUs: current.timestampUs + (dt * 1e6).round(),
    );

    if (!next.isFinite || next.groundSpeed > _ins.maxSpeed) {
      _fail('INS diverged: ${next.groundSpeed.toStringAsFixed(1)} m/s');
      return false;
    }

    _propagateCovariance(
      cbn: cbn,
      fNav: fNav,
      dt: dt,
      noiseScale: processNoiseScale.isFinite && processNoiseScale > 0
          ? processNoiseScale
          : 1.0,
    );
    _state = next;
    _predictions++;
    return true;
  }

  void _propagateCovariance({
    required Matrix3 cbn,
    required Vector3 fNav,
    required double dt,
    required double noiseScale,
  }) {
    // F = I + A*dt, first order. At 50-100 Hz the higher-order terms are
    // several orders of magnitude below the process noise.
    final f = Matrix.identity(ErrorState.size);

    // dPosition/dt = dVelocity
    for (var i = 0; i < 3; i++) {
      f.set(ErrorState.positionN + i, ErrorState.velocityN + i, dt);
    }

    // dVelocity/dt gets -[fNav x] dTheta - Cbn dAccelBias
    final skewF = NavMath.skew(fNav);
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        f.set(ErrorState.velocityN + r, ErrorState.attitudeN + c,
            -skewF.entry(r, c) * dt);
        f.set(ErrorState.velocityN + r, ErrorState.accelBiasN + c,
            -cbn.entry(r, c) * dt);
        // dAttitude/dt gets -Cbn dGyroBias
        f.set(ErrorState.attitudeN + r, ErrorState.gyroBiasN + c,
            -cbn.entry(r, c) * dt);
      }
    }

    // Bias error decay.
    final aDecay = 1 - dt / _ekf.accelBiasTau;
    final gDecay = 1 - dt / _ekf.gyroBiasTau;
    for (var i = 0; i < 3; i++) {
      f.set(ErrorState.accelBiasN + i, ErrorState.accelBiasN + i, aDecay);
      f.set(ErrorState.gyroBiasN + i, ErrorState.gyroBiasN + i, gDecay);
    }

    final q = Matrix(ErrorState.size, ErrorState.size);
    final accelVar = _sq(_ekf.accelNoiseDensity) * dt * noiseScale;
    final gyroVar = _sq(_ekf.gyroNoiseDensity) * dt * noiseScale;
    final accelBiasVar = _sq(_ekf.accelBiasRandomWalk) * dt * noiseScale;
    final gyroBiasVar = _sq(_ekf.gyroBiasRandomWalk) * dt * noiseScale;
    for (var i = 0; i < 3; i++) {
      // Velocity random walk driven by accelerometer noise, and the position
      // noise it induces over the step.
      q.set(ErrorState.positionN + i, ErrorState.positionN + i,
          accelVar * dt * dt / 3);
      q.set(ErrorState.velocityN + i, ErrorState.velocityN + i, accelVar);
      q.set(ErrorState.attitudeN + i, ErrorState.attitudeN + i, gyroVar);
      q.set(ErrorState.accelBiasN + i, ErrorState.accelBiasN + i, accelBiasVar);
      q.set(ErrorState.gyroBiasN + i, ErrorState.gyroBiasN + i, gyroBiasVar);
    }

    _p = (f * _p * f.transposed + q).symmetrized();
    _applyCovarianceFloors();
    if (!_p.isFinite) _fail('covariance went non-finite during prediction');
  }

  // ------------------------------------------------------------ corrections

  /// GNSS position update. [sigmas] are 1-sigma north, east and vertical
  /// errors in metres — normally derived from the fix accuracy and the GNSS
  /// quality score (§12 adaptive R).
  MeasurementResult updatePosition({
    required double latitudeDeg,
    required double longitudeDeg,
    double? altitudeM,
    required double horizontalSigma,
    double? verticalSigma,
    String name = 'gnss_position',
  }) {
    final current = _state;
    if (current == null || _failed) return _skip(name);
    if (!latitudeDeg.isFinite || !longitudeDeg.isFinite) return _skip(name);

    final useAltitude = altitudeM != null && altitudeM.isFinite;
    final ned = NavMath.nedBetween(
      lat0: current.latitudeDeg,
      lon0: current.longitudeDeg,
      alt0: current.altitudeM,
      lat1: latitudeDeg,
      lon1: longitudeDeg,
      alt1: useAltitude ? altitudeM : current.altitudeM,
    );

    final rows = useAltitude ? 3 : 2;
    final h = Matrix(rows, ErrorState.size);
    for (var i = 0; i < rows; i++) {
      h.set(i, ErrorState.positionN + i, 1);
    }
    final residual = Matrix.column(
      useAltitude ? [ned.x, ned.y, ned.z] : [ned.x, ned.y],
    );
    final vSigma = verticalSigma ?? horizontalSigma * 2;
    final r = Matrix.diagonal(
      useAltitude
          ? [_sq(horizontalSigma), _sq(horizontalSigma), _sq(vSigma)]
          : [_sq(horizontalSigma), _sq(horizontalSigma)],
    );
    return _applyUpdate(name: name, h: h, residual: residual, r: r);
  }

  /// GNSS (or any) navigation-frame velocity update.
  MeasurementResult updateVelocityNed({
    required Vector3 velocityNed,
    required Vector3 sigmas,
    String name = 'gnss_velocity',
  }) {
    final current = _state;
    if (current == null || _failed) return _skip(name);
    if (!_finiteVector(velocityNed)) return _skip(name);

    final h = Matrix(3, ErrorState.size);
    for (var i = 0; i < 3; i++) {
      h.set(i, ErrorState.velocityN + i, 1);
    }
    final diff = velocityNed - current.velocityNed;
    return _applyUpdate(
      name: name,
      h: h,
      residual: Matrix.column([diff.x, diff.y, diff.z]),
      r: Matrix.diagonal([_sq(sigmas.x), _sq(sigmas.y), _sq(sigmas.z)]),
    );
  }

  /// Body-frame velocity update along selected axes.
  ///
  /// This is the workhorse behind the non-holonomic constraint (§17: lateral
  /// and vertical velocity are ~0 for a car), the zero-velocity update (§16:
  /// all three axes are 0) and the neural velocity estimate (§8: the forward
  /// axis only). Treating them as *measurements* rather than clamps is what
  /// lets the filter learn the biases that cause the error in the first place.
  ///
  /// [axes] selects which of forward(0) / right(1) / down(2) are observed.
  MeasurementResult updateBodyVelocity({
    required List<int> axes,
    required List<double> measured,
    required List<double> sigmas,
    String name = 'body_velocity',
    bool gated = true,
  }) {
    final current = _state;
    if (current == null || _failed) return _skip(name);
    if (axes.isEmpty ||
        axes.length != measured.length ||
        axes.length != sigmas.length) {
      return _skip(name);
    }
    if (measured.any((v) => !v.isFinite) || sigmas.any((s) => !(s > 0))) {
      return _skip(name);
    }

    final model = _bodyVelocityModel(current, axes);
    final residual = Matrix(axes.length, 1);
    for (var row = 0; row < axes.length; row++) {
      residual.set(row, 0, measured[row] - model.predicted[axes[row]]);
    }
    return _applyUpdate(
      name: name,
      h: model.h,
      residual: residual,
      r: Matrix.diagonal(sigmas.map(_sq).toList()),
      gated: gated,
    );
  }

  /// The measurement Jacobian for observing the body-frame velocity components
  /// in [axes], and the body-frame velocity the state currently predicts.
  ({Matrix h, Vector3 predicted}) _bodyVelocityModel(
      InsState current, List<int> axes) {
    final cnb = NavMath.rotationMatrix(current.qBodyToNav).transposed();
    final Vector3 predicted = cnb * current.velocityNed;
    // d(v_body)/d(dTheta) = C_nb [v_nav x]  (see EVOLUTION_PLAN §8)
    final Matrix3 jacobianAttitude = cnb * NavMath.skew(current.velocityNed);

    final h = Matrix(axes.length, ErrorState.size);
    for (var row = 0; row < axes.length; row++) {
      final axis = axes[row];
      for (var c = 0; c < 3; c++) {
        h.set(row, ErrorState.velocityN + c, cnb.entry(axis, c));
        h.set(row, ErrorState.attitudeN + c, jacobianAttitude.entry(axis, c));
      }
    }
    return (h: h, predicted: predicted);
  }

  /// The forward speed the filter believes (m/s, body x), or null when it is
  /// not running. This is what an AI speed measurement is compared with.
  double? get forwardSpeed =>
      isInitialised ? _state!.velocityBody.x : null;

  /// Variance of that forward speed, `H P H^T` for the forward axis (m²/s²).
  double? get forwardSpeedVariance {
    final current = _state;
    if (current == null || _failed) return null;
    final h = _bodyVelocityModel(current, const [0]).h;
    return (h * _p * h.transposed).at(0, 0);
  }

  /// Zero-velocity update: the vehicle is stopped, so body velocity is zero on
  /// every axis (§16).
  MeasurementResult updateZeroVelocity({double? sigma}) => updateBodyVelocity(
        axes: const [0, 1, 2],
        measured: const [0, 0, 0],
        sigmas: List.filled(3, sigma ?? _ekf.zuptVelocitySigma),
        name: 'zupt',
      );

  /// Zero angular-rate update: while stopped, the measured gyro *is* the bias
  /// (§16). This is what stops heading drifting during a traffic light.
  MeasurementResult updateZeroAngularRate({
    required Vector3 gyroBody,
    double? sigma,
  }) {
    final current = _state;
    if (current == null || _failed) return _skip('zaru');
    if (!_finiteVector(gyroBody)) return _skip('zaru');

    final h = Matrix(3, ErrorState.size);
    for (var i = 0; i < 3; i++) {
      h.set(i, ErrorState.gyroBiasN + i, 1);
    }
    final diff = gyroBody - current.gyroBias;
    final s = sigma ?? _ekf.zaruSigma;
    return _applyUpdate(
      name: 'zaru',
      h: h,
      residual: Matrix.column([diff.x, diff.y, diff.z]),
      r: Matrix.diagonal([_sq(s), _sq(s), _sq(s)]),
    );
  }

  /// Non-holonomic constraint: a wheeled vehicle does not slide sideways or
  /// climb off the road (§17).
  ///
  /// [lateralSigma] should come from the vehicle profile — tight for a car,
  /// loose for a leaning two-wheeler. Callers must suppress this while
  /// turning hard, where the assumption is weakest.
  MeasurementResult updateNonHolonomic({
    required double lateralSigma,
    double? verticalSigma,
  }) =>
      updateBodyVelocity(
        axes: const [1, 2],
        measured: const [0, 0],
        sigmas: [lateralSigma, verticalSigma ?? lateralSigma],
        name: 'nhc',
      );

  /// Forward-speed update, e.g. from the neural velocity estimator (§8).
  ///
  /// With [preGated] the caller has already decided this measurement is
  /// believable (the AI speed gate compares it with the INS in combined
  /// sigmas), so the filter's chi-square test is skipped — and, importantly, so
  /// is the reject streak: a filter left to refuse a biased model over and over
  /// would widen its own velocity covariance every few refusals (see
  /// [_applyUpdate]) until it gave in. The NIS is still reported. **A pre-gated
  /// update is applied whatever it says**, so only pass it after gating.
  MeasurementResult updateForwardSpeed({
    required double speedMps,
    required double sigma,
    String name = 'forward_speed',
    bool preGated = false,
  }) =>
      updateBodyVelocity(
        axes: const [0],
        measured: [speedMps],
        sigmas: [sigma],
        name: name,
        gated: !preGated,
      );

  /// Barometric altitude update (§18). Secondary evidence, never truth: the
  /// caller supplies a sigma that reflects the pressure drift since the last
  /// GNSS altitude.
  MeasurementResult updateAltitude({
    required double altitudeM,
    double? sigma,
    String name = 'baro_altitude',
  }) {
    final current = _state;
    if (current == null || _failed) return _skip(name);
    if (!altitudeM.isFinite) return _skip(name);

    final h = Matrix(1, ErrorState.size);
    // Down is positive, so a *higher* altitude is a negative down error.
    h.set(0, ErrorState.positionN + 2, 1);
    final s = sigma ?? _ekf.baroSigma;
    return _applyUpdate(
      name: name,
      h: h,
      residual: Matrix.column([-(altitudeM - current.altitudeM)]),
      r: Matrix.diagonal([_sq(s)]),
    );
  }

  /// Heading update from an external bearing (magnetometer, road heading).
  ///
  /// [measuredHeadingRad] is the true heading the source believes; the filter
  /// corrects its yaw towards it.
  MeasurementResult updateHeading({
    required double measuredHeadingRad,
    double? sigma,
    String name = 'heading',
  }) {
    final current = _state;
    if (current == null || _failed) return _skip(name);
    if (!measuredHeadingRad.isFinite) return _skip(name);

    final predicted = NavMath.headingFromQuaternion(current.qBodyToNav);
    final h = Matrix(1, ErrorState.size);
    h.set(0, ErrorState.attitudeN + 2, 1);
    final s = sigma ?? _ekf.magYawSigma;
    return _applyUpdate(
      name: name,
      h: h,
      residual:
          Matrix.column([NavMath.wrapPi(measuredHeadingRad - predicted)]),
      r: Matrix.diagonal([_sq(s)]),
    );
  }

  /// Heading update straight from a magnetometer reading (§6, §12).
  ///
  /// Returns a skipped result when the field has no usable horizontal
  /// component — better no update than a fabricated bearing.
  MeasurementResult updateMagnetometer({
    required Vector3 magBody,
    double? sigma,
    double declinationRad = 0,
  }) {
    final current = _state;
    if (current == null || _failed) return _skip('magnetometer');
    final yawError = NavMath.magneticYawError(
      q: current.qBodyToNav,
      magBody: magBody,
      declinationRad: declinationRad,
    );
    if (yawError == null) return _skip('magnetometer');

    // magneticYawError returns how far the *nominal* attitude over-rotates,
    // so the error-state residual is its negation.
    final h = Matrix(1, ErrorState.size);
    h.set(0, ErrorState.attitudeN + 2, 1);
    final s = sigma ?? _ekf.magYawSigma;
    return _applyUpdate(
      name: 'magnetometer',
      h: h,
      residual: Matrix.column([-yawError]),
      r: Matrix.diagonal([_sq(s)]),
    );
  }

  // ------------------------------------------------------------- internals

  MeasurementResult _applyUpdate({
    required String name,
    required Matrix h,
    required Matrix residual,
    required Matrix r,
    bool gated = true,
  }) {
    if (!h.isFinite || !residual.isFinite || !r.isFinite) return _skip(name);

    final ht = h.transposed;
    final s = (h * _p * ht + r).symmetrized();
    final sInv = s.inverse();
    if (sInv == null) {
      return MeasurementResult(
        name: name,
        outcome: MeasurementOutcome.singular,
        residual: residual.columnValues,
      );
    }

    final nis = (residual.transposed * sInv * residual).at(0, 0);
    final dof = residual.rows;
    final gate = dof < NavMath.chiSquare99.length
        ? NavMath.chiSquare99[dof]
        : dof * 3.0;
    if (!nis.isFinite) return _skip(name);
    if (gated && nis > gate) {
      // Rejected. The measurement is inconsistent with the state and its
      // covariance — folding it in would teleport the estimate (§14).
      //
      // But a filter that rejects the same measurement forever has decided it
      // is right and the world is wrong, which is how an EKF gets permanently
      // lost. After a streak, inflate the covariance of exactly the states
      // this measurement observes, so the next one can be heard (§14).
      final streak = (_rejectStreak[name] ?? 0) + 1;
      _rejectStreak[name] = streak;
      if (streak >= _ekf.consecutiveRejectLimit) {
        _inflateObservedStates(h);
        _rejectStreak[name] = 0;
      }
      return MeasurementResult(
        name: name,
        outcome: MeasurementOutcome.rejectedByGate,
        nis: nis,
        gateLimit: gate,
        residual: residual.columnValues,
        rejectStreak: streak,
      );
    }
    _rejectStreak[name] = 0;

    final k = _p * ht * sInv;
    final dx = (k * residual).columnValues;
    if (dx.any((v) => !v.isFinite)) return _skip(name);

    final positionVarianceBefore = _horizontalPositionTrace();

    // Joseph form: stays symmetric and positive semi-definite even when the
    // gain is not exactly optimal, which the simple (I-KH)P form does not.
    final ikh = Matrix.identity(ErrorState.size) - k * h;
    _p = (ikh * _p * ikh.transposed + k * r * k.transposed).symmetrized();
    _applyCovarianceFloors();

    _injectError(dx);
    _corrections++;

    if (!_p.isFinite) {
      _fail('covariance went non-finite after $name');
    }
    return MeasurementResult(
      name: name,
      outcome: MeasurementOutcome.accepted,
      nis: nis,
      gateLimit: gate,
      residual: residual.columnValues,
      positionVarianceReduction: math.max(
        0.0,
        positionVarianceBefore - _horizontalPositionTrace(),
      ),
    );
  }

  /// Folds the error estimate into the nominal state and resets it to zero
  /// (closed-loop error-state formulation).
  void _injectError(List<double> dx) {
    final current = _state!;
    final moved = NavMath.addNed(
      latDeg: current.latitudeDeg,
      lonDeg: current.longitudeDeg,
      altM: current.altitudeM,
      north: dx[ErrorState.positionN],
      east: dx[ErrorState.positionN + 1],
      down: dx[ErrorState.positionN + 2],
    );
    final next = InsState(
      latitudeDeg: moved[0],
      longitudeDeg: moved[1],
      altitudeM: moved[2],
      velocityNed: current.velocityNed +
          Vector3(
            dx[ErrorState.velocityN],
            dx[ErrorState.velocityN + 1],
            dx[ErrorState.velocityN + 2],
          ),
      qBodyToNav: NavMath.applyNavFrameError(
        current.qBodyToNav,
        Vector3(
          dx[ErrorState.attitudeN],
          dx[ErrorState.attitudeN + 1],
          dx[ErrorState.attitudeN + 2],
        ),
      ),
      accelBias: current.accelBias +
          Vector3(
            dx[ErrorState.accelBiasN],
            dx[ErrorState.accelBiasN + 1],
            dx[ErrorState.accelBiasN + 2],
          ),
      gyroBias: current.gyroBias +
          Vector3(
            dx[ErrorState.gyroBiasN],
            dx[ErrorState.gyroBiasN + 1],
            dx[ErrorState.gyroBiasN + 2],
          ),
      timestampUs: current.timestampUs,
    );
    if (!next.isFinite) {
      _fail('state went non-finite after a correction');
      return;
    }
    _state = next;
  }

  /// Trace of the horizontal position covariance block (m²).
  double _horizontalPositionTrace() =>
      _p.at(ErrorState.positionN, ErrorState.positionN) +
      _p.at(ErrorState.positionN + 1, ErrorState.positionN + 1);

  /// Keeps the covariance numerically sound and stops the bias states from
  /// claiming more knowledge than is physically available (§28, §62).
  void _applyCovarianceFloors() {
    _p.floorDiagonal(_ekf.covarianceFloor);
    final accelFloor = _ekf.minAccelBiasSigma * _ekf.minAccelBiasSigma;
    final gyroFloor = _ekf.minGyroBiasSigma * _ekf.minGyroBiasSigma;
    for (var i = 0; i < 3; i++) {
      final a = ErrorState.accelBiasN + i;
      if (_p.at(a, a) < accelFloor) _p.set(a, a, accelFloor);
      final g = ErrorState.gyroBiasN + i;
      if (_p.at(g, g) < gyroFloor) _p.set(g, g, gyroFloor);
    }
  }

  /// Widens the covariance of every state this measurement observes, so a
  /// filter that has become overconfident can be corrected again.
  void _inflateObservedStates(Matrix h) {
    const factor = 4.0;
    for (var j = 0; j < ErrorState.size; j++) {
      var observed = false;
      for (var i = 0; i < h.rows; i++) {
        if (h.at(i, j).abs() > 1e-12) {
          observed = true;
          break;
        }
      }
      if (observed) _p.set(j, j, _p.at(j, j) * factor);
    }
    _p = _p.symmetrized();
  }

  /// Consecutive rejections of [name], for diagnostics (§64).
  int rejectStreakFor(String name) => _rejectStreak[name] ?? 0;

  MeasurementResult _skip(String name) =>
      MeasurementResult(name: name, outcome: MeasurementOutcome.skipped);

  void _fail(String reason) {
    _failed = true;
    _failureReason = reason;
    debugPrint('[NavigationFilter] FAILED: $reason');
  }

  static bool _finiteVector(Vector3 v) =>
      v.x.isFinite && v.y.isFinite && v.z.isFinite;

  static double _sq(double v) => v * v;
}
