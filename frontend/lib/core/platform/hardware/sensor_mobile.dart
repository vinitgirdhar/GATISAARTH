import 'sensor_api.dart';
import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

/// Physical multi-sensor driver:
/// - Accelerometer (50 Hz), gyroscope and magnetometer (~15 Hz, latest value held)
/// - Barometer, only if the phone actually has one (never synthesised)
///
/// Each emitted frame is
/// `[ax, ay, az, gx, gy, gz, tSeconds, mx, my, mz, pressureHpa, pressureAltM]`.
/// The last two are [double.nan] when the phone has no barometer.
class MobileSensorDriver implements HardwareSensorInterface {
  final StreamController<List<double>> _imuController =
      StreamController.broadcast();
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<BarometerEvent>? _barometerSubscription;

  List<double> _latestGyroscope = const [0.0, 0.0, 0.0];
  List<double> _latestMagnetometer = const [0.0, 0.0, 0.0];
  double _pressureHpa = double.nan;
  bool _barometerActive = false;

  @override
  Stream<List<double>> get imuStream => _imuController.stream;

  /// Real barometric pressure in hPa, or NaN if the phone has no barometer.
  double get pressureHpa => _pressureHpa;

  /// Pressure altitude (standard atmosphere) in metres, or NaN.
  double get pressureAltitudeMeters => _pressureAltitude(_pressureHpa);

  /// True only once a real barometer reading has arrived.
  bool get isBarometerActive => _barometerActive;
  List<double> get latestMagnetometer => _latestMagnetometer;
  List<double> get latestGyroscope => _latestGyroscope;

  static double _pressureAltitude(double hpa) =>
      hpa.isNaN ? double.nan : 44330.0 * (1.0 - pow(hpa / 1013.25, 1 / 5.255));

  @override
  void start() {
    if (_accelerometerSubscription != null) return;

    // Gyro and magnetometer are sampled by the 10 Hz model and a smoothed
    // compass, so 15 Hz is plenty; only the accelerometer drives 50 Hz frames.
    _gyroscopeSubscription = gyroscopeEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      _latestGyroscope = [event.x, event.y, event.z];
    });

    _magnetometerSubscription = magnetometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      _latestMagnetometer = [event.x, event.y, event.z];
    });

    _startBarometer();

    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      _imuController.add([
        event.x,
        event.y,
        event.z,
        ..._latestGyroscope,
        // Hardware event time, so a janky frame cannot distort integration.
        event.timestamp.microsecondsSinceEpoch / 1000000,
        ..._latestMagnetometer,
        _pressureHpa,
        _pressureAltitude(_pressureHpa),
      ]);
    });
  }

  /// Slow rate is plenty for pressure and keeps the sensor hub idle. Phones
  /// without a barometer (and platforms without the API) simply report none.
  void _startBarometer() {
    try {
      _barometerSubscription = barometerEventStream(
        samplingPeriod: SensorInterval.normalInterval,
      ).listen(
        (event) {
          _pressureHpa = event.pressure;
          _barometerActive = true;
        },
        onError: (Object _) {
          _pressureHpa = double.nan;
          _barometerActive = false;
        },
        cancelOnError: true,
      );
    } catch (_) {
      _barometerActive = false;
    }
  }

  @override
  void stop() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _barometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _magnetometerSubscription = null;
    _barometerSubscription = null;
  }

  Future<void> dispose() async {
    stop();
    await _imuController.close();
  }
}
