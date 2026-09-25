import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/fft.dart';
import '../nav_config.dart';

/// One reading of the tyre-vibration speedometer.
@immutable
class VibrationSpeedObservation {
  const VibrationSpeedObservation({
    required this.peakHz,
    required this.prominence,
    required this.monotonicUs,
    this.speedMps,
    this.sigmaMps,
  });

  /// Frequency of the dominant line in the wheel band.
  final double peakHz;

  /// Peak power over the band's median power.
  final double prominence;
  final int monotonicUs;

  /// Null until the per-vehicle scale has been learned from GNSS.
  final double? speedMps;
  final double? sigmaMps;
}

/// What the speedometer has done, for diagnostics and tests.
@immutable
class VibrationSpeedDiagnostics {
  const VibrationSpeedDiagnostics({
    required this.peaks,
    required this.calibrationPairs,
    required this.trusted,
    required this.applied,
    required this.rejected,
    this.metresPerCycle,
    this.relativeSpread,
    this.last,
  });

  final int peaks;
  final int calibrationPairs;
  final bool trusted;
  final int applied;
  final int rejected;

  /// Learned speed per hertz (the wheel circumference when the line is the
  /// first rotation harmonic).
  final double? metresPerCycle;
  final double? relativeSpread;
  final VibrationSpeedObservation? last;
}

/// Speed from the wheel-rotation line of the vertical accelerometer spectrum.
///
/// Every [VibrationSpeedConfig.updateInterval] it takes the last
/// [VibrationSpeedConfig.window] of vertical specific force, removes the mean,
/// applies a Hann window and finds the strongest line between
/// [VibrationSpeedConfig.minHz] and [VibrationSpeedConfig.maxHz]. While GNSS
/// is healthy [learn] pairs each line with the GNSS speed; the median ratio is
/// the vehicle's metres per cycle, and its robust spread says whether the line
/// is stable (one harmonic) or hopping (never trusted).
///
/// Pure Dart and deterministic (replay-safe).
class VibrationSpeedEstimator {
  VibrationSpeedEstimator({NavConfig config = NavConfig.defaults})
      : _c = config.vibrationSpeed;

  final VibrationSpeedConfig _c;
  final Queue<({int us, double z})> _samples = Queue();
  final Queue<double> _ratios = Queue();
  final Queue<({int us, double v})> _gnss = Queue();
  int? _lastEmitUs;
  int _peaks = 0, _applied = 0, _rejected = 0;
  VibrationSpeedObservation? _last;

  void add({required double verticalAccel, required int monotonicUs}) {
    if (!verticalAccel.isFinite) return;
    _samples.addLast((us: monotonicUs, z: verticalAccel));
    final windowUs = _c.window.inMicroseconds;
    while (_samples.length > 1 && monotonicUs - _samples.first.us > windowUs) {
      _samples.removeFirst();
    }
  }

  /// A new reading when the interval has passed and the window holds a clear
  /// line; null otherwise.
  VibrationSpeedObservation? poll(int monotonicUs) {
    final lastEmit = _lastEmitUs;
    if (lastEmit != null &&
        monotonicUs - lastEmit < _c.updateInterval.inMicroseconds) {
      return null;
    }
    if (_samples.length < 16) return null;
    final spanS = (_samples.last.us - _samples.first.us) / 1e6;
    if (spanS < _c.window.inMicroseconds / 1e6 * _c.minWindowFill) return null;
    final rateHz = (_samples.length - 1) / spanS;
    if (rateHz < _c.minSampleRateHz) return null;

    final peak = _strongestLine(rateHz);
    if (peak == null) return null;
    _lastEmitUs = monotonicUs;
    _peaks++;

    final scale = _scale;
    double? speed, sigma;
    if (trusted && scale != null) {
      speed = scale * peak.hz;
      if (speed < _c.minSpeed || speed > _c.maxSpeed) {
        speed = null;
      } else {
        final spread = _relativeSpread ?? 0;
        sigma = math
            .sqrt(math.pow(speed * spread, 2) + math.pow(scale * peak.binHz / 2, 2))
            .clamp(_c.minSigma, _c.maxSigma);
      }
    }
    return _last = VibrationSpeedObservation(
      peakHz: peak.hz,
      prominence: peak.prominence,
      monotonicUs: monotonicUs,
      speedMps: speed,
      sigmaMps: sigma,
    );
  }

  ({double hz, double prominence, double binHz})? _strongestLine(
      double rateHz) {
    final z = [for (final s in _samples) s.z];
    final mean = z.reduce((a, b) => a + b) / z.length;
    // Welch: [segments] half-overlapping Hann segments, power averaged.
    final segments = math.max(1, _c.segments);
    final segLen = (2 * z.length / (segments + 1)).floor();
    var size = 1;
    while (size < segLen) {
      size <<= 1;
    }
    final binHz = rateHz / size;
    final lo = math.max(1, (_c.minHz / binHz).ceil());
    final hi = math.min(size ~/ 2 - 1, (_c.maxHz / binHz).floor());
    if (hi - lo < 4) return null;
    final power = List<double>.filled(hi - lo + 1, 0);
    for (var seg = 0; seg < segments; seg++) {
      final start = seg * segLen ~/ 2;
      final re = List<double>.filled(size, 0);
      final im = List<double>.filled(size, 0);
      for (var i = 0; i < segLen && start + i < z.length; i++) {
        final hann = 0.5 - 0.5 * math.cos(2 * math.pi * i / (segLen - 1));
        re[i] = (z[start + i] - mean) * hann;
      }
      fftInPlace(re, im);
      for (var k = lo; k <= hi; k++) {
        power[k - lo] += re[k] * re[k] + im[k] * im[k];
      }
    }
    var best = 0;
    for (var k = 1; k < power.length; k++) {
      if (power[k] > power[best]) best = k;
    }
    final median = _median([...power]);
    if (median <= 0) return null;
    final prominence = power[best] / median;
    if (prominence < _c.minProminence) return null;
    // Parabolic interpolation on log power for a sub-bin frequency.
    var offset = 0.0;
    if (best > 0 && best < power.length - 1) {
      final a = math.log(power[best - 1] + 1e-12);
      final b = math.log(power[best] + 1e-12);
      final c = math.log(power[best + 1] + 1e-12);
      final d = a - 2 * b + c;
      if (d < 0) offset = (0.5 * (a - c) / d).clamp(-0.5, 0.5);
    }
    return (
      hz: (lo + best + offset) * binHz,
      prominence: prominence,
      binHz: binHz,
    );
  }

  /// Every GNSS speed, as it arrives; [learn] pairs spectra with them.
  void addGnssSpeed({required double speedMps, required int monotonicUs}) {
    if (!speedMps.isFinite) return;
    _gnss.addLast((us: monotonicUs, v: speedMps));
    final keepUs = 2 * _c.window.inMicroseconds;
    while (_gnss.isNotEmpty && monotonicUs - _gnss.first.us > keepUs) {
      _gnss.removeFirst();
    }
  }

  /// Learns this vehicle's metres-per-cycle from [obs] if GNSS held a steady
  /// speed over the same window. Returns whether a pair was taken.
  bool learn(VibrationSpeedObservation obs) {
    final from = obs.monotonicUs - _c.window.inMicroseconds;
    final speeds = [
      for (final g in _gnss)
        if (g.us >= from && g.us <= obs.monotonicUs) g.v
    ];
    if (speeds.length < _c.minGnssPerWindow) return false;
    final mean = speeds.reduce((a, b) => a + b) / speeds.length;
    if (mean < _c.minSpeed || mean > _c.maxSpeed) return false;
    final change = speeds.reduce(math.max) - speeds.reduce(math.min);
    if (change > _c.maxSpeedChange * mean) return false;
    _ratios.addLast(mean / obs.peakHz);
    while (_ratios.length > _c.calibrationWindow) {
      _ratios.removeFirst();
    }
    return true;
  }

  void noteApplied({required bool accepted}) =>
      accepted ? _applied++ : _rejected++;

  bool get trusted {
    if (_ratios.length < _c.calibrationMinPairs) return false;
    final fit = _fit;
    return fit != null && fit.inlierFraction >= _c.minInlierFraction;
  }

  double? get _scale => _fit?.scale;

  /// Relative spread (std / mean) of the inlier ratios.
  double? get _relativeSpread => _fit?.spread;

  /// Median ratio, then the ratios within [VibrationSpeedConfig.maxRelativeSpread]
  /// of it: their mean is the scale, their spread the uncertainty.
  ({double scale, double spread, double inlierFraction})? get _fit {
    if (_ratios.isEmpty) return null;
    final m = _median([..._ratios]);
    if (m <= 0) return null;
    final inliers = [
      for (final r in _ratios)
        if ((r - m).abs() <= _c.maxRelativeSpread * m) r
    ];
    // An even split between two harmonics leaves the median between them.
    if (inliers.isEmpty) return (scale: m, spread: 1.0, inlierFraction: 0.0);
    final mean = inliers.reduce((a, b) => a + b) / inliers.length;
    final variance =
        inliers.fold<double>(0, (s, r) => s + (r - mean) * (r - mean)) /
            inliers.length;
    return (
      scale: mean,
      spread: math.sqrt(variance) / mean,
      inlierFraction: inliers.length / _ratios.length,
    );
  }

  static double _median(List<double> xs) {
    xs.sort();
    final n = xs.length;
    return n.isOdd ? xs[n ~/ 2] : 0.5 * (xs[n ~/ 2 - 1] + xs[n ~/ 2]);
  }

  VibrationSpeedDiagnostics get diagnostics => VibrationSpeedDiagnostics(
        peaks: _peaks,
        calibrationPairs: _ratios.length,
        trusted: trusted,
        applied: _applied,
        rejected: _rejected,
        metresPerCycle: _scale,
        relativeSpread: _relativeSpread,
        last: _last,
      );

  void reset() {
    _samples.clear();
    _ratios.clear();
    _gnss.clear();
    _lastEmitUs = null;
    _peaks = _applied = _rejected = 0;
    _last = null;
  }
}
