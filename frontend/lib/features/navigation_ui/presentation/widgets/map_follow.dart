import 'dart:math' as math;

/// What the camera does with the vehicle.
enum FollowMode {
  /// The user moved the map; it stays where they put it.
  free,

  /// The vehicle stays centred, north is up.
  north,

  /// The vehicle sits low on the screen and the map turns so its heading is up.
  heading,
}

/// Zoom levels of the map. The basemap is drawn from 512 px vector tiles, so a
/// zoom here reads about like the same number on a MapLibre map plus one.
class MapZoom {
  const MapZoom._();

  static const double min = 3;
  static const double max = 20;

  /// Street level: roads, names and junctions readable. Where the map opens
  /// and where "recentre" returns to when the vehicle is slow.
  static const double street = 17.4;

  /// Region overview, for the Offline Maps preview.
  static const double overview = 9;
}

/// Zoom that suits the speed: close in when crawling or parked so junctions are
/// readable, wider as speed rises so there is road ahead to look at.
double autoZoomForSpeed(double metresPerSecond) {
  const stops = <(double, double)>[
    (0.0, 17.6),
    (5.0, 17.3),
    (12.0, 16.6),
    (20.0, 16.0),
    (30.0, 15.4),
  ];
  final speed = metresPerSecond.isFinite ? metresPerSecond : 0.0;
  if (speed <= stops.first.$1) return stops.first.$2;
  for (var i = 1; i < stops.length; i++) {
    final (s1, z1) = stops[i];
    if (speed <= s1) {
      final (s0, z0) = stops[i - 1];
      return z0 + (z1 - z0) * (speed - s0) / (s1 - s0);
    }
  }
  return stops.last.$2;
}

/// Smallest signed turn from [from] to [to], in degrees, in (-180, 180].
double shortestAngleDelta(double from, double to) {
  var delta = (to - from) % 360;
  if (delta > 180) delta -= 360;
  if (delta <= -180) delta += 360;
  return delta;
}

/// How far below the map's centre the vehicle sits when the map turns with it:
/// low enough to see well ahead, high enough to keep the puck clear of the
/// bottom sheet.
double headingLookaheadPx(double mapHeightPx) => mapHeightPx * 0.2;

/// A value that eases toward a target instead of jumping, independent of the
/// frame rate: after time `tau` it has covered 63 % of the remaining distance,
/// however that time is sliced into frames.
class Ease {
  Ease(this.value, {required this.tau, this.epsilon = 1e-4})
      : assert(tau > 0),
        target = value;

  double value;
  double target;

  /// Time constant in seconds.
  final double tau;

  /// Closer than this counts as arrived.
  final double epsilon;

  bool get settled => (target - value).abs() <= epsilon;

  /// Jumps straight to the target (a teleport, or the first fix).
  void snap() => value = target;

  /// Advances by [dtSeconds]. Returns whether it is still moving.
  bool step(double dtSeconds) {
    if (settled) {
      value = target;
      return false;
    }
    final k = 1 - math.exp(-math.max(0, dtSeconds) / tau);
    value += (target - value) * k;
    if (settled) {
      value = target;
      return false;
    }
    return true;
  }
}

/// [Ease] for an angle in degrees: always turns the short way round, and
/// [aim]ing at 10 degrees from 350 goes 20 degrees forward, not 340 back.
class AngleEase extends Ease {
  AngleEase(super.value, {required super.tau, super.epsilon = 0.02});

  void aim(double degrees) {
    target = value + shortestAngleDelta(value, degrees);
  }
}
