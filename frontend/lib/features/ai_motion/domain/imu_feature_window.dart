import 'dart:math' as math;

/// The 10 Hz, 13-feature, 20-frame window every on-device model reads
/// (`assets/models/model_metadata.json`, v3.1.0): the speed model, the vibration
/// classifier and the motion-quality model share one contract, so they share
/// this class.
///
/// A frame is `[ax, ay, az, gx, gy, gz, |a|, |g|, dax, day, daz, pitch, roll]`
/// in m/s^2, rad/s and rad, standardised with the training scaler. The
/// accelerometer is raw and **includes gravity**: feeding gravity-free data puts
/// the inputs ~75 sigma off-distribution, which [zMax] reports.
///
/// Pure Dart: no plugin, so the feature maths is unit-tested without a model.
class ImuFeatureWindow {
  static const int size = 20;
  static const int features = 13;

  /// Training-set standardisation, copied from `model_metadata.json`.
  static const List<double> mean = [
    0.025551723003058698,
    -0.0020532023982209016,
    9.84194598932291,
    -7.826907205868139e-05,
    -0.00039615690684135206,
    -0.0026302214894134766,
    9.99735125146164,
    0.17996862653960716,
    1.7051794866907978e-05,
    -0.00017159758674403617,
    5.7487940119835076e-05,
    0.0023125885838363247,
    4.4687576375297487e-05,
  ];

  static const List<double> scale = [
    1.1891239803207685,
    1.3138450122802776,
    0.5332384856869221,
    0.12450962361199933,
    0.08538335667218527,
    0.21558705612300488,
    0.5848707088712776,
    0.19206539860633634,
    9.773291883009323,
    11.6980522619145,
    4.961310545372281,
    0.11615898590782375,
    0.13036863357032644,
  ];

  final List<List<double>> _frames = [];
  double _lastAx = 0;
  double _lastAy = 0;
  double _lastAz = 9.81;
  int _fed = 0;

  /// The standardised frames, oldest first, at most [size].
  List<List<double>> get frames => List.unmodifiable(_frames);
  int get length => _frames.length;

  /// Frames fed since the window was created or last [reset]: the "windows
  /// fed" the AI speed gate's warm-up counts.
  int get fed => _fed;

  /// The largest |z-score| of any feature in any frame of the window: how far
  /// the newest input sits from what the models were trained on. Zero when
  /// empty.
  double get zMax {
    var worst = 0.0;
    for (final frame in _frames) {
      for (final z in frame) {
        worst = math.max(worst, z.abs());
      }
    }
    return worst;
  }

  void reset() {
    _frames.clear();
    _lastAx = 0;
    _lastAy = 0;
    _lastAz = 9.81;
    _fed = 0;
  }

  /// Adds one 10 Hz frame and returns its standardised feature vector.
  List<double> add({
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required double pitch,
    required double roll,
  }) {
    final raw = [
      ax,
      ay,
      az,
      gx,
      gy,
      gz,
      math.sqrt(ax * ax + ay * ay + az * az),
      math.sqrt(gx * gx + gy * gy + gz * gz),
      _fed == 0 ? 0.0 : (ax - _lastAx) / 0.1,
      _fed == 0 ? 0.0 : (ay - _lastAy) / 0.1,
      _fed == 0 ? 0.0 : (az - _lastAz) / 0.1,
      math.atan2(ax, math.sqrt(ay * ay + az * az)),
      math.atan2(ay, az),
    ];
    _lastAx = ax;
    _lastAy = ay;
    _lastAz = az;
    final frame = List<double>.generate(features, (i) {
      final s = scale[i] == 0 ? 1.0 : scale[i];
      return (raw[i] - mean[i]) / s;
    });
    _frames.add(frame);
    if (_frames.length > size) _frames.removeAt(0);
    _fed++;
    return frame;
  }

  /// Un-standardises one feature of one frame back to physical units.
  static double physical(List<double> frame, int feature) =>
      frame[feature] * scale[feature] + mean[feature];
}
