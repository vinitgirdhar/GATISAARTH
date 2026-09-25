import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';
import '../nav_config.dart';

/// What the vehicle is doing right now (§7).
///
/// Used to adapt the filter: which pseudo-measurements apply, how much to
/// trust the accelerometer, whether the neural velocity model is in
/// distribution.
enum VehicleState {
  /// Not enough history yet to say anything.
  unknown,
  stationary,
  accelerating,
  cruising,
  braking,
  turning,
  sharpTurning,
  roughRoad,
  stopAndGo,

  /// Two-wheeler leaning into a corner — the lateral constraint must relax.
  leaning,

  /// Readings are not physically plausible; treat the IMU as suspect.
  sensorAnomaly,
}

extension VehicleStateLabel on VehicleState {
  String get label {
    switch (this) {
      case VehicleState.unknown:
        return 'Unknown';
      case VehicleState.stationary:
        return 'Stationary';
      case VehicleState.accelerating:
        return 'Accelerating';
      case VehicleState.cruising:
        return 'Cruising';
      case VehicleState.braking:
        return 'Braking';
      case VehicleState.turning:
        return 'Turning';
      case VehicleState.sharpTurning:
        return 'Sharp turn';
      case VehicleState.roughRoad:
        return 'Rough road';
      case VehicleState.stopAndGo:
        return 'Stop and go';
      case VehicleState.leaning:
        return 'Leaning';
      case VehicleState.sensorAnomaly:
        return 'Sensor anomaly';
    }
  }
}

/// Vehicle class the phone is riding in. Mirrors the app's existing
/// `VehicleProfile` but lives in the core so the core stays UI-free.
enum VehicleClass { car, twoWheeler, pedestrian }

@immutable
class MotionSnapshot {
  const MotionSnapshot({
    required this.state,
    required this.isStationary,
    required this.stopDuration,
    required this.accelStd,
    required this.gyroStd,
    required this.vibrationRms,
    required this.yawRate,
    required this.longitudinalAccel,
    required this.lateralAccel,
    required this.nhcApplicable,
    required this.confidence,
    this.leanAngleRad,
    this.stopStartedAtUs,
  });

  static const MotionSnapshot initial = MotionSnapshot(
    state: VehicleState.unknown,
    isStationary: false,
    stopDuration: Duration.zero,
    accelStd: 0,
    gyroStd: 0,
    vibrationRms: 0,
    yawRate: 0,
    longitudinalAccel: 0,
    lateralAccel: 0,
    nhcApplicable: false,
    confidence: 0,
  );

  final VehicleState state;

  /// True only after the stationary condition has held past the enter delay
  /// (§16 hysteresis). This is what gates the zero-velocity update.
  final bool isStationary;

  final Duration stopDuration;
  final int? stopStartedAtUs;

  /// Standard deviation of |accel| over the window (m/s²).
  final double accelStd;

  /// Standard deviation of |gyro| over the window (rad/s).
  final double gyroStd;

  /// RMS of the gravity-removed acceleration magnitude — the road-roughness
  /// signal the existing app already shows.
  final double vibrationRms;

  final double yawRate; // rad/s, body z
  final double longitudinalAccel; // m/s², body x
  final double lateralAccel; // m/s², body y

  /// Whether the non-holonomic constraint should be applied this instant
  /// (§17). False while turning hard or leaning, where it is least valid.
  final bool nhcApplicable;

  /// 0..1 — how much history backs this classification. Low right after a
  /// reset, so the UI can say "measuring" instead of asserting a state.
  final double confidence;

  /// Estimated lean angle (rad) for a two-wheeler, null for a car or when it
  /// cannot be estimated.
  final double? leanAngleRad;

  double get leanAngleDeg =>
      leanAngleRad == null ? 0 : leanAngleRad! * NavMath.radToDeg;
}

/// Classifies vehicle motion and decides when the zero-velocity and
/// non-holonomic constraints apply (§7, §16, §17).
///
/// The existing app's stationary rule looked at accelerometer variance alone,
/// which mistakes a smooth cruise for a stop — it worked around that by
/// refusing to zero a fast speed for 3 s. This replaces the workaround: the
/// gate needs accelerometer *and* gyroscope stillness, plus agreement from
/// GNSS speed when there is one, and it has explicit enter/exit hysteresis so
/// the answer cannot chatter.
class MotionClassifier {
  MotionClassifier({
    NavConfig config = NavConfig.defaults,
    this.vehicleClass = VehicleClass.car,
  })  : _config = config.motion,
        _ekf = config.ekf;

  final MotionConfig _config;
  final EkfConfig _ekf;
  VehicleClass vehicleClass;

  static const Duration _window = Duration(seconds: 1);

  final Queue<_Sample> _samples = Queue<_Sample>();

  bool _stationary = false;
  int? _stopStartedAtUs;
  int _stopCount = 0;
  int? _lastStopEndedUs;
  MotionSnapshot _snapshot = MotionSnapshot.initial;

  MotionSnapshot get snapshot => _snapshot;

  /// Lateral-velocity sigma the filter should use for the non-holonomic
  /// update right now (§17). A leaning two-wheeler genuinely has lateral
  /// motion in its body frame, so clamping it like a car would inject error.
  double get nhcLateralSigma => nhcLateralSigmaFor();

  /// [nhcLateralSigma], optionally widened for a two-wheeler rolling at
  /// [rollRateRad] (body x rate): the phone then swings sideways at
  /// mount height × roll rate while the tyres themselves do not slip.
  double nhcLateralSigmaFor({double rollRateRad = 0}) {
    if (vehicleClass == VehicleClass.car) return _ekf.nhcSigmaCar;
    if (vehicleClass == VehicleClass.pedestrian) return double.infinity;
    final lean = _snapshot.leanAngleRad?.abs() ?? 0;
    // Widen with lean: upright bike is nearly car-like, a 30 deg lean is not.
    final base =
        _ekf.nhcSigmaTwoWheeler * (1 + _ekf.nhcLeanGain * math.sin(lean));
    final swing = _ekf.twoWheelerMountHeightM * rollRateRad.abs();
    return math.sqrt(base * base + swing * swing);
  }

  void reset() {
    _samples.clear();
    _stationary = false;
    _quietSinceUs = null;
    _movingSinceUs = null;
    _stopStartedAtUs = null;
    _lastStopEndedUs = null;
    _stopCount = 0;
    _snapshot = MotionSnapshot.initial;
  }

  /// Feeds one calibrated, vehicle-frame IMU sample.
  ///
  /// [gnssSpeedMps] is the fix speed when GNSS is live and trustworthy, else
  /// null — never a guess. [filterSpeedMps] is the filter's current speed,
  /// used only as a prior against the smooth-cruise false stop. [rollRad] is
  /// the filter's roll estimate, used for the two-wheeler lean.
  ///
  /// [shockHold] says a shock (pothole, bump, a knock on the phone) is being
  /// held: the one-second variance of |a| and |gyro| is then the shock's, not
  /// the vehicle's, so it is left out of the stillness test and a vehicle that
  /// was already stopped stays stopped through it (a shock never starts a
  /// stop). The sustained horizontal force that a real pull-away produces is
  /// still tested, so a vehicle that genuinely sets off is still released
  /// quickly.
  MotionSnapshot addSample({
    required Vector3 accelBody,
    required Vector3 gyroBody,
    required int monotonicUs,
    double? gnssSpeedMps,
    double? filterSpeedMps,
    double? rollRad,
    bool shockHold = false,
  }) {
    if (!_finite(accelBody) || !_finite(gyroBody)) {
      _snapshot = MotionSnapshot(
        state: VehicleState.sensorAnomaly,
        isStationary: false,
        stopDuration: Duration.zero,
        accelStd: _snapshot.accelStd,
        gyroStd: _snapshot.gyroStd,
        vibrationRms: _snapshot.vibrationRms,
        yawRate: 0,
        longitudinalAccel: 0,
        lateralAccel: 0,
        nhcApplicable: false,
        confidence: 0,
      );
      return _snapshot;
    }

    _samples.addLast(_Sample(
      monotonicUs: monotonicUs,
      accelMagnitude: accelBody.length,
      longitudinal: accelBody.x,
      lateral: accelBody.y,
      gyroMagnitude: gyroBody.length,
      yawRate: gyroBody.z,
    ));
    while (_samples.length > 1 &&
        monotonicUs - _samples.first.monotonicUs > _window.inMicroseconds) {
      _samples.removeFirst();
    }

    final stats = _Stats.of(_samples);
    final stationary = _updateStationary(
      stats: stats,
      monotonicUs: monotonicUs,
      gnssSpeedMps: gnssSpeedMps,
      filterSpeedMps: filterSpeedMps,
      shockHold: shockHold,
    );

    final lean = vehicleClass == VehicleClass.twoWheeler
        ? _estimateLean(rollRad: rollRad, lateralAccel: stats.meanLateral)
        : null;

    final state = _classify(stats, stationary, lean);
    final nhcApplicable = vehicleClass != VehicleClass.pedestrian &&
        !stationary &&
        state != VehicleState.sensorAnomaly &&
        stats.absYawRate < _config.nhcMaxYawRate;

    // Confidence ramps with window fill; a snapshot from three samples should
    // not be presented with the same weight as one from a full second.
    final span = _samples.length < 2
        ? 0.0
        : (_samples.last.monotonicUs - _samples.first.monotonicUs) /
            _window.inMicroseconds;

    _snapshot = MotionSnapshot(
      state: state,
      isStationary: stationary,
      stopDuration: _stopStartedAtUs == null
          ? Duration.zero
          : Duration(microseconds: monotonicUs - _stopStartedAtUs!),
      stopStartedAtUs: _stopStartedAtUs,
      accelStd: stats.accelStd,
      gyroStd: stats.gyroStd,
      vibrationRms: stats.vibrationRms,
      yawRate: stats.meanYawRate,
      longitudinalAccel: stats.meanLongitudinal,
      lateralAccel: stats.meanLateral,
      nhcApplicable: nhcApplicable,
      confidence: span.clamp(0.0, 1.0),
      leanAngleRad: lean,
    );
    return _snapshot;
  }

  bool _updateStationary({
    required _Stats stats,
    required int monotonicUs,
    double? gnssSpeedMps,
    double? filterSpeedMps,
    bool shockHold = false,
  }) {
    // GNSS, when it is live, is the strongest evidence either way — it is the
    // one signal that sees actual ground motion. When it is present it
    // decides on its own: deferring to the filter's own speed here would let
    // a diverged filter veto the very stop that would have corrected it.
    final bool motionVeto;
    if (gnssSpeedMps != null) {
      motionVeto = gnssSpeedMps > _config.zuptMaxGnssSpeed;
    } else {
      // No GNSS. The classic ZUPT ambiguity bites: a smooth cruise on good
      // tarmac looks exactly like a stop to an IMU, and there is no purely
      // inertial way out of it. The filter's own speed stands in as a prior —
      // it was established while there WAS independent evidence. A guard, not
      // a solution; the real discriminators are the velocity model (§8) and
      // map matching (§19).
      motionVeto = filterSpeedMps != null &&
          filterSpeedMps > _config.zuptMaxFilterSpeed;
    }

    // Horizontal specific force catches steady acceleration, which the
    // variance test is blind to; the variance test catches vibration, which
    // this one is blind to. Both are needed.
    //
    // It is read over the last few samples rather than the whole window: a
    // one-second mean takes half a second to notice a pull-away, and every
    // one of those samples tells the filter it is not moving while it plainly
    // is. Slow to declare a stop, quick to abandon one.
    // A held shock can keep a stop, never start one: entering stillness on the
    // strength of ignoring the variance would let a bump at a crawl read as a
    // stop.
    final varianceQuiet = (shockHold && _stationary) ||
        (stats.accelStd < _config.zuptAccelStd &&
            stats.gyroStd < _config.zuptGyroStd);
    final quiet = varianceQuiet &&
        stats.recentHorizontal < _config.zuptMaxHorizontalAccel &&
        !motionVeto;

    if (quiet) {
      _movingSinceUs = null;
      _quietSinceUs ??= monotonicUs;
      if (!_stationary &&
          monotonicUs - _quietSinceUs! >=
              _config.zuptEnterDelay.inMicroseconds) {
        _stationary = true;
        _stopStartedAtUs = _quietSinceUs;
        _stopCount++;
      }
    } else {
      _quietSinceUs = null;
      _movingSinceUs ??= monotonicUs;
      if (_stationary &&
          monotonicUs - _movingSinceUs! >=
              _config.zuptExitDelay.inMicroseconds) {
        _stationary = false;
        _stopStartedAtUs = null;
        _lastStopEndedUs = monotonicUs;
      }
    }
    return _stationary;
  }

  int? _quietSinceUs;
  int? _movingSinceUs;

  /// Lean angle of a two-wheeler.
  ///
  /// Prefers the filter's roll estimate; falls back to the lateral specific
  /// force, which for a coordinated turn equals `g * tan(lean)`. Returns null
  /// when neither is available rather than assuming upright.
  double? _estimateLean({double? rollRad, required double lateralAccel}) {
    if (rollRad != null && rollRad.isFinite) return rollRad;
    if (!lateralAccel.isFinite) return null;
    if (lateralAccel.abs() < _config.leanRateThreshold) return 0;
    return math.atan(lateralAccel / NavMath.gravity);
  }

  VehicleState _classify(_Stats stats, bool stationary, double? lean) {
    if (stats.count < 3) return VehicleState.unknown;
    if (stats.accelMax > 50 || stats.gyroMax > 15) {
      return VehicleState.sensorAnomaly;
    }
    if (stationary) {
      // Several stops in quick succession is traffic, not a parked vehicle.
      final recentlyStopped = _lastStopEndedUs != null &&
          stats.lastUs - _lastStopEndedUs! < 30 * 1000000;
      return _stopCount > 2 && recentlyStopped
          ? VehicleState.stopAndGo
          : VehicleState.stationary;
    }
    if (lean != null && lean.abs() > 12 * NavMath.degToRad) {
      return VehicleState.leaning;
    }
    if (stats.absYawRate > _config.sharpTurnYawRate) {
      return VehicleState.sharpTurning;
    }
    if (stats.vibrationRms > _config.severeRms) return VehicleState.roughRoad;
    if (stats.absYawRate > _config.turningYawRate) return VehicleState.turning;
    if (stats.meanLongitudinal < _config.hardBrakingAccel) {
      return VehicleState.braking;
    }
    if (stats.meanLongitudinal > 0.8) return VehicleState.accelerating;
    if (stats.meanLongitudinal < -0.8) return VehicleState.braking;
    if (stats.vibrationRms > _config.roughRms) return VehicleState.roughRoad;
    return VehicleState.cruising;
  }

  static bool _finite(Vector3 v) =>
      v.x.isFinite && v.y.isFinite && v.z.isFinite;
}

class _Sample {
  const _Sample({
    required this.monotonicUs,
    required this.accelMagnitude,
    required this.longitudinal,
    required this.lateral,
    required this.gyroMagnitude,
    required this.yawRate,
  });

  final int monotonicUs;
  final double accelMagnitude;
  final double longitudinal;
  final double lateral;
  final double gyroMagnitude;
  final double yawRate;
}

class _Stats {
  const _Stats({
    required this.count,
    required this.lastUs,
    required this.recentHorizontal,
    required this.accelStd,
    required this.gyroStd,
    required this.vibrationRms,
    required this.meanYawRate,
    required this.absYawRate,
    required this.meanLongitudinal,
    required this.meanLateral,
    required this.accelMax,
    required this.gyroMax,
  });

  factory _Stats.of(Iterable<_Sample> samples) {
    final list = samples.toList(growable: false);
    if (list.isEmpty) {
      return const _Stats(
        count: 0,
        lastUs: 0,
        recentHorizontal: 0,
        accelStd: 0,
        gyroStd: 0,
        vibrationRms: 0,
        meanYawRate: 0,
        absYawRate: 0,
        meanLongitudinal: 0,
        meanLateral: 0,
        accelMax: 0,
        gyroMax: 0,
      );
    }
    var sumA = 0.0, sumG = 0.0, sumYaw = 0.0, sumLong = 0.0, sumLat = 0.0;
    var maxA = 0.0, maxG = 0.0;
    for (final s in list) {
      sumA += s.accelMagnitude;
      sumG += s.gyroMagnitude;
      sumYaw += s.yawRate;
      sumLong += s.longitudinal;
      sumLat += s.lateral;
      if (s.accelMagnitude > maxA) maxA = s.accelMagnitude;
      if (s.gyroMagnitude > maxG) maxG = s.gyroMagnitude;
    }
    final n = list.length;
    final meanA = sumA / n;
    final meanG = sumG / n;
    var varA = 0.0, varG = 0.0, sumSqDev = 0.0;
    for (final s in list) {
      final da = s.accelMagnitude - meanA;
      final dg = s.gyroMagnitude - meanG;
      varA += da * da;
      varG += dg * dg;
      // Road roughness: deviation of |a| from gravity, independent of the
      // vehicle's own acceleration mean.
      final net = s.accelMagnitude - NavMath.gravity;
      sumSqDev += net * net;
    }
    // Horizontal specific force over the newest handful of samples.
    const recentCount = 5;
    final recent = list.length <= recentCount
        ? list
        : list.sublist(list.length - recentCount);
    var recentLong = 0.0, recentLat = 0.0;
    for (final s in recent) {
      recentLong += s.longitudinal;
      recentLat += s.lateral;
    }
    recentLong /= recent.length;
    recentLat /= recent.length;

    return _Stats(
      count: n,
      lastUs: list.last.monotonicUs,
      recentHorizontal:
          math.sqrt(recentLong * recentLong + recentLat * recentLat),
      accelStd: math.sqrt(varA / n),
      gyroStd: math.sqrt(varG / n),
      vibrationRms: math.sqrt(sumSqDev / n),
      meanYawRate: sumYaw / n,
      absYawRate: (sumYaw / n).abs(),
      meanLongitudinal: sumLong / n,
      meanLateral: sumLat / n,
      accelMax: maxA,
      gyroMax: maxG,
    );
  }

  final int count;
  final int lastUs;

  /// Horizontal specific force over the newest few samples (m/s²).
  final double recentHorizontal;
  final double accelStd;
  final double gyroStd;
  final double vibrationRms;
  final double meanYawRate;
  final double absYawRate;
  final double meanLongitudinal;
  final double meanLateral;
  final double accelMax;
  final double gyroMax;
}
