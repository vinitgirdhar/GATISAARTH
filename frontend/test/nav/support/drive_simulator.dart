import 'dart:math' as math;

import 'package:gatisaarth/core/nav/gnss/gnss_quality.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';

/// Where the phone sits, as the vehicle axes seen in phone coordinates.
class PhoneMount {
  const PhoneMount({required this.forward, required this.down});

  /// Flat on the dashboard, top pointing at the windscreen.
  factory PhoneMount.flatTopForward() =>
      PhoneMount(forward: Vector3(0, 1, 0), down: Vector3(0, 0, -1));

  /// Rotated [yawDeg] in its cradle and tilted [tiltDeg] back from flat — the
  /// realistic case the old pitch/roll-only alignment could not handle.
  factory PhoneMount.tilted({double yawDeg = 35, double tiltDeg = 20}) {
    final tilt = tiltDeg * NavMath.degToRad;
    final yaw = yawDeg * NavMath.degToRad;
    final down = Vector3(0, -math.sin(tilt), -math.cos(tilt)).normalized();
    final flatForward =
        Vector3(0, math.cos(tilt), -math.sin(tilt)).normalized();
    final right = down.cross(flatForward).normalized();
    final forward =
        (flatForward * math.cos(yaw) + right * math.sin(yaw)).normalized();
    return PhoneMount(forward: forward, down: down);
  }

  final Vector3 forward;
  final Vector3 down;

  Vector3 get right => down.cross(forward).normalized();

  /// Converts a vehicle-frame vector into phone coordinates.
  Vector3 toPhone(Vector3 vehicle) =>
      forward * vehicle.x + right * vehicle.y + down * vehicle.z;
}

/// One simulated instant of ground truth.
class TruthSample {
  const TruthSample({
    required this.monotonicUs,
    required this.latitude,
    required this.longitude,
    required this.headingRad,
    required this.speedMps,
    required this.distanceM,
  });

  final int monotonicUs;
  final double latitude;
  final double longitude;
  final double headingRad;
  final double speedMps;
  final double distanceM;
}

/// One simulated IMU frame in the phone frame, plus its truth.
class SimulatedImu {
  const SimulatedImu({
    required this.accelPhone,
    required this.gyroPhone,
    required this.truth,
  });

  final Vector3 accelPhone;
  final Vector3 gyroPhone;
  final TruthSample truth;
}

/// A segment of driving: how hard to accelerate and how fast to turn.
class DriveSegment {
  const DriveSegment({
    required this.seconds,
    this.longitudinalAccel = 0,
    this.yawRate = 0,
  });

  final double seconds;
  final double longitudinalAccel; // m/s²
  final double yawRate; // rad/s
}

/// Generates a synthetic drive with ground truth, phone-frame IMU and GNSS.
///
/// Everything a phone would measure is derived from the same truth, so the
/// engine's output can be scored against it (§39). Sensor error is explicit:
/// biases and noise are parameters, not accidents of the generator.
class DriveSimulator {
  DriveSimulator({
    required this.mount,
    this.startLat = 28.6139,
    this.startLon = 77.2090,
    this.startHeadingRad = 0,
    this.imuHz = 50,
    this.accelBias = const [0.08, -0.05, 0.06],
    this.gyroBias = const [0.002, -0.001, 0.004],
    this.accelNoise = 0.04,
    this.gyroNoise = 0.002,
    this.gnssAccuracy = 5,
    this.gnssNoise = 2.5,
    this.wheelVibration = 0,
    this.wheelRadiusM = 0.31,
    int seed = 42,
  }) : _rng = math.Random(seed);

  final PhoneMount mount;
  final double startLat;
  final double startLon;
  final double startHeadingRad;
  final int imuHz;

  /// Constant sensor errors the engine has to live with.
  final List<double> accelBias;
  final List<double> gyroBias;
  final double accelNoise;
  final double gyroNoise;

  final double gnssAccuracy;
  final double gnssNoise;

  /// Vertical shake at the wheel-rotation rate, m/s² amplitude (0 = none):
  /// what a real tyre does to the car body, for the vibration speedometer.
  final double wheelVibration;
  final double wheelRadiusM;
  double _wheelPhase = 0;

  final math.Random _rng;

  double _lat = 0;
  double _lon = 0;
  double _heading = 0;
  double _speed = 0;
  double _distance = 0;
  int _us = 0;
  bool _started = false;

  TruthSample get truth => TruthSample(
        monotonicUs: _us,
        latitude: _lat,
        longitude: _lon,
        headingRad: _heading,
        speedMps: _speed,
        distanceM: _distance,
      );

  void _ensureStarted() {
    if (_started) return;
    _started = true;
    _lat = startLat;
    _lon = startLon;
    _heading = startHeadingRad;
  }

  /// Advances the truth by one IMU period and returns what the phone measures.
  SimulatedImu step(DriveSegment segment) {
    _ensureStarted();
    final dt = 1 / imuHz;
    _us += (dt * 1e6).round();

    final previousSpeed = _speed;
    _speed = math.max(0.0, _speed + segment.longitudinalAccel * dt);
    // A stopped vehicle does not turn.
    final yawRate = _speed < 0.2 ? 0.0 : segment.yawRate;
    _heading = NavMath.wrapPi(_heading + yawRate * dt);

    final meanSpeed = 0.5 * (previousSpeed + _speed);
    final travelled = meanSpeed * dt;
    _distance += travelled;
    final moved = NavMath.addNed(
      latDeg: _lat,
      lonDeg: _lon,
      altM: 0,
      north: travelled * math.cos(_heading),
      east: travelled * math.sin(_heading),
      down: 0,
    );
    _lat = moved[0];
    _lon = moved[1];

    // Specific force in the vehicle frame. Centripetal acceleration shows up
    // on the lateral axis exactly as it does in a real vehicle.
    final actualLongitudinal =
        _speed <= 0 && segment.longitudinalAccel < 0 ? 0.0 : segment.longitudinalAccel;
    _wheelPhase += _speed / wheelRadiusM * dt;
    final specificVehicle = Vector3(
      actualLongitudinal,
      _speed * yawRate,
      -NavMath.gravity + wheelVibration * math.sin(_wheelPhase),
    );
    final gyroVehicle = Vector3(0, 0, yawRate);

    return SimulatedImu(
      accelPhone: mount.toPhone(specificVehicle) +
          Vector3(
            accelBias[0] + _noise(accelNoise),
            accelBias[1] + _noise(accelNoise),
            accelBias[2] + _noise(accelNoise),
          ),
      gyroPhone: mount.toPhone(gyroVehicle) +
          Vector3(
            gyroBias[0] + _noise(gyroNoise),
            gyroBias[1] + _noise(gyroNoise),
            gyroBias[2] + _noise(gyroNoise),
          ),
      truth: truth,
    );
  }

  /// A GNSS fix for the current truth, with realistic noise.
  GnssObservation gnss() {
    final offset = NavMath.addNed(
      latDeg: _lat,
      lonDeg: _lon,
      altM: 0,
      north: _noise(gnssNoise),
      east: _noise(gnssNoise),
      down: 0,
    );
    return GnssObservation(
      latitudeDeg: offset[0],
      longitudeDeg: offset[1],
      accuracyM: gnssAccuracy,
      monotonicUs: _us,
      altitudeM: 0,
      speedMps: math.max(0.0, _speed + _noise(0.3)),
      speedAccuracyMps: 0.5,
      bearingDeg: _speed > 1
          ? NavMath.wrap360(_heading * NavMath.radToDeg)
          : null,
    );
  }

  double _noise(double scale) =>
      scale == 0 ? 0 : (_rng.nextDouble() - 0.5) * 2 * scale;
}

/// A calibration-drive profile: repeated acceleration and braking on a
/// straight road, which is what the mount alignment needs (§6).
List<DriveSegment> calibrationDrive({int cycles = 14}) => [
      const DriveSegment(seconds: 3),
      for (var i = 0; i < cycles; i++) ...[
        const DriveSegment(seconds: 4, longitudinalAccel: 1.8),
        const DriveSegment(seconds: 1),
        const DriveSegment(seconds: 4, longitudinalAccel: -1.8),
        const DriveSegment(seconds: 1),
      ],
    ];
