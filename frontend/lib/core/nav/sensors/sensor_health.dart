import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';
import '../motion/phone_handling.dart';
import '../nav_config.dart';
import 'sensor_fault_detector.dart';
import 'sensor_sample.dart';
import 'time_sync.dart';

/// One check's outcome (§ Navigation Hardware Check).
enum HealthVerdict { pass, degraded, fail, pending }

extension HealthVerdictLabel on HealthVerdict {
  String get label {
    switch (this) {
      case HealthVerdict.pass:
        return 'PASS';
      case HealthVerdict.degraded:
        return 'DEGRADED';
      case HealthVerdict.fail:
        return 'FAIL';
      case HealthVerdict.pending:
        return '--';
    }
  }

  /// Worst-wins ordering, used to fold several checks into one verdict.
  int get _severity {
    switch (this) {
      case HealthVerdict.pending:
        return 0;
      case HealthVerdict.pass:
        return 1;
      case HealthVerdict.degraded:
        return 2;
      case HealthVerdict.fail:
        return 3;
    }
  }
}

/// One row of the hardware check.
@immutable
class HealthCheck {
  const HealthCheck({
    required this.name,
    required this.verdict,
    required this.value,
    this.reason,
  });

  final String name;
  final HealthVerdict verdict;

  /// The measured number, human readable, or "--" when there is none yet.
  final String value;

  /// Why it is not PASS, or null when it is.
  final String? reason;
}

/// The full report: every check plus the worst non-pending verdict among
/// them, so the UI has one chip to show at a glance.
@immutable
class SensorHealthReport {
  const SensorHealthReport({required this.overall, required this.checks});

  static const SensorHealthReport pending =
      SensorHealthReport(overall: HealthVerdict.pending, checks: []);

  final HealthVerdict overall;
  final List<HealthCheck> checks;
}

/// Aggregates sensor health into PASS/DEGRADED/FAIL/PENDING checks a driver
/// can read at a glance (the "Navigation Hardware Check" card).
///
/// Deliberately self-contained: it owns its own [TimeSync] (rate, jitter,
/// drops — §4), [SensorFaultDetector] (frozen/stalled/out-of-range/noise/
/// magnetic — §29) and [PhoneHandlingDetector] (orientation wobble) rather
/// than sharing the engine's, so it can be fed and tested on a synthetic
/// stream in isolation.
///
/// ponytail: this duplicates the ~20 us/sample cost `NavigationEngine`
/// already pays for the same windows (see the nav CLAUDE.md cost note); fold
/// the two together if that ever shows up in a profile.
///
/// Two checks nothing else in the core measures: gyro-bias drift between
/// stationary windows, and GNSS fix cadence — both tracked here directly.
class SensorHealthMonitor {
  SensorHealthMonitor({NavConfig config = NavConfig.defaults})
      : _config = config.sensorHealth,
        _fieldConfig = config.sensorFault,
        _timeSync = TimeSync(config: config),
        _faults = SensorFaultDetector(config: config),
        _handling = PhoneHandlingDetector(config: config);

  final SensorHealthConfig _config;
  final SensorFaultConfig _fieldConfig;
  final TimeSync _timeSync;
  final SensorFaultDetector _faults;
  final PhoneHandlingDetector _handling;

  // Stationary detection is done here from accelerometer magnitude alone
  // (orientation- and mount-independent), the same test
  // `HandHeldStopDetector` uses.
  final List<_TimedScalar> _accelWindow = [];
  bool _stationary = false;
  int? _quietSinceUs;
  int? _movingSinceUs;
  static const Duration _stopEnterDelay = Duration(milliseconds: 800);
  static const Duration _stopExitDelay = Duration(milliseconds: 250);
  static const double _stopAccelStd = 0.6;

  // Gyro-bias stability: mean gyro over consecutive stationary windows.
  Vector3 _biasWindowSum = Vector3.zero();
  int _biasWindowCount = 0;
  int? _biasWindowStartUs;
  Vector3? _lastStationaryMeanGyro;
  int? _lastStationaryMeanUs;
  double? _gyroBiasDriftDegPerS;

  // GNSS fix cadence.
  int _gnssFixes = 0;
  int _gnssGaps = 0;
  int? _lastGnssUs;
  double? _gnssMeanIntervalUs;

  /// Gravity-direction wobble (deg), or null before the handling window has
  /// filled — the same signal driving [isHandling].
  double? get orientationWobbleDeg =>
      _handling.gravityDirection == null ? null : _handling.wobbleDeg;

  bool get isHandling => _handling.isHandling;

  void reset() {
    _timeSync.reset();
    _faults.reset();
    _handling.reset();
    _accelWindow.clear();
    _stationary = false;
    _quietSinceUs = null;
    _movingSinceUs = null;
    _biasWindowSum = Vector3.zero();
    _biasWindowCount = 0;
    _biasWindowStartUs = null;
    _lastStationaryMeanGyro = null;
    _lastStationaryMeanUs = null;
    _gyroBiasDriftDegPerS = null;
    _gnssFixes = 0;
    _gnssGaps = 0;
    _lastGnssUs = null;
    _gnssMeanIntervalUs = null;
  }

  /// Feeds one raw phone-frame IMU sample.
  void observeImu({
    required Vector3 accelPhone,
    required Vector3 gyroPhone,
    Vector3? magPhone,
    required int monotonicUs,
  }) {
    if (!_finite(accelPhone) || !_finite(gyroPhone)) return;

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
    _faults.checkStaleness(monotonicUs);

    _handling.add(
      accelPhone: accelPhone,
      gyroPhone: gyroPhone,
      monotonicUs: monotonicUs,
    );
    final stationary = _updateStationary(accelPhone.length, monotonicUs);
    _updateGyroBias(gyroPhone, stationary, monotonicUs);
  }

  /// Feeds one GNSS fix arrival (accepted or not — cadence is about the
  /// receiver, not the filter's opinion of the fix).
  void observeGnssFix(int monotonicUs) {
    _gnssFixes++;
    final last = _lastGnssUs;
    _lastGnssUs = monotonicUs;
    if (last == null) return;
    final interval = (monotonicUs - last).toDouble();
    final mean = _gnssMeanIntervalUs;
    if (mean == null) {
      _gnssMeanIntervalUs = interval;
    } else {
      if (interval > mean * _config.gnssGapFactor) _gnssGaps++;
      _gnssMeanIntervalUs = mean + 0.3 * (interval - mean);
    }
  }

  SensorHealthReport evaluate({required int monotonicUs}) {
    final checks = <HealthCheck>[
      _sensorCheck('Accelerometer', SensorType.accelerometer, 'm/s²'),
      _sensorCheck('Gyroscope', SensorType.gyroscope, 'rad/s'),
      _sensorCheck('Magnetometer', SensorType.magnetometer, 'µT'),
      _gnssCheck(monotonicUs),
      _rateCheck(),
      _jitterCheck(),
      _mountStabilityCheck(),
      _magneticInterferenceCheck(),
      _gyroBiasCheck(),
    ];
    final worst = checks
        .map((c) => c.verdict)
        .where((v) => v != HealthVerdict.pending)
        .fold<HealthVerdict?>(null, (a, b) =>
            a == null || b._severity > a._severity ? b : a);
    return SensorHealthReport(
      overall: worst ?? HealthVerdict.pending,
      checks: checks,
    );
  }

  HealthCheck _sensorCheck(String name, SensorType type, String unit) {
    final diag = _faults.diagnoses[type];
    if (diag == null || diag.samples == 0) {
      return HealthCheck(
        name: name,
        verdict: HealthVerdict.pending,
        value: '--',
        reason: 'No samples yet',
      );
    }
    if (!diag.usable) {
      final hard = diag.fault == SensorFault.stalled ||
          diag.fault == SensorFault.frozen ||
          diag.fault == SensorFault.outOfRange;
      return HealthCheck(
        name: name,
        verdict: hard ? HealthVerdict.fail : HealthVerdict.degraded,
        value: diag.fault.label,
        reason: diag.detail,
      );
    }
    final mag = diag.magnitude;
    return HealthCheck(
      name: name,
      verdict: HealthVerdict.pass,
      value: mag == null ? 'OK' : '${mag.toStringAsFixed(2)} $unit',
    );
  }

  HealthCheck _gnssCheck(int monotonicUs) {
    if (_gnssFixes == 0) {
      return const HealthCheck(
        name: 'GNSS',
        verdict: HealthVerdict.pending,
        value: '--',
        reason: 'No fix yet',
      );
    }
    final last = _lastGnssUs!;
    if (monotonicUs - last > _config.gnssStaleAfter.inMicroseconds) {
      return HealthCheck(
        name: 'GNSS',
        verdict: HealthVerdict.fail,
        value: '${((monotonicUs - last) / 1e6).toStringAsFixed(0)} s since '
            'last fix',
        reason: 'No recent fix',
      );
    }
    final mean = _gnssMeanIntervalUs;
    final hz = (mean == null || mean <= 0) ? null : 1e6 / mean;
    final hzText = hz == null ? '--' : '${hz.toStringAsFixed(2)} Hz';
    if (_gnssGaps > 0) {
      return HealthCheck(
        name: 'GNSS',
        verdict: HealthVerdict.degraded,
        value: '$hzText · $_gnssGaps gaps',
        reason: 'Fix cadence irregular',
      );
    }
    return HealthCheck(name: 'GNSS', verdict: HealthVerdict.pass, value: hzText);
  }

  HealthCheck _rateCheck() {
    final accelHz = _timeSync.statsFor(SensorType.accelerometer).effectiveHz;
    final gyroHz = _timeSync.statsFor(SensorType.gyroscope).effectiveHz;
    if (accelHz == null || gyroHz == null) {
      return const HealthCheck(
        name: 'Sampling rate',
        verdict: HealthVerdict.pending,
        value: '--',
      );
    }
    final worst = math.min(accelHz, gyroHz);
    final verdict = worst < _config.minAcceptableHz
        ? HealthVerdict.fail
        : worst < _config.minGoodHz
            ? HealthVerdict.degraded
            : HealthVerdict.pass;
    return HealthCheck(
      name: 'Sampling rate',
      verdict: verdict,
      value: '${worst.toStringAsFixed(0)} Hz',
      reason: verdict == HealthVerdict.pass
          ? null
          : 'Accel/gyro below ${_config.minGoodHz.toStringAsFixed(0)} Hz',
    );
  }

  HealthCheck _jitterCheck() {
    final accel = _timeSync.statsFor(SensorType.accelerometer);
    final gyro = _timeSync.statsFor(SensorType.gyroscope);
    if (accel.jitterRatio == null || gyro.jitterRatio == null) {
      return const HealthCheck(
        name: 'Timestamp jitter',
        verdict: HealthVerdict.pending,
        value: '--',
      );
    }
    double? jitterMs(SensorStreamStats s) {
      final hz = s.effectiveHz;
      final ratio = s.jitterRatio;
      if (hz == null || hz <= 0 || ratio == null) return null;
      return ratio * (1000 / hz);
    }

    final ms = [jitterMs(accel), jitterMs(gyro)]
        .whereType<double>()
        .fold<double>(0, math.max);
    final worstQuality = _worseQuality(accel.quality, gyro.quality);
    final verdict = switch (worstQuality) {
      SampleQuality.excellent || SampleQuality.good => HealthVerdict.pass,
      SampleQuality.degraded => HealthVerdict.degraded,
      SampleQuality.invalid => HealthVerdict.fail,
    };
    return HealthCheck(
      name: 'Timestamp jitter',
      verdict: verdict,
      value: '${ms.toStringAsFixed(1)} ms',
      reason: verdict == HealthVerdict.pass ? null : 'Irregular sample timing',
    );
  }

  HealthCheck _mountStabilityCheck() {
    final wobble = orientationWobbleDeg;
    if (wobble == null) {
      return const HealthCheck(
        name: 'Mount stability',
        verdict: HealthVerdict.pending,
        value: '--',
      );
    }
    final verdict = wobble >= _config.orientationWobbleFailDeg
        ? HealthVerdict.fail
        : wobble >= _config.orientationWobbleDegradedDeg
            ? HealthVerdict.degraded
            : HealthVerdict.pass;
    return HealthCheck(
      name: 'Mount stability',
      verdict: verdict,
      value: '${wobble.toStringAsFixed(1)}°',
      reason: verdict == HealthVerdict.pass
          ? null
          : 'Phone moving in its mount',
    );
  }

  HealthCheck _magneticInterferenceCheck() {
    final diag = _faults.diagnoses[SensorType.magnetometer];
    if (diag == null || diag.samples == 0) {
      return const HealthCheck(
        name: 'Magnetic interference',
        verdict: HealthVerdict.pending,
        value: '--',
      );
    }
    final mag = diag.magnitude;
    if (diag.fault == SensorFault.magneticDisturbance || mag == null) {
      return HealthCheck(
        name: 'Magnetic interference',
        verdict: HealthVerdict.fail,
        value: mag == null ? '--' : '${mag.toStringAsFixed(0)} µT',
        reason: 'Outside Earth\'s field',
      );
    }
    const softMargin = 5.0;
    final soft = mag < _fieldConfig.minFieldMicroTesla + softMargin ||
        mag > _fieldConfig.maxFieldMicroTesla - softMargin;
    return HealthCheck(
      name: 'Magnetic interference',
      verdict: soft ? HealthVerdict.degraded : HealthVerdict.pass,
      value: '${mag.toStringAsFixed(0)} µT',
      reason: soft ? 'Near the edge of Earth\'s field band' : null,
    );
  }

  HealthCheck _gyroBiasCheck() {
    final drift = _gyroBiasDriftDegPerS;
    if (drift == null) {
      return const HealthCheck(
        name: 'Gyro bias stability',
        verdict: HealthVerdict.pending,
        value: '--',
        reason: 'Waiting for two stationary periods',
      );
    }
    final verdict = drift >= 2.0
        ? HealthVerdict.fail
        : drift >= 0.5
            ? HealthVerdict.degraded
            : HealthVerdict.pass;
    return HealthCheck(
      name: 'Gyro bias stability',
      verdict: verdict,
      value: '${drift.toStringAsFixed(2)} deg/s',
      reason: verdict == HealthVerdict.pass ? null : 'Bias drifting at rest',
    );
  }

  bool _updateStationary(double accelMagnitude, int monotonicUs) {
    _accelWindow.add(_TimedScalar(monotonicUs, accelMagnitude));
    while (_accelWindow.isNotEmpty &&
        monotonicUs - _accelWindow.first.us >
            const Duration(seconds: 1).inMicroseconds) {
      _accelWindow.removeAt(0);
    }
    if (_accelWindow.length < 3) return _stationary;

    var sum = 0.0;
    for (final s in _accelWindow) {
      sum += s.value;
    }
    final mean = sum / _accelWindow.length;
    var variance = 0.0;
    for (final s in _accelWindow) {
      final d = s.value - mean;
      variance += d * d;
    }
    variance /= _accelWindow.length;
    final quiet = math.sqrt(variance) < _stopAccelStd;

    if (quiet) {
      _movingSinceUs = null;
      _quietSinceUs ??= monotonicUs;
      if (!_stationary &&
          monotonicUs - _quietSinceUs! >= _stopEnterDelay.inMicroseconds) {
        _stationary = true;
      }
    } else {
      _quietSinceUs = null;
      _movingSinceUs ??= monotonicUs;
      if (_stationary &&
          monotonicUs - _movingSinceUs! >= _stopExitDelay.inMicroseconds) {
        _stationary = false;
      }
    }
    return _stationary;
  }

  void _updateGyroBias(Vector3 gyroPhone, bool stationary, int monotonicUs) {
    if (!stationary) {
      _biasWindowSum = Vector3.zero();
      _biasWindowCount = 0;
      _biasWindowStartUs = null;
      return;
    }
    _biasWindowStartUs ??= monotonicUs;
    _biasWindowSum += gyroPhone;
    _biasWindowCount++;
    if (monotonicUs - _biasWindowStartUs! < _config.gyroBiasWindow.inMicroseconds) {
      return;
    }

    final mean = _biasWindowSum / _biasWindowCount.toDouble();
    final prevMean = _lastStationaryMeanGyro;
    final prevUs = _lastStationaryMeanUs;
    if (prevMean != null && prevUs != null) {
      final dtS = (monotonicUs - prevUs) / 1e6;
      if (dtS > 0) {
        _gyroBiasDriftDegPerS =
            (mean - prevMean).length * NavMath.radToDeg / dtS;
      }
    }
    _lastStationaryMeanGyro = mean;
    _lastStationaryMeanUs = monotonicUs;
    _biasWindowSum = Vector3.zero();
    _biasWindowCount = 0;
    _biasWindowStartUs = monotonicUs;
  }

  static SampleQuality _worseQuality(SampleQuality a, SampleQuality b) {
    const order = [
      SampleQuality.excellent,
      SampleQuality.good,
      SampleQuality.degraded,
      SampleQuality.invalid,
    ];
    return order.indexOf(a) >= order.indexOf(b) ? a : b;
  }

  static bool _finite(Vector3 v) =>
      v.x.isFinite && v.y.isFinite && v.z.isFinite;
}

class _TimedScalar {
  const _TimedScalar(this.us, this.value);
  final int us;
  final double value;
}
