import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';
import '../nav_config.dart';

/// One coordinated-turn speed reading.
@immutable
class TurnSpeedObservation {
  const TurnSpeedObservation({
    required this.speedMps,
    required this.sigmaMps,
    required this.lateralAccel,
    required this.yawRate,
    required this.monotonicUs,
  });

  final double speedMps;
  final double sigmaMps;

  /// Window means, level frame (right-positive lateral, down-positive yaw).
  final double lateralAccel;
  final double yawRate;
  final int monotonicUs;
}

/// What the turn speedometer has done, for diagnostics and tests.
@immutable
class TurnSpeedDiagnostics {
  const TurnSpeedDiagnostics({
    required this.observed,
    required this.applied,
    required this.rejected,
    required this.validationPairs,
    required this.trusted,
    this.validationBiasMps,
    this.validationRmsMps,
    this.last,
  });

  static const TurnSpeedDiagnostics none = TurnSpeedDiagnostics(
    observed: 0,
    applied: 0,
    rejected: 0,
    validationPairs: 0,
    trusted: true,
  );

  final int observed;
  final int applied;

  /// Offered to the filter and refused by its innovation gate.
  final int rejected;
  final int validationPairs;
  final bool trusted;

  /// Mean and RMS of (turn speed - GNSS speed) over the validation window.
  final double? validationBiasMps;
  final double? validationRmsMps;
  final TurnSpeedObservation? last;
}

/// Coordinated-turn speedometer: forward speed from v = a_lat / omega.
///
/// For a vehicle following its nose (no side-slip), the kinematic
/// acceleration is omega x v, whose component across the direction of travel
/// is v * omega. That holds in any right-handed frame with x forward (z x x
/// = y), so the sign of the lateral force and of the yaw rate always agree
/// in a real turn, and a disagreement flags a sensor or frame problem.
///
/// Inputs are **level-frame** quantities ([levelFrame]): lateral kinematic
/// acceleration and heading rate, taken through the filter's attitude and
/// bias estimates. A body-frame reading would read gravity leaking through
/// body roll, road bank or, worst of all, a two-wheeler's lean, which in a
/// coordinated turn hides the centripetal force from the body y axis almost
/// completely.
///
/// Pure Dart and deterministic (replay-safe).
class TurnSpeedEstimator {
  TurnSpeedEstimator({NavConfig config = NavConfig.defaults})
      : _c = config.turnSpeed;

  final TurnSpeedConfig _c;
  final Queue<_Sample> _samples = Queue<_Sample>();
  final Queue<double> _residuals = Queue<double>();
  int? _lastEmitUs;
  int _observed = 0;
  int _applied = 0;
  int _rejected = 0;
  TurnSpeedObservation? _last;

  /// Lateral kinematic acceleration (right of the heading, m/s²) and heading
  /// rate (rad/s, positive turning right) in the local-level frame.
  ///
  /// [specificForceBody] and [angularRateBody] must already be bias-corrected
  /// (the filter's estimates). NED navigation frame, gravity down.
  static ({double lateralAccel, double yawRate}) levelFrame({
    required Quaternion qBodyToNav,
    required Vector3 specificForceBody,
    required Vector3 angularRateBody,
  }) {
    final aNav = NavMath.rotateBodyToNav(qBodyToNav, specificForceBody) +
        Vector3(0, 0, NavMath.gravity);
    final heading = NavMath.headingFromQuaternion(qBodyToNav);
    final lateral = -math.sin(heading) * aNav.x + math.cos(heading) * aNav.y;
    final omegaNav = NavMath.rotateBodyToNav(qBodyToNav, angularRateBody);
    return (lateralAccel: lateral, yawRate: omegaNav.z);
  }

  void add({
    required double lateralAccel,
    required double yawRate,
    required int monotonicUs,
  }) {
    if (!lateralAccel.isFinite || !yawRate.isFinite) return;
    _samples.addLast(_Sample(monotonicUs, lateralAccel, yawRate));
    final windowUs = _c.window.inMicroseconds;
    while (_samples.length > 1 && monotonicUs - _samples.first.us > windowUs) {
      _samples.removeFirst();
    }
  }

  /// A new observation when the window holds a clear, steady turn and the
  /// update interval has passed; null otherwise.
  TurnSpeedObservation? poll(int monotonicUs) {
    final lastEmit = _lastEmitUs;
    if (lastEmit != null &&
        monotonicUs - lastEmit < _c.updateInterval.inMicroseconds) {
      return null;
    }
    if (_samples.length < 3) return null;
    final span = _samples.last.us - _samples.first.us;
    if (span < _c.window.inMicroseconds * _c.minWindowFill) return null;

    var sumA = 0.0, sumW = 0.0;
    for (final s in _samples) {
      sumA += s.lateral;
      sumW += s.yawRate;
    }
    final n = _samples.length;
    final a = sumA / n;
    final w = sumW / n;
    if (w.abs() < _c.minYawRate || w.abs() > _c.maxYawRate) return null;
    if (a.abs() < _c.minLateralAccel) return null;
    if (a.sign != w.sign) return null;

    var varW = 0.0;
    for (final s in _samples) {
      final d = s.yawRate - w;
      varW += d * d;
    }
    if (math.sqrt(varW / n) / w.abs() > _c.maxYawRateCv) return null;

    final v = a / w;
    if (v < _c.minSpeed || v > _c.maxSpeed) return null;
    final sigma = math.sqrt(math.pow(_c.accelSigma / w.abs(), 2) +
        math.pow(v * _c.yawRateSigma / w.abs(), 2));
    if (sigma > _c.maxSigma) return null;

    _lastEmitUs = monotonicUs;
    _observed++;
    return _last = TurnSpeedObservation(
      speedMps: v,
      sigmaMps: sigma,
      lateralAccel: a,
      yawRate: w,
      monotonicUs: monotonicUs,
    );
  }

  /// Compares an observation with a fresh GNSS speed. Turns are rare, so
  /// only a sustained disagreement ([TurnSpeedConfig.validationMinPairs])
  /// switches the speedometer off; a single odd turn does not.
  void grade(TurnSpeedObservation obs, {required double gnssSpeedMps}) {
    if (!gnssSpeedMps.isFinite) return;
    _residuals.addLast(obs.speedMps - gnssSpeedMps);
    while (_residuals.length > _c.validationWindow) {
      _residuals.removeFirst();
    }
  }

  /// Records what the filter did with an offered observation.
  void noteApplied({required bool accepted}) {
    if (accepted) {
      _applied++;
    } else {
      _rejected++;
    }
  }

  bool get trusted {
    if (_residuals.length < _c.validationMinPairs) return true;
    return _bias!.abs() <= _c.validationMaxBias && _rms! <= _c.validationMaxRms;
  }

  double? get _bias => _residuals.isEmpty
      ? null
      : _residuals.reduce((a, b) => a + b) / _residuals.length;

  double? get _rms => _residuals.isEmpty
      ? null
      : math.sqrt(
          _residuals.fold<double>(0, (s, r) => s + r * r) / _residuals.length);

  TurnSpeedDiagnostics get diagnostics => TurnSpeedDiagnostics(
        observed: _observed,
        applied: _applied,
        rejected: _rejected,
        validationPairs: _residuals.length,
        trusted: trusted,
        validationBiasMps: _bias,
        validationRmsMps: _rms,
        last: _last,
      );

  void reset() {
    _samples.clear();
    _residuals.clear();
    _lastEmitUs = null;
    _observed = 0;
    _applied = 0;
    _rejected = 0;
    _last = null;
  }
}

class _Sample {
  const _Sample(this.us, this.lateral, this.yawRate);

  final int us;
  final double lateral;
  final double yawRate;
}
