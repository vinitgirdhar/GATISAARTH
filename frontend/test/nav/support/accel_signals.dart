import 'dart:math' as math;

import 'package:gatisaarth/core/nav/math/nav_math.dart';

/// One accelerometer sample: the engine's monotonic clock and the phone-frame
/// specific force.
typedef AccelSample = ({int us, Vector3 accel});

/// A phone-frame accelerometer stream for a vehicle whose "up" axis sits at an
/// arbitrary tilt in the phone: gravity, uniform sensor noise (the simulator's
/// own model) and whatever [extra] adds. The estimator under test is mount
/// agnostic, so tests run the same physics through more than one [up].
List<AccelSample> synthAccel({
  required double seconds,
  int hz = 50,
  Vector3? up,
  double noise = 0.04,
  int seed = 1,
  int startUs = 1000000,
  Vector3 Function(int i, double t)? extra,
}) {
  final upUnit = (up ?? Vector3(0.3, 2.0, 9.6)).normalized();
  final rng = math.Random(seed);
  final n = (seconds * hz).round();
  final dtUs = 1000000 ~/ hz;
  double jitter() => noise == 0 ? 0 : (rng.nextDouble() - 0.5) * 2 * noise;
  return [
    for (var i = 0; i < n; i++)
      (
        us: startUs + i * dtUs,
        accel: upUnit * NavMath.gravity +
            (extra?.call(i, i / hz) ?? Vector3.zero()) +
            Vector3(jitter(), jitter(), jitter()),
      ),
  ];
}

/// A Gaussian sample from [rng] (Box-Muller), for broadband road noise.
double gaussian(math.Random rng) {
  final u1 = 1 - rng.nextDouble();
  final u2 = rng.nextDouble();
  return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
}

/// Two unit vectors perpendicular to [up] and to each other, for building
/// horizontal disturbances without assuming which way the phone points.
(Vector3, Vector3) horizontalAxes(Vector3 up) {
  final u = up.normalized();
  final seed = u.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
  final a = u.cross(seed).normalized();
  final b = u.cross(a).normalized();
  return (a, b);
}
