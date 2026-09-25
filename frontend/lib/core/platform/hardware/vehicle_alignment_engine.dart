import 'dart:math' as math;

/// What the phone rides in. Chooses the motion constraints the navigation core
/// applies (a car cannot slide sideways, a bike leans, a walker does neither).
enum VehicleProfile { car, twoWheeler, pedestrian }

/// Tilt of the phone in its mount, for the recording metadata and the Sensors
/// tab. The navigation core does its own, full mount alignment
/// (`core/nav/alignment/mount_alignment.dart`); this only reports how the phone
/// leans relative to gravity.
///
/// Gravity is tracked with a slow exponential average of the accelerometer, so
/// braking or a pothole barely moves it while a re-seated phone is followed
/// within a few seconds.
class VehicleAlignmentEngine {
  VehicleAlignmentEngine({this.smoothing = 0.02, this.warmUpSamples = 10});

  /// Weight of each new sample in the gravity average (0..1).
  final double smoothing;

  /// Samples needed before the tilt is reported as known.
  final int warmUpSamples;

  VehicleProfile vehicleProfile = VehicleProfile.car;

  double _gx = 0, _gy = 0, _gz = 9.81;
  int _samples = 0;

  /// Phone pitch, radians (nose up is positive).
  double get pitch => math.atan2(-_gx, math.sqrt(_gy * _gy + _gz * _gz));

  /// Phone roll, radians (right side down is positive).
  double get roll => math.atan2(_gy, _gz);

  /// True once enough samples have been seen for [pitch] and [roll] to mean
  /// anything.
  bool get isCalibrated => _samples > warmUpSamples;

  /// Feeds one raw accelerometer sample (m/s², gravity included).
  void addAccelerometer(double ax, double ay, double az) {
    _gx += smoothing * (ax - _gx);
    _gy += smoothing * (ay - _gy);
    _gz += smoothing * (az - _gz);
    _samples++;
  }
}
