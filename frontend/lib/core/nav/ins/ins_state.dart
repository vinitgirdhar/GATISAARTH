import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';

/// The nominal navigation state the strapdown mechanization propagates (§10).
///
/// Immutable: every propagation and every filter correction produces a new
/// state, so a replay can hold on to intermediate states and a bug cannot
/// mutate one out from under an observer.
@immutable
class InsState {
  const InsState({
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.altitudeM,
    required this.velocityNed,
    required this.qBodyToNav,
    required this.accelBias,
    required this.gyroBias,
    required this.timestampUs,
  });

  /// Seeds a state at a position with a known heading and no motion.
  factory InsState.seeded({
    required double latitudeDeg,
    required double longitudeDeg,
    double altitudeM = 0,
    double headingRad = 0,
    Vector3? gravityBody,
    int timestampUs = 0,
  }) =>
      InsState(
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
        altitudeM: altitudeM,
        velocityNed: Vector3.zero(),
        qBodyToNav: gravityBody == null
            ? NavMath.quaternionFromEuler(roll: 0, pitch: 0, yaw: headingRad)
            : NavMath.levelledAttitude(
                gravityBody: gravityBody,
                headingRad: headingRad,
              ),
        accelBias: Vector3.zero(),
        gyroBias: Vector3.zero(),
        timestampUs: timestampUs,
      );

  final double latitudeDeg;
  final double longitudeDeg;
  final double altitudeM;

  /// Velocity in the navigation frame: north, east, down (m/s).
  final Vector3 velocityNed;

  /// Attitude, body to navigation frame.
  final Quaternion qBodyToNav;

  /// Estimated sensor biases in the body frame.
  final Vector3 accelBias;
  final Vector3 gyroBias;

  final int timestampUs;

  /// Ground speed (m/s), horizontal only — the number a driver reads.
  double get groundSpeed =>
      Vector3(velocityNed.x, velocityNed.y, 0).length;

  /// Heading of travel (deg, 0 = North) when moving, else the attitude's own
  /// heading. Below walking pace a velocity vector is mostly noise.
  double get headingDeg {
    if (groundSpeed > 0.8) {
      return NavMath.wrap360(
        NavMath.radToDeg * math.atan2(velocityNed.y, velocityNed.x),
      );
    }
    return NavMath.wrap360(
      NavMath.radToDeg * NavMath.headingFromQuaternion(qBodyToNav),
    );
  }

  /// Vertical rate, positive upwards (m/s).
  double get climbRate => -velocityNed.z;

  /// Velocity expressed in the body (vehicle) frame: forward, right, down.
  Vector3 get velocityBody =>
      NavMath.rotateNavToBody(qBodyToNav, velocityNed);

  bool get isFinite =>
      latitudeDeg.isFinite &&
      longitudeDeg.isFinite &&
      altitudeM.isFinite &&
      velocityNed.x.isFinite &&
      velocityNed.y.isFinite &&
      velocityNed.z.isFinite &&
      qBodyToNav.x.isFinite &&
      qBodyToNav.y.isFinite &&
      qBodyToNav.z.isFinite &&
      qBodyToNav.w.isFinite &&
      accelBias.x.isFinite &&
      accelBias.y.isFinite &&
      accelBias.z.isFinite &&
      gyroBias.x.isFinite &&
      gyroBias.y.isFinite &&
      gyroBias.z.isFinite;

  InsState copyWith({
    double? latitudeDeg,
    double? longitudeDeg,
    double? altitudeM,
    Vector3? velocityNed,
    Quaternion? qBodyToNav,
    Vector3? accelBias,
    Vector3? gyroBias,
    int? timestampUs,
  }) =>
      InsState(
        latitudeDeg: latitudeDeg ?? this.latitudeDeg,
        longitudeDeg: longitudeDeg ?? this.longitudeDeg,
        altitudeM: altitudeM ?? this.altitudeM,
        velocityNed: velocityNed ?? this.velocityNed.clone(),
        qBodyToNav: qBodyToNav ?? this.qBodyToNav.clone(),
        accelBias: accelBias ?? this.accelBias.clone(),
        gyroBias: gyroBias ?? this.gyroBias.clone(),
        timestampUs: timestampUs ?? this.timestampUs,
      );

  @override
  String toString() => 'InsState(${latitudeDeg.toStringAsFixed(6)}, '
      '${longitudeDeg.toStringAsFixed(6)}, ${altitudeM.toStringAsFixed(1)}m, '
      'v=${groundSpeed.toStringAsFixed(2)}m/s, '
      'hdg=${headingDeg.toStringAsFixed(1)}°)';
}
