import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';
import '../nav_config.dart';

/// The estimated phone-to-vehicle transform and how much to believe it (§6).
@immutable
class MountAlignment {
  const MountAlignment({
    required this.rPhoneToVehicle,
    required this.forwardInPhone,
    required this.rightInPhone,
    required this.downInPhone,
    required this.yawOffsetRad,
    required this.pitchOffsetRad,
    required this.rollOffsetRad,
    required this.confidence,
    required this.samplesUsed,
    required this.r2,
    required this.excitation,
    required this.stability,
    this.notes = const [],
  });

  /// Rotation taking a phone-frame vector into the vehicle frame
  /// (x forward, y right, z down).
  final Matrix3 rPhoneToVehicle;

  /// The vehicle's axes expressed in phone coordinates.
  final Vector3 forwardInPhone;
  final Vector3 rightInPhone;
  final Vector3 downInPhone;

  /// How far the phone is rotated about its own vertical from pointing
  /// forward. This is the number the existing app has never had, and the
  /// dominant dead-reckoning error when it is wrong.
  final double yawOffsetRad;

  /// Tilt of the phone out of flat, about its own left-right axis. 0 means
  /// lying flat screen-up; -90 deg means standing upright in a windshield
  /// mount with its top upwards.
  final double pitchOffsetRad;

  /// Sideways lean of the phone, about its own top-bottom axis.
  final double rollOffsetRad;

  /// 0..1. Never exactly 1 — a short drive cannot certify a mount.
  final double confidence;

  final int samplesUsed;

  /// Coefficient of determination of the forward-axis regression.
  final double r2;

  /// Standard deviation (m/s²) of the longitudinal acceleration the fit saw.
  final double excitation;

  /// Cosine agreement between the first and second half of the fit.
  final double stability;

  final List<String> notes;

  double get yawOffsetDeg => yawOffsetRad * NavMath.radToDeg;
  double get pitchOffsetDeg => pitchOffsetRad * NavMath.radToDeg;
  double get rollOffsetDeg => rollOffsetRad * NavMath.radToDeg;

  /// Rotates a phone-frame vector into the vehicle frame.
  Vector3 toVehicle(Vector3 phone) {
    final Vector3 out = rPhoneToVehicle * phone;
    return out;
  }

  /// Rotates a vehicle-frame vector back into the phone frame.
  Vector3 toPhone(Vector3 vehicle) {
    final Vector3 out = rPhoneToVehicle.transposed() * vehicle;
    return out;
  }
}

/// Estimates the phone-to-vehicle transform from a short drive (§6).
///
/// Two cues, in the order they become available:
///
/// 1. **Gravity** gives the vehicle's *down* axis in phone coordinates as soon
///    as the phone has been still for a moment. That is pitch and roll, and it
///    is what the existing `VehicleAlignmentEngine` already does.
/// 2. **Longitudinal acceleration** gives the *forward* axis, which gravity
///    cannot. While the vehicle drives straight and changes speed, the
///    horizontal part of its linear acceleration points along the forward
///    axis, with a sign that matches the GNSS speed derivative. Regressing one
///    on the other recovers the direction *and* the sign in one step.
///
/// The estimator publishes nothing until the regression has real speed changes
/// to work with, agrees with itself across the drive, and explains most of the
/// horizontal acceleration. Below that it reports its confidence and the UI
/// says "calibrating", not "calibrated" (§6, §83).
class MountAlignmentEstimator {
  MountAlignmentEstimator({NavConfig config = NavConfig.defaults})
      : _config = config.alignment;

  final AlignmentConfig _config;

  /// Samples taken unconditionally at the start, so that pitch and roll are
  /// available before the vehicle has done anything.
  static const int _bootstrapSamples = 50;

  Vector3? _gravityPhone; // specific force at rest, so it points "up"
  Vector3? _gravityAtFitStart;
  int _gravitySamples = 0;

  // Regression accumulators: a_horizontal ~= dvdt * forward.
  Vector3 _crossSum = Vector3.zero();
  double _dvdtSquaredSum = 0;
  double _dvdtSum = 0;
  double _accelSquaredSum = 0;
  int _accepted = 0;

  // Split halves, for the self-agreement check.
  Vector3 _firstHalfCross = Vector3.zero();
  Vector3 _secondHalfCross = Vector3.zero();
  int _halfSplitAt = 0;

  double? _lastSpeed;
  int? _lastSpeedUs;
  double? _currentDvdt;
  int? _currentDvdtUs;
  int _events = 0;
  MountAlignment? _alignment;
  final List<String> _notes = [];

  /// Latest estimate, or null while nothing can honestly be published.
  MountAlignment? get alignment => _alignment;

  /// True only once the estimate is good enough to call the mount calibrated.
  bool get isConverged =>
      (_alignment?.confidence ?? 0) >= _config.convergedConfidence;

  int get acceptedSamples => _accepted;

  /// Distinct GNSS speed-change intervals the fit has used.
  int get speedChangeEvents => _events;

  /// Pitch and roll are available from gravity alone, long before yaw is.
  bool get hasLevelling => _gravitySamples > 20 && _gravityPhone != null;

  /// Gravity direction in phone coordinates ("up"), or null before it settles.
  Vector3? get upInPhone =>
      hasLevelling ? _gravityPhone!.normalized() : null;

  void reset() {
    _gravityPhone = null;
    _gravityAtFitStart = null;
    _gravitySamples = 0;
    _crossSum = Vector3.zero();
    _dvdtSquaredSum = 0;
    _dvdtSum = 0;
    _accelSquaredSum = 0;
    _accepted = 0;
    _firstHalfCross = Vector3.zero();
    _secondHalfCross = Vector3.zero();
    _halfSplitAt = 0;
    _lastSpeed = null;
    _lastSpeedUs = null;
    _currentDvdt = null;
    _currentDvdtUs = null;
    _events = 0;
    _alignment = null;
    _notes.clear();
  }

  /// Feeds one raw, calibrated sample in the **phone** frame.
  ///
  /// [gnssSpeedMps] must be a real, trusted fix speed or null. Feeding a
  /// dead-reckoned speed here would make the regression circular.
  ///
  /// With [hold] the sample is not learned from: no gravity or tilt update and
  /// no regression step. A shock (pothole, phone knocked) corrupts exactly the
  /// readings the estimate is built from, and one such sample can move a slow
  /// gravity average further than a second of quiet driving.
  MountAlignment? add({
    required Vector3 accelPhone,
    required Vector3 gyroPhone,
    required int monotonicUs,
    double? gnssSpeedMps,
    int? gnssUs,
    bool hold = false,
  }) {
    if (!_finite(accelPhone) || !_finite(gyroPhone)) return _alignment;

    _updateSpeedDerivative(gnssSpeedMps, gnssUs ?? monotonicUs);
    if (hold) return _alignment;
    final dvdt = _applicableDvdt(monotonicUs);

    // Gravity must be estimated from samples where the vehicle is NOT
    // accelerating. A longitudinal acceleration barely changes |a| (1.8 m/s^2
    // moves it by 0.17), so a magnitude test cannot catch it — but the GNSS
    // speed derivative can, and it is already computed. Letting braking leak
    // into the gravity estimate tilts the horizontal plane, and a tilted
    // plane pours gravity straight into the forward axis.
    _updateGravity(
      accelPhone,
      quiescent: dvdt == null &&
          gyroPhone.length < _config.maxYawRateWhileFitting,
    );
    final up = upInPhone;
    if (up == null) return _alignment;
    if (dvdt == null) return _alignment;

    // Only straight-line speed changes carry forward-axis information.
    if (gyroPhone.length > _config.maxYawRateWhileFitting) return _alignment;

    // Linear acceleration, gravity removed, projected onto the horizontal
    // plane the gravity vector defines.
    final linear = accelPhone - _gravityPhone!;
    final horizontal = linear - up * linear.dot(up);

    // Only use samples where the accelerometer and the GNSS derivative are
    // describing the same event — see `dvdtConsistencyMin`.
    final magnitude = horizontal.length;
    final expected = dvdt.abs();
    if (magnitude < expected * _config.dvdtConsistencyMin ||
        magnitude > expected * _config.dvdtConsistencyMax) {
      return _alignment;
    }

    _crossSum += horizontal * dvdt;
    _dvdtSquaredSum += dvdt * dvdt;
    _dvdtSum += dvdt;
    _accelSquaredSum += horizontal.length2;
    _accepted++;
    _gravityAtFitStart ??= _gravityPhone!.clone();

    // Halves are split at the point the minimum event count is reached, so
    // the comparison is between two comparably sized stretches of the drive.
    if (_events <= _config.minEvents) {
      _firstHalfCross += horizontal * dvdt;
      _halfSplitAt = _accepted;
    } else {
      _secondHalfCross += horizontal * dvdt;
    }

    _alignment = _solve();
    return _alignment;
  }

  void _updateGravity(Vector3 accelPhone, {required bool quiescent}) {
    final previous = _gravityPhone;
    if (previous == null) {
      _gravityPhone = accelPhone.clone();
      _gravitySamples = 1;
      return;
    }
    // Bootstrap: the first second is taken whatever the vehicle is doing,
    // so levelling is available promptly. After that, only quiet samples.
    if (!quiescent && _gravitySamples > _bootstrapSamples) return;
    final a = _config.gravityAlpha;
    final next = previous * a + accelPhone * (1 - a);
    _gravityPhone = next;
    _gravitySamples++;

    // A mount that has physically moved invalidates the forward axis; pitch
    // and roll follow gravity automatically, yaw does not.
    //
    // The comparison must be against where gravity sat when the fit started,
    // not against the previous filtered value: at alpha 0.995 a single sample
    // moves the estimate by half a percent, so consecutive values never differ
    // enough to trip any sane threshold. Driving accelerations wash out of the
    // slow filter; a phone that has actually been knocked over does not.
    final anchor = _gravityAtFitStart;
    if (anchor != null && anchor.length > 1e-6 && next.length > 1e-6) {
      final drift = math.acos(
        (anchor.normalized().dot(next.normalized())).clamp(-1.0, 1.0),
      );
      if (drift > _config.maxGravityDrift) {
        reset();
        _gravityPhone = accelPhone.clone();
        _gravitySamples = 1;
        _notes.add('Mount moved; alignment restarted');
      }
    }
  }

  /// Recomputes the GNSS speed derivative whenever a new fix arrives.
  ///
  /// Never extrapolated from a dead-reckoned speed: feeding the filter's own
  /// output back in would make the regression circular.
  void _updateSpeedDerivative(double? speed, int us) {
    if (speed == null || !speed.isFinite) {
      _lastSpeed = null;
      _lastSpeedUs = null;
      _currentDvdt = null;
      _currentDvdtUs = null;
      return;
    }
    final previousUs = _lastSpeedUs;
    if (previousUs != null && us == previousUs) return; // same fix

    final previous = _lastSpeed;
    _lastSpeed = speed;
    _lastSpeedUs = us;
    if (previous == null || previousUs == null) return;

    final dt = (us - previousUs) / 1e6;
    // A gap longer than a couple of fixes is not a derivative.
    if (dt <= 0 || dt > 3) {
      _currentDvdt = null;
      _currentDvdtUs = null;
      return;
    }
    final dvdt = (speed - previous) / dt;
    if (dvdt.abs() < _config.minLongitudinalAccel) {
      _currentDvdt = null;
      _currentDvdtUs = null;
      return;
    }
    _currentDvdt = dvdt;
    _currentDvdtUs = us;
    _events++;
  }

  /// The acceleration currently applicable to an IMU sample, or null once the
  /// GNSS interval it came from is too old to speak for the present.
  double? _applicableDvdt(int monotonicUs) {
    final us = _currentDvdtUs;
    final dvdt = _currentDvdt;
    if (us == null || dvdt == null) return null;
    if (monotonicUs < us) return null;
    if (monotonicUs - us > _config.dvdtHoldFor.inMicroseconds) return null;
    return dvdt;
  }

  MountAlignment? _solve() {
    if (_accepted < _config.minSamples) return _alignment;
    if (_events < _config.minEvents) return _alignment;
    if (_dvdtSquaredSum <= 0) return _alignment;

    final forwardRaw = _crossSum / _dvdtSquaredSum;
    if (forwardRaw.length < 1e-6) return _alignment;

    final up = upInPhone!;
    final down = -up;
    var forward = forwardRaw - up * forwardRaw.dot(up);
    if (forward.length < 1e-6) return _alignment;
    forward = forward.normalized();

    final Vector3 right = down.cross(forward).normalized();

    // R has the vehicle axes as its rows, so R * v_phone = v_vehicle.
    final r = Matrix3(
      forward.x, right.x, down.x, //
      forward.y, right.y, down.y, //
      forward.z, right.z, down.z,
    );

    final meanDvdt = _dvdtSum / _accepted;
    var variance = _dvdtSquaredSum / _accepted - meanDvdt * meanDvdt;
    if (variance < 0) variance = 0;
    final excitation = math.sqrt(variance);

    // R² of the one-parameter model a_horizontal = dvdt * forwardRaw.
    final explained = forwardRaw.length2 * _dvdtSquaredSum;
    final r2 = _accelSquaredSum <= 0
        ? 0.0
        : (explained / _accelSquaredSum).clamp(0.0, 1.0);

    final stability = _halfAgreement();

    final notes = <String>[..._notes];
    if (excitation < _config.minExcitation) {
      notes.add('Too little speed change to fix the forward axis yet');
    }
    if (r2 < _config.minR2) {
      notes.add('Horizontal acceleration is not mostly longitudinal yet');
    }
    if (stability < _config.minStability) {
      notes.add('Estimate still moving between halves of the drive');
    }

    final confidence = _confidence(
      r2: r2,
      excitation: excitation,
      stability: stability,
    );

    return MountAlignment(
      rPhoneToVehicle: r,
      forwardInPhone: forward,
      rightInPhone: right,
      downInPhone: down,
      yawOffsetRad: _yawOffset(forward: forward, down: down),
      // Tilt of the phone away from lying flat, screen up: how far the
      // vehicle's down axis has swung off the phone's -z. Both are 0 for a
      // phone lying flat on the dashboard, whatever its yaw.
      pitchOffsetRad: math.atan2(down.y, -down.z),
      rollOffsetRad: math.atan2(down.x, -down.z),
      confidence: confidence,
      samplesUsed: _accepted,
      r2: r2,
      excitation: excitation,
      stability: stability,
      notes: notes,
    );
  }

  /// Signed rotation about the vehicle's down axis from the phone's own +y
  /// ("portrait top") to the vehicle's forward axis.
  ///
  /// This is the number a driver understands: 0 means the phone's top points
  /// where the car is going, 90 deg means it is mounted sideways.
  double _yawOffset({required Vector3 forward, required Vector3 down}) {
    final phoneUpAxis = Vector3(0, 1, 0);
    var reference = phoneUpAxis - down * phoneUpAxis.dot(down);
    if (reference.length < 1e-6) {
      // Phone pointing straight down or up: +y has no horizontal part, so use
      // its +x axis as the reference instead.
      final phoneRight = Vector3(1, 0, 0);
      reference = phoneRight - down * phoneRight.dot(down);
      if (reference.length < 1e-6) return 0;
    }
    reference = reference.normalized();
    final cross = reference.cross(forward);
    return math.atan2(cross.dot(down), reference.dot(forward));
  }

  double _halfAgreement() {
    if (_halfSplitAt == 0 || _events <= _config.minEvents) return 0;
    final a = _firstHalfCross;
    final b = _secondHalfCross;
    if (a.length < 1e-9 || b.length < 1e-9) return 0;
    return ((a.normalized().dot(b.normalized())) + 1) / 2;
  }

  double _confidence({
    required double r2,
    required double excitation,
    required double stability,
  }) {
    // Independent evidence is counted in speed-change events, not in IMU
    // samples: 50 samples inside one braking event are one observation of
    // the vehicle changing speed, not fifty.
    final sampleTerm = math.min(
      (_events / (_config.minEvents * 2)).clamp(0.0, 1.0),
      (_accepted / (_config.minSamples * 2)).clamp(0.0, 1.0),
    );
    final excitationTerm =
        (excitation / (_config.minExcitation * 2)).clamp(0.0, 1.0);
    final r2Term = (r2 / math.max(_config.minR2 * 1.6, 1e-6)).clamp(0.0, 1.0);
    final stabilityTerm = _events <= _config.minEvents
        ? 0.0
        : ((stability - _config.minStability) /
                math.max(1 - _config.minStability, 1e-6))
            .clamp(0.0, 1.0);

    // Every term is *necessary*, so the weakest one decides: a perfect fit
    // from one braking event is not a calibrated mount. A geometric mean
    // would forgive a weak term whenever the others are strong, which is
    // exactly the wrong behaviour here.
    final weakest = math.min(
      math.min(sampleTerm, excitationTerm),
      math.min(r2Term, stabilityTerm),
    );
    // Capped below 1: a short drive cannot certify a mount, so no
    // configuration can ever make this report certainty (§83).
    return weakest.clamp(0.0, 0.98);
  }

  static bool _finite(Vector3 v) =>
      v.x.isFinite && v.y.isFinite && v.z.isFinite;
}
