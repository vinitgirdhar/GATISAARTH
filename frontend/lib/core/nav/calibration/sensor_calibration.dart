import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';
import '../nav_config.dart';
import 'ellipsoid_fit.dart';

/// Which calibration produced a stored set of parameters (§5).
enum CalibrationMode {
  /// 10-20 s with the phone held still. Observes gyroscope bias and the noise
  /// statistics of every sensor. Does **not** observe accelerometer bias —
  /// see [SensorCalibration.accelBiasQuality].
  quick,

  /// Guided: the phone is placed in several distinct orientations and then
  /// rotated. Observes accelerometer bias and scale, and magnetometer
  /// hard-iron and diagonal soft-iron.
  full,
}

/// Stored sensor calibration (§5).
///
/// Every quality field is nullable and every one is `null` when the procedure
/// could not observe that parameter. A missing quality is shown as `--`, never
/// as 0 % and never as a confident-looking number (§83).
@immutable
class SensorCalibration {
  SensorCalibration({
    required this.mode,
    required this.createdAtMs,
    Vector3? accelBias,
    Vector3? accelScale,
    Vector3? gyroBias,
    Vector3? magHardIron,
    Vector3? magSoftIron,
    this.accelNoiseStd,
    this.gyroNoiseStd,
    this.magNoiseStd,
    this.accelBiasQuality,
    this.gyroBiasQuality,
    this.magQuality,
    this.temperatureC,
    this.configVersion = NavConfig.currentVersion,
    this.notes = const [],
  })  : accelBias = accelBias ?? Vector3.zero(),
        accelScale = accelScale ?? unitScale(),
        gyroBias = gyroBias ?? Vector3.zero(),
        magHardIron = magHardIron ?? Vector3.zero(),
        magSoftIron = magSoftIron ?? unitScale();

  /// A scale vector meaning "no correction".
  static Vector3 unitScale() => Vector3(1, 1, 1);

  /// An identity calibration: nothing measured, nothing claimed.
  static final SensorCalibration none = SensorCalibration(
    mode: CalibrationMode.quick,
    createdAtMs: 0,
  );

  final CalibrationMode mode;
  final int createdAtMs;

  final Vector3 accelBias; // m/s²
  final Vector3 accelScale; // dimensionless, 1 = no error
  final Vector3 gyroBias; // rad/s
  final Vector3 magHardIron; // µT
  final Vector3 magSoftIron; // dimensionless

  /// 1-sigma noise measured while still, per sensor. Feeds the filter's
  /// process noise instead of a datasheet guess (§12).
  final double? accelNoiseStd;
  final double? gyroNoiseStd;
  final double? magNoiseStd;

  /// 0..1. **Null after a quick calibration** — a stationary phone in one
  /// orientation constrains only `|g + bias|`, which is one equation in three
  /// unknowns. Claiming an accelerometer bias from it would be fabrication.
  final double? accelBiasQuality;

  final double? gyroBiasQuality;
  final double? magQuality;

  /// Device temperature when the calibration was taken. MEMS bias moves with
  /// die temperature, so a large swing invalidates it (§5).
  final double? temperatureC;

  final int configVersion;

  /// Human-readable caveats to show next to the numbers.
  final List<String> notes;

  bool get isEmpty => createdAtMs == 0;

  Vector3 correctAccel(Vector3 raw) => Vector3(
        (raw.x - accelBias.x) * accelScale.x,
        (raw.y - accelBias.y) * accelScale.y,
        (raw.z - accelBias.z) * accelScale.z,
      );

  Vector3 correctGyro(Vector3 raw) => raw - gyroBias;

  Vector3 correctMag(Vector3 raw) => Vector3(
        (raw.x - magHardIron.x) * magSoftIron.x,
        (raw.y - magHardIron.y) * magSoftIron.y,
        (raw.z - magHardIron.z) * magSoftIron.z,
      );

  /// True when this calibration should no longer be trusted (§5).
  bool isStale({
    required int nowMs,
    double? temperatureC,
    NavConfig config = NavConfig.defaults,
  }) {
    if (isEmpty) return true;
    if (configVersion != config.version) return true;
    if (nowMs - createdAtMs > config.calibration.staleAfter.inMilliseconds) {
      return true;
    }
    final then = this.temperatureC;
    if (then != null && temperatureC != null) {
      if ((temperatureC - then).abs() >
          config.calibration.invalidateOnTempDeltaC) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'createdAtMs': createdAtMs,
        'configVersion': configVersion,
        'accelBias': _vecJson(accelBias),
        'accelScale': _vecJson(accelScale),
        'gyroBias': _vecJson(gyroBias),
        'magHardIron': _vecJson(magHardIron),
        'magSoftIron': _vecJson(magSoftIron),
        'accelNoiseStd': accelNoiseStd,
        'gyroNoiseStd': gyroNoiseStd,
        'magNoiseStd': magNoiseStd,
        'accelBiasQuality': accelBiasQuality,
        'gyroBiasQuality': gyroBiasQuality,
        'magQuality': magQuality,
        'temperatureC': temperatureC,
        'notes': notes,
      };

  static SensorCalibration? fromJson(Map<String, dynamic> json) {
    try {
      final createdAtMs = json['createdAtMs'];
      if (createdAtMs is! int) return null;
      return SensorCalibration(
        mode: CalibrationMode.values.firstWhere(
          (m) => m.name == json['mode'],
          orElse: () => CalibrationMode.quick,
        ),
        createdAtMs: createdAtMs,
        configVersion: (json['configVersion'] as num?)?.toInt() ??
            NavConfig.currentVersion,
        accelBias: _vecFrom(json['accelBias']),
        accelScale: _vecFrom(json['accelScale']),
        gyroBias: _vecFrom(json['gyroBias']),
        magHardIron: _vecFrom(json['magHardIron']),
        magSoftIron: _vecFrom(json['magSoftIron']),
        accelNoiseStd: (json['accelNoiseStd'] as num?)?.toDouble(),
        gyroNoiseStd: (json['gyroNoiseStd'] as num?)?.toDouble(),
        magNoiseStd: (json['magNoiseStd'] as num?)?.toDouble(),
        accelBiasQuality: (json['accelBiasQuality'] as num?)?.toDouble(),
        gyroBiasQuality: (json['gyroBiasQuality'] as num?)?.toDouble(),
        magQuality: (json['magQuality'] as num?)?.toDouble(),
        temperatureC: (json['temperatureC'] as num?)?.toDouble(),
        notes: (json['notes'] as List?)?.whereType<String>().toList() ??
            const [],
      );
    } catch (_) {
      // A corrupt stored calibration must never crash start-up; the caller
      // re-calibrates instead.
      return null;
    }
  }

  static List<double> _vecJson(Vector3 v) => [v.x, v.y, v.z];

  static Vector3? _vecFrom(Object? raw) {
    if (raw is! List || raw.length != 3) return null;
    final values = raw.whereType<num>().map((n) => n.toDouble()).toList();
    if (values.length != 3 || values.any((v) => !v.isFinite)) return null;
    return Vector3(values[0], values[1], values[2]);
  }
}

@immutable
class CalibrationProgress {
  const CalibrationProgress({
    required this.stillSamples,
    required this.accelSamples,
    required this.magSamples,
    required this.orientationsSeen,
    required this.isStill,
    required this.magCoverage,
    required this.ready,
    this.hint = '',
  });

  final int stillSamples;
  final int accelSamples;
  final int magSamples;

  /// Distinct direction octants the static accelerometer has visited — the
  /// thing the user is being asked to produce during a full calibration.
  final int orientationsSeen;

  final bool isStill;
  final double magCoverage;

  /// True when enough has been captured for [CalibrationEstimator.finish] to
  /// produce something worth storing.
  final bool ready;

  final String hint;
}

/// Estimates sensor calibration from a stream of raw samples (§5).
///
/// Quick mode wants the phone held still. Full mode wants it placed in several
/// orientations and then rotated; the estimator tells the caller what is still
/// missing through [CalibrationProgress.hint] so the UI can prompt rather than
/// guess.
class CalibrationEstimator {
  CalibrationEstimator({
    required this.mode,
    NavConfig config = NavConfig.defaults,
  }) : _config = config.calibration;

  final CalibrationMode mode;
  final CalibrationConfig _config;

  final List<Vector3> _stillAccel = [];
  final List<Vector3> _stillGyro = [];
  final List<Vector3> _staticAccelByOrientation = [];
  final List<Vector3> _mag = [];

  final List<Vector3> _recentAccel = [];
  final List<Vector3> _recentGyro = [];

  double? _temperatureC;
  bool _isStill = false;

  static const int _windowSamples = 25;

  /// Feeds one raw IMU sample. [mag] and [temperatureC] are optional; a phone
  /// without a magnetometer simply produces no magnetometer calibration.
  CalibrationProgress add({
    required Vector3 accel,
    required Vector3 gyro,
    Vector3? mag,
    double? temperatureC,
  }) {
    if (temperatureC != null && temperatureC.isFinite) {
      _temperatureC = temperatureC;
    }
    if (!_finite(accel) || !_finite(gyro)) return progress;

    _recentAccel.add(accel);
    _recentGyro.add(gyro);
    if (_recentAccel.length > _windowSamples) _recentAccel.removeAt(0);
    if (_recentGyro.length > _windowSamples) _recentGyro.removeAt(0);

    _isStill = _recentAccel.length >= _windowSamples &&
        _std(_recentAccel.map((v) => v.length)) < _config.stillAccelStd &&
        _std(_recentGyro.map((v) => v.length)) < _config.stillGyroStd;

    if (_isStill) {
      _stillAccel.add(accel);
      _stillGyro.add(gyro);
      // One static sample per orientation is enough for the sphere fit, and
      // keeping every sample of a long pause would bias the fit towards
      // whichever orientation the user held longest.
      if (_isNewOrientation(accel)) _staticAccelByOrientation.add(accel);
    }

    if (mag != null && _finite(mag) && mode == CalibrationMode.full) {
      if (_mag.isEmpty || (mag - _mag.last).length > 0.5) _mag.add(mag);
    }
    return progress;
  }

  bool _isNewOrientation(Vector3 accel) {
    const minSeparation = 3.0; // m/s², about 18 degrees of tilt
    for (final existing in _staticAccelByOrientation) {
      if ((accel - existing).length < minSeparation) return false;
    }
    return true;
  }

  CalibrationProgress get progress {
    final magCoverage = _mag.length < EllipsoidFitter.minimumSamples
        ? 0.0
        : EllipsoidFitter.directionCoverage(_mag, _meanOf(_mag));
    final ready = mode == CalibrationMode.quick
        ? _stillGyro.length >= _config.minSamples
        : _staticAccelByOrientation.length >= 4 &&
            _stillGyro.length >= _config.minSamples;

    return CalibrationProgress(
      stillSamples: _stillGyro.length,
      accelSamples: _stillAccel.length,
      magSamples: _mag.length,
      orientationsSeen: _staticAccelByOrientation.length,
      isStill: _isStill,
      magCoverage: magCoverage,
      ready: ready,
      hint: _hint(magCoverage, ready),
    );
  }

  String _hint(double magCoverage, bool ready) {
    if (mode == CalibrationMode.quick) {
      if (_stillGyro.length >= _config.minSamples) return 'Done';
      return _isStill ? 'Hold still' : 'Put the phone down and keep it still';
    }
    if (_staticAccelByOrientation.length < 4) {
      return 'Rest the phone in a different position '
          '(${_staticAccelByOrientation.length} of 4)';
    }
    if (!ready) return 'Hold still a moment longer';
    if (magCoverage < 0.75 && _mag.isNotEmpty) {
      return 'Rotate the phone slowly through every direction';
    }
    return 'Done';
  }

  /// Produces the calibration, or null when not enough was captured.
  SensorCalibration? finish({required int nowMs}) {
    if (_stillGyro.length < _config.minSamples) return null;

    final notes = <String>[];
    final gyroBias = _meanOf(_stillGyro);
    if (gyroBias.length > _config.maxGyroBias) {
      // A bias this large means the phone was moving, not that the gyro is bad.
      return null;
    }

    final gyroNoise = _std(_stillGyro.map((v) => v.length));
    final accelNoise = _std(_stillAccel.map((v) => v.length));

    // Gyro quality: enough still samples, and noise low enough for the mean to
    // mean something. Capped below 1 — a 20 s sample cannot certify a sensor.
    final sampleFactor =
        (_stillGyro.length / (_config.minSamples * 3)).clamp(0.0, 1.0);
    final noiseFactor =
        (1 - gyroNoise / (_config.stillGyroStd * 2)).clamp(0.0, 1.0);
    final gyroQuality = (0.55 + 0.45 * sampleFactor * noiseFactor)
        .clamp(0.0, 0.99)
        .toDouble();

    var accelBias = Vector3.zero();
    var accelScale = SensorCalibration.unitScale();
    double? accelQuality;
    var magHardIron = Vector3.zero();
    var magSoftIron = SensorCalibration.unitScale();
    double? magQuality;

    if (mode == CalibrationMode.quick) {
      notes.add('Quick calibration: gyroscope bias and noise only. '
          'Accelerometer bias needs several orientations.');
    } else {
      final accelFit = EllipsoidFitter.fit(_stillAccel);
      if (accelFit == null || _staticAccelByOrientation.length < 4) {
        notes.add('Not enough orientations for an accelerometer fit.');
      } else if (accelFit.gravityError > 1.0) {
        notes.add('Accelerometer fit rejected: sphere radius '
            '${accelFit.meanRadius.toStringAsFixed(2)} m/s² is not gravity.');
      } else if (accelFit.centre.length > _config.maxAccelBias) {
        notes.add('Accelerometer bias estimate out of range, discarded.');
      } else {
        accelBias = accelFit.centre;
        accelScale = accelFit.scale;
        accelQuality = _fitQuality(
          fit: accelFit,
          samples: _stillAccel,
          referenceRadius: NavMath.gravity,
        );
      }

      if (_mag.length >= EllipsoidFitter.minimumSamples) {
        final magFit = EllipsoidFitter.fit(_mag);
        if (magFit == null) {
          notes.add('Magnetometer fit failed; the readings are not a sphere.');
        } else if (_axisSpread(_mag) < _config.magFitMinSpread) {
          notes.add('Magnetometer barely moved; hard-iron fit discarded.');
        } else {
          magHardIron = magFit.centre;
          magSoftIron = magFit.scale;
          magQuality = _fitQuality(fit: magFit, samples: _mag);
        }
      } else if (_mag.isEmpty) {
        notes.add('No magnetometer on this device.');
      } else {
        notes.add('Too few magnetometer samples for a hard-iron fit.');
      }
    }

    return SensorCalibration(
      mode: mode,
      createdAtMs: nowMs,
      accelBias: accelBias,
      accelScale: accelScale,
      gyroBias: gyroBias,
      magHardIron: magHardIron,
      magSoftIron: magSoftIron,
      accelNoiseStd: _stillAccel.length >= 10 ? accelNoise : null,
      gyroNoiseStd: gyroNoise,
      magNoiseStd: _mag.length >= 10 ? _std(_mag.map((v) => v.length)) : null,
      accelBiasQuality: accelQuality,
      gyroBiasQuality: gyroQuality,
      magQuality: magQuality,
      temperatureC: _temperatureC,
      notes: notes,
    );
  }

  /// Fit quality from geometry first, residual second.
  ///
  /// Coverage and planarity gate it: a tiny residual from samples that all sit
  /// in one plane describes a circle, not a sphere, and the unobserved axis
  /// would be pure invention.
  static double _fitQuality({
    required EllipsoidFit fit,
    required List<Vector3> samples,
    double? referenceRadius,
  }) {
    final coverage = fit.coverage;
    final planarity = EllipsoidFitter.planarity(samples, fit.centre);
    final scale = referenceRadius ?? fit.meanRadius;
    final residual =
        scale <= 0 ? 1.0 : (fit.residualRms / scale).clamp(0.0, 1.0);
    final geometry = math.sqrt(coverage * planarity);
    return (geometry * (1 - residual)).clamp(0.0, 0.99).toDouble();
  }

  void reset() {
    _stillAccel.clear();
    _stillGyro.clear();
    _staticAccelByOrientation.clear();
    _mag.clear();
    _recentAccel.clear();
    _recentGyro.clear();
    _isStill = false;
  }

  static Vector3 _meanOf(List<Vector3> values) {
    if (values.isEmpty) return Vector3.zero();
    var x = 0.0, y = 0.0, z = 0.0;
    for (final v in values) {
      x += v.x;
      y += v.y;
      z += v.z;
    }
    final n = values.length;
    return Vector3(x / n, y / n, z / n);
  }

  static double _std(Iterable<double> values) {
    final list = values.toList(growable: false);
    if (list.length < 2) return 0;
    final mean = list.reduce((a, b) => a + b) / list.length;
    var sum = 0.0;
    for (final v in list) {
      final d = v - mean;
      sum += d * d;
    }
    return math.sqrt(sum / list.length);
  }

  /// Largest per-axis peak-to-peak spread, used to reject a magnetometer that
  /// never really moved.
  static double _axisSpread(List<Vector3> values) {
    if (values.isEmpty) return 0;
    var minX = values.first.x, maxX = minX;
    var minY = values.first.y, maxY = minY;
    var minZ = values.first.z, maxZ = minZ;
    for (final v in values) {
      minX = math.min(minX, v.x);
      maxX = math.max(maxX, v.x);
      minY = math.min(minY, v.y);
      maxY = math.max(maxY, v.y);
      minZ = math.min(minZ, v.z);
      maxZ = math.max(maxZ, v.z);
    }
    return math.min(maxX - minX, math.min(maxY - minY, maxZ - minZ));
  }

  static bool _finite(Vector3 v) =>
      v.x.isFinite && v.y.isFinite && v.z.isFinite;
}
