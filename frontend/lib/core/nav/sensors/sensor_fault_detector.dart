import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../nav_config.dart';
import 'sensor_sample.dart';

/// What is wrong with a sensor (§29).
enum SensorFault {
  none,

  /// Identical values sample after sample. Real MEMS always jitters at the
  /// least significant bit, so a perfectly still reading means the sensor or
  /// its driver has stopped producing.
  frozen,

  /// No sample for longer than the stream's own cadence allows.
  stalled,

  /// Values outside anything physically possible for the quantity.
  outOfRange,

  /// Noise far above what this sensor should produce, even on a rough road.
  excessiveNoise,

  /// Magnetometer only: the field magnitude is nothing like Earth's, so the
  /// reading is measuring something in the car rather than the planet.
  magneticDisturbance,
}

extension SensorFaultLabel on SensorFault {
  String get label {
    switch (this) {
      case SensorFault.none:
        return 'OK';
      case SensorFault.frozen:
        return 'Frozen';
      case SensorFault.stalled:
        return 'No data';
      case SensorFault.outOfRange:
        return 'Out of range';
      case SensorFault.excessiveNoise:
        return 'Excessive noise';
      case SensorFault.magneticDisturbance:
        return 'Magnetic interference';
    }
  }
}

@immutable
class SensorDiagnosis {
  const SensorDiagnosis({
    required this.type,
    required this.fault,
    required this.usable,
    required this.samples,
    this.detail,
    this.magnitude,
    this.noiseStd,
  });

  const SensorDiagnosis.unavailable(this.type)
      : fault = SensorFault.stalled,
        usable = false,
        samples = 0,
        detail = 'Not present on this device',
        magnitude = null,
        noiseStd = null;

  final SensorType type;
  final SensorFault fault;

  /// False when the navigation core must stop using this sensor.
  final bool usable;

  final int samples;
  final String? detail;

  /// Mean magnitude over the window, in the sensor's own units.
  final double? magnitude;
  final double? noiseStd;

  bool get isHealthy => fault == SensorFault.none;
}

/// Watches each sensor stream for the ways one can go wrong (§29).
///
/// Isolation, not shutdown: a failed magnetometer must not stop inertial
/// navigation, it must stop *the magnetometer* from feeding the filter. The
/// only fault that can end navigation is losing the accelerometer or the
/// gyroscope, because without them there is nothing to propagate.
class SensorFaultDetector {
  SensorFaultDetector({NavConfig config = NavConfig.defaults})
      : _config = config.sensorFault,
        _sensors = config.sensors;

  final SensorFaultConfig _config;
  final SensorConfig _sensors;

  final Map<SensorType, _Window> _windows = {};
  final Map<SensorType, SensorDiagnosis> _diagnoses = {};

  Map<SensorType, SensorDiagnosis> get diagnoses =>
      Map.unmodifiable(_diagnoses);

  SensorDiagnosis diagnosisFor(SensorType type) =>
      _diagnoses[type] ?? SensorDiagnosis.unavailable(type);

  /// True when this sensor's readings may be fed to the filter.
  bool isUsable(SensorType type) => _diagnoses[type]?.usable ?? false;

  /// The accelerometer and gyroscope are the floor; everything else degrades a
  /// feature rather than the position (§3).
  bool get hasMinimumViableSensors =>
      isUsable(SensorType.accelerometer) && isUsable(SensorType.gyroscope);

  /// Sensors that are present but currently unusable.
  List<SensorType> get faultedSensors => _diagnoses.entries
      .where((e) => e.value.samples > 0 && !e.value.usable)
      .map((e) => e.key)
      .toList();

  void reset() {
    _windows.clear();
    _diagnoses.clear();
  }

  /// Records one sample and re-diagnoses that stream.
  SensorDiagnosis observe({
    required SensorType type,
    required List<double> values,
    required int monotonicUs,
  }) {
    final window = _windows.putIfAbsent(type, () => _Window());
    window.add(values, monotonicUs, _config.windowSamples);
    final diagnosis = _diagnose(type, window, monotonicUs);
    _diagnoses[type] = diagnosis;
    return diagnosis;
  }

  /// Re-checks every stream for staleness without a new sample. Call from the
  /// engine tick so a sensor that simply stops is noticed.
  void checkStaleness(int monotonicUs) {
    for (final entry in _windows.entries) {
      final last = entry.value.lastUs;
      if (last == null) continue;
      if (monotonicUs - last > _sensors.staleSample.inMicroseconds) {
        _diagnoses[entry.key] = SensorDiagnosis(
          type: entry.key,
          fault: SensorFault.stalled,
          usable: false,
          samples: entry.value.count,
          detail: 'No sample for '
              '${((monotonicUs - last) / 1000).round()} ms',
        );
      }
    }
  }

  SensorDiagnosis _diagnose(SensorType type, _Window window, int monotonicUs) {
    final magnitude = window.lastMagnitude;

    if (!window.lastFinite) {
      return SensorDiagnosis(
        type: type,
        fault: SensorFault.outOfRange,
        usable: false,
        samples: window.count,
        detail: 'Non-finite reading',
        magnitude: magnitude,
      );
    }

    final range = _rangeFor(type);
    if (range != null && magnitude != null) {
      if (magnitude > range) {
        return SensorDiagnosis(
          type: type,
          fault: SensorFault.outOfRange,
          usable: false,
          samples: window.count,
          detail: '${magnitude.toStringAsFixed(1)} exceeds the physical limit '
              'of ${range.toStringAsFixed(0)}',
          magnitude: magnitude,
        );
      }
    }

    // Magnetic field magnitude is a strong, cheap fault signal: Earth's field
    // is 25-65 microtesla everywhere, so anything well outside that is the
    // car's own metal or electronics, not the planet.
    if (type == SensorType.magnetometer && magnitude != null) {
      if (magnitude < _config.minFieldMicroTesla ||
          magnitude > _config.maxFieldMicroTesla) {
        return SensorDiagnosis(
          type: type,
          fault: SensorFault.magneticDisturbance,
          usable: false,
          samples: window.count,
          detail: '${magnitude.toStringAsFixed(0)} uT is not Earth\'s field',
          magnitude: magnitude,
        );
      }
    }

    if (window.identicalRun >= _config.frozenSamples) {
      // 1. Gyroscope at rest: On emulators, simulators, or physical hardware
      //    where zero-rate clamping occurs when motionless, the gyroscope
      //    naturally reports exact zeros or values near zero. This is normal
      //    physical resting state, NOT a frozen hardware fault.
      final isRestingGyro = type == SensorType.gyroscope &&
          (magnitude == 0.0 ||
              (magnitude != null && magnitude < 1e-4) ||
              (window.lastValues != null &&
                  window.lastValues!.every((v) => v == 0.0)));

      // 2. Accelerometer at rest: On emulators, simulators, or a phone sitting
      //    motionless in a vehicle mount / desk, the accelerometer measures
      //    nominal 1g Earth gravity (approx 9.81 m/s²). Identical readings at
      //    rest are expected physical behavior, not a frozen hardware fault.
      final isNominalRestingAccel = type == SensorType.accelerometer &&
          magnitude != null &&
          (magnitude - 9.81).abs() < 0.25;

      // 3. Magnetometer at rest in Earth's geomagnetic field:
      //    When motionless, Earth's ambient magnetic vector is constant.
      final isRestingMag = type == SensorType.magnetometer &&
          magnitude != null &&
          magnitude >= _config.minFieldMicroTesla &&
          magnitude <= _config.maxFieldMicroTesla;

      if (!isRestingGyro && !isNominalRestingAccel && !isRestingMag) {
        return SensorDiagnosis(
          type: type,
          fault: SensorFault.frozen,
          usable: false,
          samples: window.count,
          detail: '${window.identicalRun} identical readings',
          magnitude: magnitude,
        );
      }
    }

    final noise = window.count >= _config.windowSamples ~/ 2
        ? window.magnitudeStd
        : null;
    final noiseLimit = _noiseLimitFor(type);
    if (noise != null && noiseLimit != null && noise > noiseLimit) {
      return SensorDiagnosis(
        type: type,
        fault: SensorFault.excessiveNoise,
        usable: false,
        samples: window.count,
        detail: 'Noise ${noise.toStringAsFixed(2)} above the '
            '${noiseLimit.toStringAsFixed(2)} limit',
        magnitude: magnitude,
        noiseStd: noise,
      );
    }

    return SensorDiagnosis(
      type: type,
      fault: SensorFault.none,
      usable: true,
      samples: window.count,
      magnitude: magnitude,
      noiseStd: noise,
    );
  }

  double? _rangeFor(SensorType type) {
    switch (type) {
      case SensorType.accelerometer:
      case SensorType.linearAcceleration:
      case SensorType.gravity:
        return _config.maxAccelMagnitude;
      case SensorType.gyroscope:
        return _config.maxGyroMagnitude;
      case SensorType.magnetometer:
        return _config.maxFieldMicroTesla * 10;
      default:
        return null;
    }
  }

  double? _noiseLimitFor(SensorType type) {
    switch (type) {
      case SensorType.accelerometer:
        return _config.maxAccelNoise;
      case SensorType.gyroscope:
        return _config.maxGyroNoise;
      default:
        return null;
    }
  }
}

class _Window {
  final Queue<double> _magnitudes = Queue<double>();
  List<double>? _lastValues;

  List<double>? get lastValues => _lastValues;

  int count = 0;
  int identicalRun = 0;
  int? lastUs;
  bool lastFinite = true;
  double? lastMagnitude;

  void add(List<double> values, int monotonicUs, int limit) {
    count++;
    lastUs = monotonicUs;
    lastFinite = values.every((v) => v.isFinite);

    if (!lastFinite) {
      lastMagnitude = null;
      _lastValues = List<double>.from(values);
      identicalRun = 0;
      return;
    }

    var sumSq = 0.0;
    for (final v in values) {
      sumSq += v * v;
    }
    final magnitude = math.sqrt(sumSq);
    lastMagnitude = magnitude;

    final previous = _lastValues;
    if (previous != null &&
        previous.length == values.length &&
        _identical(previous, values)) {
      identicalRun++;
    } else {
      identicalRun = 0;
    }
    _lastValues = List<double>.from(values);

    _magnitudes.addLast(magnitude);
    while (_magnitudes.length > limit) {
      _magnitudes.removeFirst();
    }
  }

  double get magnitudeStd {
    if (_magnitudes.length < 2) return 0;
    final mean =
        _magnitudes.reduce((a, b) => a + b) / _magnitudes.length;
    var sum = 0.0;
    for (final v in _magnitudes) {
      final d = v - mean;
      sum += d * d;
    }
    return math.sqrt(sum / _magnitudes.length);
  }

  static bool _identical(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
