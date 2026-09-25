import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import 'sensor_api.dart';

/// The phone's own motion sensors as one frame stream.
///
/// The accelerometer drives the stream at the game rate (~50 Hz); every frame
/// carries the newest gyroscope, magnetometer and barometer values alongside
/// it:
///
/// `[ax, ay, az, gx, gy, gz, tSeconds, mx, my, mz, pressureHpa, pressureAltM]`
///
/// `tSeconds` is the accelerometer event's own timestamp, so a late frame
/// cannot stretch the integration step. The two pressure slots are NaN on a
/// phone without a barometer: nothing here is ever synthesised.
class MobileSensorDriver implements HardwareSensorInterface {
  final StreamController<List<double>> _frames =
      StreamController<List<double>>.broadcast();
  final List<StreamSubscription<Object>> _subscriptions = [];

  var _gyro = const <double>[0, 0, 0];
  var _mag = const <double>[0, 0, 0];
  double _pressure = double.nan;

  @override
  Stream<List<double>> get imuStream => _frames.stream;

  /// Barometric pressure in hPa, NaN until a real reading arrives.
  double get pressureHpa => _pressure;

  /// Standard-atmosphere altitude for [pressureHpa] in metres, or NaN.
  double get pressureAltitudeMeters => altitudeFor(_pressure);

  /// True once the phone has delivered a barometer reading.
  bool get isBarometerActive => !_pressure.isNaN;

  List<double> get latestGyroscope => _gyro;
  List<double> get latestMagnetometer => _mag;

  /// International standard atmosphere, sea level 1013.25 hPa.
  static double altitudeFor(double hpa) => hpa.isNaN
      ? double.nan
      : 44330.0 * (1.0 - math.pow(hpa / 1013.25, 0.190295).toDouble());

  @override
  void start() {
    if (_subscriptions.isNotEmpty) return;
    _subscriptions
      ..add(gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen((e) => _gyro = [e.x, e.y, e.z]))
      ..add(magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .listen((e) => _mag = [e.x, e.y, e.z]));
    _listenToBarometer();
    _subscriptions.add(
      accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen(_emit),
    );
  }

  void _emit(AccelerometerEvent e) {
    _frames.add([
      e.x,
      e.y,
      e.z,
      ..._gyro,
      e.timestamp.microsecondsSinceEpoch / 1e6,
      ..._mag,
      _pressure,
      altitudeFor(_pressure),
    ]);
  }

  /// A slow rate is plenty for pressure. A phone (or platform) without a
  /// barometer errors here, which simply leaves the pressure slots NaN.
  void _listenToBarometer() {
    try {
      _subscriptions.add(
        barometerEventStream(samplingPeriod: SensorInterval.normalInterval)
            .listen(
          (e) => _pressure = e.pressure,
          onError: (Object _) => _pressure = double.nan,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      _pressure = double.nan;
    }
  }

  @override
  void stop() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> dispose() async {
    stop();
    await _frames.close();
  }
}
