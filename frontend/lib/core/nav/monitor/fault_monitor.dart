import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../gnss/gnss_quality.dart';
import '../ins/ins_state.dart';
import '../math/nav_math.dart';
import '../nav_config.dart';

/// One thing `FaultMonitor` noticed that nothing else in the engine flags.
///
/// A read-only observation, never a correction: [mechanism] is honest about
/// that — every mechanism here ends the same way, "no correction applied".
@immutable
class FaultFlag {
  const FaultFlag({
    required this.label,
    required this.mechanism,
    required this.monotonicUs,
  });

  /// Driver-facing text, e.g. "Gyro bias suspected (+0.52 deg/s vs GNSS
  /// course)".
  final String label;

  /// Short tag the Fault Injection Lab matches against, e.g. "Gyro bias
  /// suspected".
  final String mechanism;

  /// When this flag first raised.
  final int monotonicUs;
}

/// Read-only fault detectors fed from data the engine already computes each
/// step: raw gyro/accel samples, the filter's own predicted state (before a
/// GNSS correction) and the filter's own gyro-bias estimate.
///
/// Every detector here only *observes* — nothing it computes is fed back into
/// the filter, so replay stays bit-exact with or without it running. It
/// exists because five of the nine Fault Injection Lab presets (gyro bias,
/// accelerometer bias, a slow GNSS integrity ramp, and GNSS timestamp delay)
/// pass every existing gate: the jump/heading/accuracy checks in
/// `GnssQualityEngine` compare a fix only against the *previous fix*, never
/// against the filter's own prediction, so a slow drift or a small constant
/// bias sails through unnoticed until now.
class FaultMonitor {
  FaultMonitor({NavConfig config = NavConfig.defaults})
      : _config = config.faultMonitor;

  final FaultMonitorConfig _config;

  // Gyro integration accumulated since the last accepted GNSS fix.
  double _yawIntegralRad = 0;
  int? _lastImuUs;

  GnssObservation? _lastFix;
  Vector3? _lastFilterGyroBias;
  double? _accelBiasBaselineX;

  final Queue<double> _gyroResiduals = Queue<double>();
  final Queue<double> _accelResiduals = Queue<double>();
  final Queue<double> _delaySamples = Queue<double>();
  double _cusum = 0;

  FaultFlag? _gyroFlag;
  FaultFlag? _accelFlag;
  FaultFlag? _integrityFlag;
  FaultFlag? _delayFlag;
  FaultFlag? _filterBiasJumpFlag;

  /// Every flag currently raised, in the order the detectors run. Latched:
  /// once raised, a flag stays until [reset] — matching how the lab reads
  /// "first sign of it" rather than a flickering per-sample verdict.
  List<FaultFlag> get flags => [
        if (_gyroFlag != null) _gyroFlag!,
        if (_accelFlag != null) _accelFlag!,
        if (_integrityFlag != null) _integrityFlag!,
        if (_delayFlag != null) _delayFlag!,
        if (_filterBiasJumpFlag != null) _filterBiasJumpFlag!,
      ];

  void reset() {
    _yawIntegralRad = 0;
    _lastImuUs = null;
    _lastFix = null;
    _lastFilterGyroBias = null;
    _accelBiasBaselineX = null;
    _gyroResiduals.clear();
    _accelResiduals.clear();
    _delaySamples.clear();
    _cusum = 0;
    _gyroFlag = null;
    _accelFlag = null;
    _integrityFlag = null;
    _delayFlag = null;
    _filterBiasJumpFlag = null;
  }

  /// One vehicle-frame IMU sample. [yawRateVehicleRadPerS] is the gyro's own
  /// z (down) axis rate — the same value the filter propagates attitude
  /// with.
  void onImuStep({
    required int monotonicUs,
    required double yawRateVehicleRadPerS,
  }) {
    final last = _lastImuUs;
    _lastImuUs = monotonicUs;
    if (last == null) return;
    final dt = (monotonicUs - last) / 1e6;
    if (dt <= 0 || dt > 0.5) return;
    _yawIntegralRad += yawRateVehicleRadPerS * dt;
  }

  /// One GNSS fix, exactly as the engine saw it — accepted or not, mirroring
  /// `GnssQualityEngine.assess`. [predictedState] and
  /// [predictedHorizontalSigmaM] are the filter's state *before* this fix
  /// corrects it; [filterGyroBiasRadPerS] is the EKF's own bias estimate,
  /// read only.
  void onGnssStep({
    required GnssObservation fix,
    required GnssAssessment assessment,
    InsState? predictedState,
    double? predictedHorizontalSigmaM,
    Vector3? filterGyroBiasRadPerS,
  }) {
    _checkFilterGyroBiasJump(fix.monotonicUs, filterGyroBiasRadPerS);

    if (assessment.usable && predictedState != null) {
      _checkIntegrityAnomaly(
        fix,
        assessment,
        predictedState,
        predictedHorizontalSigmaM,
      );
      _checkTimestampDelay(fix, predictedState, predictedHorizontalSigmaM);
    }

    if (assessment.usable && predictedState != null) {
      // The gyro-bias residual is meaningless before the filter has a
      // vehicle frame and a real course to compare against - a raw
      // open-loop integration is otherwise indistinguishable from the mount
      // alignment still converging.
      _checkGyroBias(fix);
      _checkAccelBias(fix.monotonicUs, predictedState.accelBias);
      // The gyro integrator spans "since the last *accepted* fix", so a
      // rejected fix in between (e.g. under a GNSS outage or jump fault)
      // must not zero it early - only reset once it has actually been
      // compared against a fresh interval.
      _lastFix = fix;
      _yawIntegralRad = 0;
    }
  }

  // ------------------------------------------------------------- detectors

  void _checkFilterGyroBiasJump(int monotonicUs, Vector3? bias) {
    if (bias == null) return;
    final prev = _lastFilterGyroBias;
    _lastFilterGyroBias = bias;
    if (prev == null || _filterBiasJumpFlag != null) return;
    final jumpRadPerS = (bias - prev).length;
    if (jumpRadPerS > _config.filterGyroBiasJumpRadPerS) {
      _filterBiasJumpFlag = FaultFlag(
        label: 'EKF gyro-bias estimate jumped '
            '${(jumpRadPerS * NavMath.radToDeg).toStringAsFixed(2)} deg/s',
        mechanism: 'EKF gyro-bias estimate jump',
        monotonicUs: monotonicUs,
      );
    }
  }

  /// GNSS integrity anomaly via innovation CUSUM: none of `GnssQualityEngine`
  /// gates compare a fix against the filter's own predicted position, so a
  /// slow ramp under the jump/accel thresholds sails through them all.
  void _checkIntegrityAnomaly(
    GnssObservation fix,
    GnssAssessment assessment,
    InsState predictedState,
    double? predictedHorizontalSigmaM,
  ) {
    if (_integrityFlag != null) return;
    final innovationM = NavMath.horizontalDistance(
      lat0: predictedState.latitudeDeg,
      lon0: predictedState.longitudeDeg,
      lat1: fix.latitudeDeg,
      lon1: fix.longitudeDeg,
    );
    final sigma = math.sqrt(
      _sq(assessment.horizontalSigmaM) + _sq(predictedHorizontalSigmaM ?? 0),
    );
    if (sigma <= 0 || !sigma.isFinite) return;
    final z = innovationM / sigma;
    _cusum = math.max(0, _cusum + z - _config.integrityCusumSlack);
    if (_cusum > _config.integrityCusumThreshold) {
      _integrityFlag = FaultFlag(
        label: 'GNSS integrity anomaly detected (innovation drift vs the '
            "filter's own prediction)",
        mechanism: 'GNSS integrity anomaly detected',
        monotonicUs: fix.monotonicUs,
      );
    }
  }

  /// Timestamp-delay detector: if a fix's timestamp is later than the
  /// position it actually measured, the filter's prediction at that
  /// timestamp runs ahead of the fix along the direction of travel while
  /// staying close to it cross-track — the specific signature a plain along-
  /// track/cross-track split can tell apart from a bias (which pulls off to
  /// one side regardless of heading).
  void _checkTimestampDelay(
    GnssObservation fix,
    InsState predictedState,
    double? predictedHorizontalSigmaM,
  ) {
    if (_delayFlag != null) return;
    final speed = predictedState.groundSpeed;
    if (speed < _config.timestampDelayMinSpeedMps) return;
    final ned = NavMath.nedBetween(
      lat0: fix.latitudeDeg,
      lon0: fix.longitudeDeg,
      alt0: 0,
      lat1: predictedState.latitudeDeg,
      lon1: predictedState.longitudeDeg,
      alt1: 0,
    );
    final headingRad = predictedState.headingDeg * NavMath.degToRad;
    final along = ned.x * math.cos(headingRad) + ned.y * math.sin(headingRad);
    final cross = -ned.x * math.sin(headingRad) + ned.y * math.cos(headingRad);
    if (along <= 0) return; // a delay only ever puts the fix *behind*.
    if (cross.abs() > along.abs() * _config.timestampDelayMaxCrossTrackFraction) {
      return; // sideways offset: a bias, not a timing shift.
    }
    // The along-track offset must clear ordinary filter uncertainty by a
    // comfortable margin, or a long clean drive's own accumulated position
    // sigma reads as a "delay" once in a while (measured: a fixed 300 ms
    // threshold alone false-alarms after ~170s of undisturbed driving).
    final sigma = predictedHorizontalSigmaM;
    if (sigma == null ||
        sigma <= 0 ||
        along < sigma * _config.timestampDelayMinSigmaMultiple) {
      return;
    }
    final impliedDelayS = along / speed;
    _delaySamples.addLast(impliedDelayS);
    while (_delaySamples.length > _config.timestampDelayWindow) {
      _delaySamples.removeFirst();
    }
    if (_delaySamples.length < _config.timestampDelayWindow) return;
    final agreeing =
        _delaySamples.where((d) => d > _config.timestampDelayThresholdS * 0.5).length;
    if (agreeing / _delaySamples.length < _config.timestampDelayMinFraction) {
      return;
    }
    final mean =
        _delaySamples.reduce((a, b) => a + b) / _delaySamples.length;
    if (mean > _config.timestampDelayThresholdS) {
      _delayFlag = FaultFlag(
        label: 'GNSS timestamp latency suspected '
            '(~${(mean * 1000).round()} ms)',
        mechanism: 'GNSS timestamp latency suspected',
        monotonicUs: fix.monotonicUs,
      );
    }
  }

  void _checkGyroBias(GnssObservation fix) {
    final last = _lastFix;
    if (last == null || _gyroFlag != null) return;
    final dt = (fix.monotonicUs - last.monotonicUs) / 1e6;
    if (dt <= 0) return;

    final bearing = fix.bearingDeg;
    final prevBearing = last.bearingDeg;
    final speed = fix.speedMps;
    final prevSpeed = last.speedMps;
    if (bearing == null ||
        prevBearing == null ||
        (speed ?? 0) <= _config.courseMinSpeedMps ||
        (prevSpeed ?? 0) <= _config.courseMinSpeedMps) {
      return;
    }
    final courseRateDegPerS = NavMath.angleDiffDeg(bearing, prevBearing) / dt;
    final gyroRateDegPerS = (_yawIntegralRad * NavMath.radToDeg) / dt;
    _pushGyroResidual(gyroRateDegPerS - courseRateDegPerS, fix.monotonicUs);
  }

  /// Accelerometer-bias detector: reads the EKF's own accel-bias state
  /// estimate (`InsState.accelBias`, already computed for the filter, never
  /// written to here) rather than re-deriving it by double-integrating raw
  /// accelerometer samples - a from-scratch open-loop integration turned out
  /// to be far noisier than the filter's own Kalman-smoothed estimate,
  /// particularly through the reference drive's turns.
  ///
  /// Compared against a *baseline* captured the first time this runs, not an
  /// absolute value: the estimate is not zero-centred even on a clean drive
  /// (measured: -0.06 to -0.08 m/s² while cruising, matching the documented
  /// limit that accel bias is entangled with tilt and only weakly observable
  /// - see the root CLAUDE.md "Measured limits" note). Watching the *change*
  /// from wherever it started is what makes an injected bias visible without
  /// that steady-state offset alone reading as a fault.
  void _checkAccelBias(int monotonicUs, Vector3 accelBias) {
    if (_accelFlag != null) return;
    // Forward-axis (vehicle x) component: the bias direction a real
    // accelerometer bias fault injects.
    final baseline = _accelBiasBaselineX ??= accelBias.x;
    _pushAccelResidual(accelBias.x - baseline, monotonicUs);
  }

  void _pushGyroResidual(double residualDegPerS, int monotonicUs) {
    _gyroResiduals.addLast(residualDegPerS);
    while (_gyroResiduals.length > _config.gyroResidualWindow) {
      _gyroResiduals.removeFirst();
    }
    if (_gyroResiduals.length < _config.gyroResidualWindow) return;
    final mean =
        _gyroResiduals.reduce((a, b) => a + b) / _gyroResiduals.length;
    if (mean.abs() < _config.gyroResidualThresholdDegPerS) return;
    final agreeing =
        _gyroResiduals.where((r) => r.sign == mean.sign).length;
    if (agreeing / _gyroResiduals.length < _config.gyroResidualMinFraction) {
      return;
    }
    _gyroFlag = FaultFlag(
      label: 'Gyro bias suspected (${mean >= 0 ? '+' : ''}'
          '${mean.toStringAsFixed(2)} deg/s vs GNSS course)',
      mechanism: 'Gyro bias suspected',
      monotonicUs: monotonicUs,
    );
  }

  void _pushAccelResidual(double residualMps, int monotonicUs) {
    _accelResiduals.addLast(residualMps);
    while (_accelResiduals.length > _config.accelResidualWindow) {
      _accelResiduals.removeFirst();
    }
    if (_accelResiduals.length < _config.accelResidualWindow) return;
    final mean =
        _accelResiduals.reduce((a, b) => a + b) / _accelResiduals.length;
    if (mean.abs() < _config.accelResidualThresholdMps) return;
    final agreeing =
        _accelResiduals.where((r) => r.sign == mean.sign).length;
    if (agreeing / _accelResiduals.length < _config.accelResidualMinFraction) {
      return;
    }
    _accelFlag = FaultFlag(
      label: 'Accelerometer bias suspected (EKF forward-axis bias estimate '
          '${mean >= 0 ? '+' : ''}${mean.toStringAsFixed(2)} m/s²)',
      mechanism: 'Accelerometer bias suspected',
      monotonicUs: monotonicUs,
    );
  }

  static double _sq(double v) => v * v;
}
