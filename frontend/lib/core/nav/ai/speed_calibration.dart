import 'dart:collection';

import 'ai_config.dart';

/// Per-vehicle correction of the neural speed: gnss ≈ scale · model + offset,
/// fitted by least squares over the last [AiConfig.calibrationWindowSamples]
/// pairs the gate graded against GNSS Doppler speed.
///
/// A model trained on other cars reads this one's vibrations with its own
/// scale; this learns that scale while GNSS is healthy, so the outage starts
/// with a speed tuned to the vehicle. The scale is only fitted when the pairs
/// span enough speeds to separate it from the offset; otherwise the offset
/// alone is corrected. A scale outside the configured band is a broken model,
/// not a vehicle, and nothing is corrected.
class SpeedCalibration {
  SpeedCalibration(this._c);

  final AiConfig _c;
  final Queue<({double model, double gnss})> _pairs = Queue();

  double _scale = 1, _offset = 0;
  bool _ready = false;

  double get scale => _scale;
  double get offset => _offset;
  bool get isReady => _ready;
  int get pairs => _pairs.length;

  void add({required double modelMps, required double gnssMps}) {
    if (!modelMps.isFinite || !gnssMps.isFinite) return;
    _pairs.addLast((model: modelMps, gnss: gnssMps));
    while (_pairs.length > _c.calibrationWindowSamples) {
      _pairs.removeFirst();
    }
    _fit();
  }

  /// The corrected speed, or null until the fit is ready and plausible.
  double? apply(double modelMps) {
    if (!_ready) return null;
    final v = _scale * modelMps + _offset;
    return v < 0 ? 0 : v;
  }

  void _fit() {
    final n = _pairs.length;
    _ready = false;
    if (n < _c.calibrationMinSamples) return;
    var mx = 0.0, my = 0.0;
    for (final p in _pairs) {
      mx += p.model;
      my += p.gnss;
    }
    mx /= n;
    my /= n;
    var sxx = 0.0, sxy = 0.0;
    for (final p in _pairs) {
      sxx += (p.model - mx) * (p.model - mx);
      sxy += (p.model - mx) * (p.gnss - my);
    }
    final spread = n > 1 ? (sxx / (n - 1)) : 0.0;
    final spanOk = spread >=
        _c.calibrationMinSpeedSpreadMps * _c.calibrationMinSpeedSpreadMps;
    final scale = spanOk ? sxy / sxx : 1.0;
    if (scale < _c.calibrationScaleMin || scale > _c.calibrationScaleMax) {
      return;
    }
    _scale = scale;
    _offset = my - scale * mx;
    _ready = true;
  }

  void reset() {
    _pairs.clear();
    _scale = 1;
    _offset = 0;
    _ready = false;
  }
}
