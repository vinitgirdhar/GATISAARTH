import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'matrix.dart';

export 'package:vector_math/vector_math_64.dart' show Vector3, Matrix3, Quaternion;

/// Frame and attitude maths for the navigation core.
///
/// Conventions, fixed once here so nothing downstream has to guess:
/// * Navigation frame is **NED** — x North, y East, z Down.
/// * Body frame is the *vehicle* frame after alignment — x forward, y right,
///   z down.
/// * `qBodyToNav` rotates a body-frame vector into the nav frame. Use
///   [rotateBodyToNav] / [rotateNavToBody] — **never** `Quaternion.rotate` or
///   `rotated`, which in `vector_math` apply the *opposite* sense to the
///   matrix the same quaternion's `asRotationMatrix()` produces. Pinning the
///   convention here is what stops that inconsistency leaking into the filter.
class NavMath {
  const NavMath._();

  /// WGS84 semi-major axis (m).
  static const double earthA = 6378137.0;
  static const double earthF = 1 / 298.257223563;
  static final double earthE2 = earthF * (2 - earthF);

  /// Standard gravity (m/s²). Latitude-dependent gravity is a <0.3 % effect,
  /// far below the accelerometer bias this filter estimates.
  static const double gravity = 9.80665;

  static const double degToRad = math.pi / 180.0;
  static const double radToDeg = 180.0 / math.pi;

  // ------------------------------------------------------------------ frames

  /// Skew-symmetric matrix `[v x]` such that `[v x] * u == v.cross(u)`.
  static Matrix3 skew(Vector3 v) => Matrix3(
        0, v.z, -v.y, //
        -v.z, 0, v.x, //
        v.y, -v.x, 0,
      );

  /// Direction-cosine matrix for [q] (body to nav).
  static Matrix3 rotationMatrix(Quaternion q) => q.asRotationMatrix();

  /// Rotates a body-frame vector into the navigation frame.
  static Vector3 rotateBodyToNav(Quaternion q, Vector3 v) {
    final Vector3 out = q.asRotationMatrix() * v;
    return out;
  }

  /// Rotates a navigation-frame vector into the body frame.
  static Vector3 rotateNavToBody(Quaternion q, Vector3 v) {
    final Vector3 out = q.asRotationMatrix().transposed() * v;
    return out;
  }

  /// Quaternion increment for a rotation-vector [rv] (rad), exact for large
  /// angles and numerically safe as the angle goes to zero.
  static Quaternion quaternionFromRotationVector(Vector3 rv) {
    final angle = rv.length;
    if (angle < 1e-12) {
      // Second-order small-angle form; normalising afterwards keeps it unit.
      return Quaternion(rv.x * 0.5, rv.y * 0.5, rv.z * 0.5, 1.0)..normalize();
    }
    final half = angle * 0.5;
    final s = math.sin(half) / angle;
    return Quaternion(rv.x * s, rv.y * s, rv.z * s, math.cos(half))
      ..normalize();
  }

  /// Applies a small nav-frame attitude error [delta] (rad) to [q].
  ///
  /// The error state is defined in the navigation frame, so the correction
  /// left-multiplies: `q' = δq ⊗ q`.
  static Quaternion applyNavFrameError(Quaternion q, Vector3 delta) {
    final corrected = quaternionFromRotationVector(delta) * q;
    corrected.normalize();
    return corrected;
  }

  /// Propagates [q] by a body-frame angular rate [omegaBody] (rad/s) over [dt].
  ///
  /// Body-frame increments right-multiply: `q' = q ⊗ δq`.
  static Quaternion propagate(Quaternion q, Vector3 omegaBody, double dt) {
    final next = q * quaternionFromRotationVector(omegaBody * dt);
    next.normalize();
    return next;
  }

  /// Attitude with x forward, z down, from a measured gravity vector in body
  /// coordinates and a heading. Used to seed the filter before motion gives a
  /// yaw observation.
  static Quaternion levelledAttitude({
    required Vector3 gravityBody,
    required double headingRad,
  }) {
    final g = gravityBody.length < 1e-6
        ? Vector3(0, 0, gravity)
        : gravityBody.normalized() * gravity;
    // A phone at rest measures +g along its own "up"; the nav-frame down axis
    // is therefore -g_measured normalised.
    final roll = math.atan2(-g.y, -g.z);
    final pitch = math.atan2(g.x, math.sqrt(g.y * g.y + g.z * g.z));
    return quaternionFromEuler(roll: roll, pitch: pitch, yaw: headingRad);
  }

  /// Z-Y-X (yaw, then pitch, then roll) Euler angles to a body-to-nav
  /// quaternion.
  static Quaternion quaternionFromEuler({
    required double roll,
    required double pitch,
    required double yaw,
  }) {
    final cr = math.cos(roll * 0.5), sr = math.sin(roll * 0.5);
    final cp = math.cos(pitch * 0.5), sp = math.sin(pitch * 0.5);
    final cy = math.cos(yaw * 0.5), sy = math.sin(yaw * 0.5);
    return Quaternion(
      sr * cp * cy - cr * sp * sy,
      cr * sp * cy + sr * cp * sy,
      cr * cp * sy - sr * sp * cy,
      cr * cp * cy + sr * sp * sy,
    )..normalize();
  }

  /// Roll, pitch, yaw (rad) of [q], in that list order.
  static List<double> eulerFromQuaternion(Quaternion q) {
    final x = q.x, y = q.y, z = q.z, w = q.w;
    final sinP = (2 * (w * y - z * x)).clamp(-1.0, 1.0);
    return [
      math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y)),
      math.asin(sinP),
      math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)),
    ];
  }

  /// Heading of the body x-axis (rad, 0 = North, clockwise positive).
  static double headingFromQuaternion(Quaternion q) {
    final c = rotationMatrix(q);
    return math.atan2(c.entry(1, 0), c.entry(0, 0));
  }

  /// Wraps [rad] to (-π, π].
  static double wrapPi(double rad) {
    var v = rad % (2 * math.pi);
    if (v > math.pi) v -= 2 * math.pi;
    if (v <= -math.pi) v += 2 * math.pi;
    return v;
  }

  /// Wraps [deg] to [0, 360).
  static double wrap360(double deg) {
    final v = deg % 360;
    return v < 0 ? v + 360 : v;
  }

  /// Signed smallest difference `a - b` in degrees, in (-180, 180].
  static double angleDiffDeg(double a, double b) =>
      wrapPi((a - b) * degToRad) * radToDeg;

  // ----------------------------------------------------------- magnetometer

  /// Yaw error (rad) implied by a magnetometer reading.
  ///
  /// Rotates the body-frame field [magBody] into the nav frame with the current
  /// attitude [q]; whatever horizontal bearing it lands on *should* be magnetic
  /// north, so the offset from north is the attitude's yaw error. Returns null
  /// when the horizontal component is too small to give a bearing (phone
  /// pointing along the field, or a dead magnetometer).
  static double? magneticYawError({
    required Quaternion q,
    required Vector3 magBody,
    double declinationRad = 0,
  }) {
    if (magBody.length2 < 1e-6) return null;
    final Vector3 navField = rotateBodyToNav(q, magBody);
    final horizontal =
        math.sqrt(navField.x * navField.x + navField.y * navField.y);
    // Near the magnetic poles — or with the field almost along the vertical —
    // the horizontal bearing is meaningless.
    if (horizontal < 0.2 * magBody.length) return null;
    return wrapPi(math.atan2(navField.y, navField.x) - declinationRad);
  }

  // --------------------------------------------------------------- geodesy

  /// Meridian radius of curvature (m) at [latRad].
  static double meridianRadius(double latRad) {
    final s = math.sin(latRad);
    final t = 1 - earthE2 * s * s;
    return earthA * (1 - earthE2) / (t * math.sqrt(t));
  }

  /// Prime-vertical radius of curvature (m) at [latRad].
  static double normalRadius(double latRad) {
    final s = math.sin(latRad);
    return earthA / math.sqrt(1 - earthE2 * s * s);
  }

  /// Advances a geodetic position by a local NED displacement (m).
  ///
  /// Replaces the flat-earth `111000 m/deg` approximation: at 28° N that
  /// constant is ~0.3 % long in latitude, which is 3 m per kilometre of
  /// dead reckoning before any sensor error is counted.
  static List<double> addNed({
    required double latDeg,
    required double lonDeg,
    required double altM,
    required double north,
    required double east,
    required double down,
  }) {
    final latRad = latDeg * degToRad;
    final m = meridianRadius(latRad) + altM;
    final n = (normalRadius(latRad) + altM) * math.cos(latRad);
    final newLat = latDeg + (north / m) * radToDeg;
    // Beyond the poles the longitude step is undefined; clamp instead of
    // dividing by ~0.
    final newLon = n.abs() < 1e-3 ? lonDeg : lonDeg + (east / n) * radToDeg;
    return [newLat, newLon, altM - down];
  }

  /// Local NED displacement (m) from (`lat0`,`lon0`,`alt0`) to
  /// (`lat1`,`lon1`,`alt1`). Valid for the short baselines a filter update
  /// sees (metres to kilometres).
  static Vector3 nedBetween({
    required double lat0,
    required double lon0,
    required double alt0,
    required double lat1,
    required double lon1,
    required double alt1,
  }) {
    final latRad = lat0 * degToRad;
    final m = meridianRadius(latRad) + alt0;
    final n = (normalRadius(latRad) + alt0) * math.cos(latRad);
    return Vector3(
      (lat1 - lat0) * degToRad * m,
      wrapPi((lon1 - lon0) * degToRad) * n,
      -(alt1 - alt0),
    );
  }

  /// Great-circle-ish horizontal distance (m) between two positions.
  static double horizontalDistance({
    required double lat0,
    required double lon0,
    required double lat1,
    required double lon1,
  }) {
    final d = nedBetween(
      lat0: lat0,
      lon0: lon0,
      alt0: 0,
      lat1: lat1,
      lon1: lon1,
      alt1: 0,
    );
    return math.sqrt(d.x * d.x + d.y * d.y);
  }

  // ----------------------------------------------------------- filter maths

  /// Normalised innovation squared, `rᵀ S⁻¹ r`.
  ///
  /// Returns null when `S` cannot be inverted — the caller must then skip the
  /// update rather than gate on a NaN.
  static double? nis(Matrix residual, Matrix innovationCov) {
    final inv = innovationCov.inverse();
    if (inv == null) return null;
    final v = (residual.transposed * inv * residual).at(0, 0);
    return v.isFinite ? v : null;
  }

  /// 99th-percentile chi-square thresholds for 1..6 degrees of freedom, used
  /// as measurement-gate limits (§14).
  static const List<double> chiSquare99 = [
    0, 6.635, 9.210, 11.345, 13.277, 15.086, 16.812,
  ];

  /// 1-sigma horizontal radius (m) from a 2x2 position covariance block —
  /// the semi-major axis of the error ellipse.
  static double horizontalSigma(double pNN, double pNE, double pEE) {
    final tr = pNN + pEE;
    final diff = pNN - pEE;
    final disc = math.sqrt(math.max(0.0, diff * diff + 4 * pNE * pNE));
    return math.sqrt(math.max(0.0, 0.5 * (tr + disc)));
  }
}
