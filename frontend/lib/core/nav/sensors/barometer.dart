import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../nav_config.dart';

/// Which way the vehicle is going vertically (§18).
enum VerticalMotion { flat, ascending, descending }

extension VerticalMotionLabel on VerticalMotion {
  String get label {
    switch (this) {
      case VerticalMotion.flat:
        return 'Level';
      case VerticalMotion.ascending:
        return 'Climbing';
      case VerticalMotion.descending:
        return 'Descending';
    }
  }
}

@immutable
class BarometerEstimate {
  const BarometerEstimate({
    required this.pressureHpa,
    required this.motion,
    this.relativeAltitudeM,
    this.absoluteAltitudeM,
    this.verticalRateMps,
    this.sigmaM,
    this.levelChanges = 0,
  });

  final double pressureHpa;
  final VerticalMotion motion;

  /// Height change since the reference was set (m). Reliable — this is what a
  /// barometer is genuinely good at.
  final double? relativeAltitudeM;

  /// Height above sea level (m), only when a GNSS altitude has anchored it.
  /// Null otherwise: a barometer alone cannot know its own datum.
  final double? absoluteAltitudeM;

  final double? verticalRateMps;

  /// Uncertainty of [absoluteAltitudeM]. Grows with time since the anchor,
  /// because weather moves the sea-level pressure under you (§18).
  final double? sigmaM;

  /// How many distinct level changes have been counted — car-park floors,
  /// flyover ramps.
  final int levelChanges;
}

/// Turns barometric pressure into height, honestly (§18).
///
/// A phone barometer measures height *change* superbly — a car-park floor or a
/// flyover ramp is unmistakable — and absolute height not at all, because the
/// sea-level pressure it would need moves with the weather by roughly a
/// hectopascal an hour, which is about 8 m. So the relative number is offered
/// freely and the absolute one only while a GNSS altitude has recently
/// anchored it, with an uncertainty that grows the moment that anchor goes
/// stale. It is evidence, never truth.
class BarometerProcessor {
  BarometerProcessor({NavConfig config = NavConfig.defaults})
      : _config = config.barometer;

  final BarometerConfig _config;

  double? _referencePressure;
  double? _anchorAltitudeM;
  int? _anchorUs;
  double _smoothedAltitude = 0;
  double? _lastAltitude;
  int? _lastUs;
  double _verticalRate = 0;
  int _levelChanges = 0;
  double? _levelBaseline;
  VerticalMotion _motion = VerticalMotion.flat;
  BarometerEstimate? _last;

  BarometerEstimate? get last => _last;
  bool get hasReference => _referencePressure != null;

  void reset() {
    _referencePressure = null;
    _anchorAltitudeM = null;
    _anchorUs = null;
    _smoothedAltitude = 0;
    _lastAltitude = null;
    _lastUs = null;
    _verticalRate = 0;
    _levelChanges = 0;
    _levelBaseline = null;
    _motion = VerticalMotion.flat;
    _last = null;
  }

  /// Anchors the absolute scale to a trusted GNSS altitude.
  ///
  /// Only call this with an altitude the GNSS quality engine accepted — a bad
  /// vertical fix would poison every height the barometer reports afterwards.
  void anchorToGnss({
    required double altitudeM,
    required double pressureHpa,
    required int monotonicUs,
  }) {
    if (!altitudeM.isFinite || !_isPlausible(pressureHpa)) return;
    _anchorAltitudeM = altitudeM;
    _anchorUs = monotonicUs;
    _referencePressure ??= pressureHpa;
  }

  /// Feeds one pressure reading. Returns null for an implausible one.
  BarometerEstimate? add({
    required double pressureHpa,
    required int monotonicUs,
  }) {
    if (!_isPlausible(pressureHpa)) return _last;

    _referencePressure ??= pressureHpa;
    final relative = _heightDifference(_referencePressure!, pressureHpa);

    // Pressure is noisy at the decimetre level; a little smoothing makes the
    // rate usable without hiding a real ramp.
    if (_lastAltitude == null) {
      _smoothedAltitude = relative;
      _levelBaseline = relative;
    } else {
      final a = _config.smoothing;
      _smoothedAltitude = _smoothedAltitude * a + relative * (1 - a);
    }

    final previousUs = _lastUs;
    if (previousUs != null && _lastAltitude != null) {
      final dt = (monotonicUs - previousUs) / 1e6;
      if (dt > 0 && dt < 5) {
        final instant = (_smoothedAltitude - _lastAltitude!) / dt;
        _verticalRate = _verticalRate * 0.8 + instant * 0.2;
      }
    }
    _lastAltitude = _smoothedAltitude;
    _lastUs = monotonicUs;

    _motion = _verticalRate > _config.motionRateMps
        ? VerticalMotion.ascending
        : _verticalRate < -_config.motionRateMps
            ? VerticalMotion.descending
            : VerticalMotion.flat;

    // A level change is a sustained step, not a wobble — a car-park floor or
    // a flyover ramp rather than a pothole.
    final baseline = _levelBaseline;
    if (baseline != null &&
        (_smoothedAltitude - baseline).abs() >= _config.levelChangeM) {
      _levelChanges++;
      _levelBaseline = _smoothedAltitude;
    }

    _last = BarometerEstimate(
      pressureHpa: pressureHpa,
      motion: _motion,
      relativeAltitudeM: _smoothedAltitude,
      absoluteAltitudeM: _absoluteAltitude(),
      verticalRateMps: _verticalRate,
      sigmaM: _sigma(monotonicUs),
      levelChanges: _levelChanges,
    );
    return _last;
  }

  double? _absoluteAltitude() {
    final anchor = _anchorAltitudeM;
    if (anchor == null) return null;
    return anchor + _smoothedAltitude;
  }

  /// Uncertainty of the absolute altitude, or null when there is none to
  /// report. Grows linearly with time since the GNSS anchor.
  double? _sigma(int monotonicUs) {
    final anchoredAt = _anchorUs;
    if (anchoredAt == null || _anchorAltitudeM == null) return null;
    final hours = (monotonicUs - anchoredAt) / 3.6e9;
    return _config.baseSigmaM + _config.driftSigmaMPerHour * math.max(0, hours);
  }

  /// Height difference from a pressure ratio, by the barometric formula.
  static double _heightDifference(double referenceHpa, double pressureHpa) =>
      44330.0 *
      (1.0 - math.pow(pressureHpa / referenceHpa, 1 / 5.255).toDouble());

  static bool _isPlausible(double hpa) =>
      hpa.isFinite && hpa > 300 && hpa < 1100;
}
