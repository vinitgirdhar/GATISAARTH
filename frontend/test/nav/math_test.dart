import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/math/matrix.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';

void expectVectorClose(Vector3 a, Vector3 b, {double tol = 1e-9}) {
  expect(a.x, closeTo(b.x, tol), reason: 'x of $a vs $b');
  expect(a.y, closeTo(b.y, tol), reason: 'y of $a vs $b');
  expect(a.z, closeTo(b.z, tol), reason: 'z of $a vs $b');
}

void main() {
  group('Matrix', () {
    test('multiplication matches a hand-computed product', () {
      final a = Matrix.fromRows([
        [1, 2, 3],
        [4, 5, 6],
      ]);
      final b = Matrix.fromRows([
        [7, 8],
        [9, 10],
        [11, 12],
      ]);
      final c = a * b;
      expect(c.rows, 2);
      expect(c.cols, 2);
      expect(c.at(0, 0), 58);
      expect(c.at(0, 1), 64);
      expect(c.at(1, 0), 139);
      expect(c.at(1, 1), 154);
    });

    test('transpose is an involution', () {
      final a = Matrix.fromRows([
        [1, 2, 3],
        [4, 5, 6],
      ]);
      final t = a.transposed.transposed;
      for (var r = 0; r < a.rows; r++) {
        for (var c = 0; c < a.cols; c++) {
          expect(t.at(r, c), a.at(r, c));
        }
      }
    });

    test('inverse times original is the identity', () {
      final a = Matrix.fromRows([
        [4, 7, 2],
        [3, 6, 1],
        [2, 5, 3],
      ]);
      final inv = a.inverse();
      expect(inv, isNotNull);
      final id = a * inv!;
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 3; c++) {
          expect(id.at(r, c), closeTo(r == c ? 1 : 0, 1e-10));
        }
      }
    });

    test('a singular matrix inverts to null instead of NaN', () {
      final singular = Matrix.fromRows([
        [1, 2],
        [2, 4],
      ]);
      expect(singular.inverse(), isNull);
    });

    test('symmetrized averages the off-diagonal pair', () {
      final m = Matrix.fromRows([
        [1, 4],
        [2, 5],
      ]).symmetrized();
      expect(m.at(0, 1), 3);
      expect(m.at(1, 0), 3);
      expect(m.isSymmetricPositiveDiagonal(), isTrue);
    });

    test('floorDiagonal lifts a collapsed variance', () {
      final m = Matrix.diagonal([1e-30, 4]);
      m.floorDiagonal(1e-9);
      expect(m.at(0, 0), 1e-9);
      expect(m.at(1, 1), 4);
    });
  });

  group('NavMath rotations', () {
    test('skew(v) * u equals v cross u', () {
      final v = Vector3(0.3, -1.2, 2.5);
      final u = Vector3(-0.7, 0.4, 1.1);
      expectVectorClose(NavMath.skew(v) * u, v.cross(u));
    });

    test('quaternion from a rotation vector rotates by that angle', () {
      final q = NavMath.quaternionFromRotationVector(Vector3(0, 0, math.pi / 2));
      expectVectorClose(
          NavMath.rotateBodyToNav(q, Vector3(1, 0, 0)), Vector3(0, 1, 0),
          tol: 1e-12);
    });

    test('a near-zero rotation vector stays unit and near identity', () {
      final q = NavMath.quaternionFromRotationVector(Vector3(1e-15, 0, -1e-15));
      expect(q.length, closeTo(1.0, 1e-12));
      expectVectorClose(
          NavMath.rotateBodyToNav(q, Vector3(1, 2, 3)), Vector3(1, 2, 3),
          tol: 1e-9);
    });

    test('rotationMatrix agrees with quaternion rotation', () {
      final q = NavMath.quaternionFromEuler(roll: 0.3, pitch: -0.2, yaw: 1.1);
      final c = NavMath.rotationMatrix(q);
      final v = Vector3(1.5, -0.4, 2.2);
      expectVectorClose(c * v, NavMath.rotateBodyToNav(q, v), tol: 1e-12);
    });

    test('vector_math Quaternion.rotated is the OPPOSITE sense to ours', () {
      // Guard, not an endorsement. `Quaternion.rotated()` applies the inverse
      // of the rotation its own `asRotationMatrix()` produces, which is why
      // the nav core routes every rotation through NavMath. If a vector_math
      // upgrade ever fixes this, the assertion below fails loudly instead of
      // the filter silently flipping its heading sign.
      final q = NavMath.quaternionFromRotationVector(Vector3(0, 0, math.pi / 2));
      expectVectorClose(q.rotated(Vector3(1, 0, 0)), Vector3(0, -1, 0),
          tol: 1e-12);
      expectVectorClose(NavMath.rotateBodyToNav(q, Vector3(1, 0, 0)),
          Vector3(0, 1, 0),
          tol: 1e-12);
    });

    test('rotateNavToBody undoes rotateBodyToNav', () {
      final q = NavMath.quaternionFromEuler(roll: 0.7, pitch: -0.2, yaw: 2.4);
      final v = Vector3(1.1, -2.3, 0.7);
      expectVectorClose(
        NavMath.rotateNavToBody(q, NavMath.rotateBodyToNav(q, v)),
        v,
        tol: 1e-12,
      );
    });

    test('rotation matrix stays orthonormal', () {
      final q = NavMath.quaternionFromEuler(roll: -0.9, pitch: 0.4, yaw: 2.7);
      final c = NavMath.rotationMatrix(q);
      final ct = c.clone()..transpose();
      final id = c * ct;
      for (var r = 0; r < 3; r++) {
        for (var col = 0; col < 3; col++) {
          expect(id.entry(r, col), closeTo(r == col ? 1 : 0, 1e-12));
        }
      }
      expect(c.determinant(), closeTo(1.0, 1e-12));
    });

    test('euler round-trips through the quaternion', () {
      const roll = 0.42, pitch = -0.31, yaw = 2.05;
      final e = NavMath.eulerFromQuaternion(
        NavMath.quaternionFromEuler(roll: roll, pitch: pitch, yaw: yaw),
      );
      expect(e[0], closeTo(roll, 1e-12));
      expect(e[1], closeTo(pitch, 1e-12));
      expect(e[2], closeTo(yaw, 1e-12));
    });

    test('heading comes from the body x-axis, ignoring roll and pitch', () {
      final q = NavMath.quaternionFromEuler(roll: 0.5, pitch: -0.3, yaw: 1.2);
      expect(NavMath.headingFromQuaternion(q), closeTo(1.2, 1e-9));
    });

    test('propagate integrates a constant yaw rate to the right heading', () {
      var q = NavMath.quaternionFromEuler(roll: 0, pitch: 0, yaw: 0);
      const dt = 0.01;
      const rate = 0.5; // rad/s about body z (down) => heading increases
      for (var i = 0; i < 200; i++) {
        q = NavMath.propagate(q, Vector3(0, 0, rate), dt);
      }
      expect(NavMath.headingFromQuaternion(q), closeTo(1.0, 1e-6));
      expect(q.length, closeTo(1.0, 1e-12));
    });

    test('a nav-frame yaw error correction lands on the right heading', () {
      final q = NavMath.quaternionFromEuler(roll: 0.2, pitch: 0.1, yaw: 0.8);
      final corrected = NavMath.applyNavFrameError(q, Vector3(0, 0, 0.05));
      expect(
        NavMath.headingFromQuaternion(corrected),
        closeTo(0.85, 1e-6),
      );
    });

    test('wrapPi and wrap360 fold angles into range', () {
      expect(NavMath.wrapPi(3 * math.pi), closeTo(math.pi, 1e-12));
      expect(NavMath.wrapPi(-3 * math.pi), closeTo(math.pi, 1e-12));
      expect(NavMath.wrap360(-10), closeTo(350, 1e-12));
      expect(NavMath.wrap360(370), closeTo(10, 1e-12));
      expect(NavMath.angleDiffDeg(10, 350), closeTo(20, 1e-9));
      expect(NavMath.angleDiffDeg(350, 10), closeTo(-20, 1e-9));
    });

    test('levelledAttitude recovers roll and pitch from gravity', () {
      final q = NavMath.quaternionFromEuler(roll: 0.25, pitch: -0.4, yaw: 0);
      // What a stationary phone at that attitude measures: specific force is
      // up, i.e. -down expressed in body coordinates.
      final measured =
          NavMath.rotateNavToBody(q, Vector3(0, 0, -NavMath.gravity));
      final recovered =
          NavMath.levelledAttitude(gravityBody: measured, headingRad: 0);
      final e = NavMath.eulerFromQuaternion(recovered);
      expect(e[0], closeTo(0.25, 1e-9));
      expect(e[1], closeTo(-0.4, 1e-9));
    });
  });

  group('NavMath magnetometer', () {
    test('a correct attitude implies no yaw error', () {
      // Field pointing north and down, as it does in the northern hemisphere.
      final fieldNav = Vector3(20, 0, 40);
      final q = NavMath.quaternionFromEuler(roll: 0.1, pitch: 0.2, yaw: 0.9);
      final magBody = NavMath.rotateNavToBody(q, fieldNav);
      final err = NavMath.magneticYawError(q: q, magBody: magBody);
      expect(err, isNotNull);
      expect(err!, closeTo(0, 1e-9));
    });

    test('a yaw error of the attitude shows up in the magnetometer residual', () {
      final fieldNav = Vector3(20, 0, 40);
      final truth = NavMath.quaternionFromEuler(roll: 0, pitch: 0, yaw: 0.5);
      final magBody = NavMath.rotateNavToBody(truth, fieldNav);
      // Filter believes the heading is 0.2 rad further clockwise than it is.
      final believed = NavMath.quaternionFromEuler(roll: 0, pitch: 0, yaw: 0.7);
      final err = NavMath.magneticYawError(q: believed, magBody: magBody);
      expect(err, isNotNull);
      expect(err!, closeTo(0.2, 1e-9));
    });

    test('a field with no usable horizontal component returns null', () {
      final q = NavMath.quaternionFromEuler(roll: 0, pitch: 0, yaw: 0);
      expect(
        NavMath.magneticYawError(q: q, magBody: Vector3(0, 0, 50)),
        isNull,
      );
      expect(
        NavMath.magneticYawError(q: q, magBody: Vector3(0, 0, 0)),
        isNull,
      );
    });
  });

  group('NavMath geodesy', () {
    test('a NED step then its inverse returns the original position', () {
      const lat = 28.6139, lon = 77.2090, alt = 216.0;
      final moved = NavMath.addNed(
        latDeg: lat,
        lonDeg: lon,
        altM: alt,
        north: 750,
        east: -1200,
        down: -35,
      );
      final back = NavMath.nedBetween(
        lat0: lat,
        lon0: lon,
        alt0: alt,
        lat1: moved[0],
        lon1: moved[1],
        alt1: moved[2],
      );
      expect(back.x, closeTo(750, 0.2));
      expect(back.y, closeTo(-1200, 0.2));
      expect(back.z, closeTo(-35, 1e-6));
    });

    test('WGS84 curvature beats the flat 111 km/deg constant', () {
      // One degree of latitude at Delhi is ~110.9 km, not 111.0 km. The old
      // constant was long by ~90 m per degree.
      final oneDegNorth = NavMath.meridianRadius(28.6 * NavMath.degToRad) *
          NavMath.degToRad;
      expect(oneDegNorth, closeTo(110857.0, 200));
      expect((oneDegNorth - 111000).abs(), greaterThan(100));
    });

    test('longitude scale shrinks with latitude', () {
      double lonMetresPerDeg(double latDeg) =>
          NavMath.horizontalDistance(
            lat0: latDeg,
            lon0: 0,
            lat1: latDeg,
            lon1: 1,
          );
      expect(lonMetresPerDeg(0), closeTo(111319.0, 300));
      expect(lonMetresPerDeg(60), lessThan(0.55 * lonMetresPerDeg(0)));
    });

    test('distance between two known points is right to a few metres', () {
      // Delhi (Connaught Place) to Noida.
      final d = NavMath.horizontalDistance(
        lat0: 28.6139,
        lon0: 77.2090,
        lat1: 28.5355,
        lon1: 77.3910,
      );
      expect(d, closeTo(19807.0, 50));
    });
  });

  group('NavMath filter helpers', () {
    test('NIS of a zero residual is zero', () {
      final r = Matrix.column([0, 0]);
      final s = Matrix.diagonal([4, 9]);
      expect(NavMath.nis(r, s), closeTo(0, 1e-12));
    });

    test('NIS counts residuals in sigmas', () {
      // Residual of 3 with variance 1 in each of two independent channels.
      final r = Matrix.column([3, 3]);
      final s = Matrix.diagonal([1, 1]);
      expect(NavMath.nis(r, s), closeTo(18, 1e-9));
    });

    test('NIS returns null for a singular innovation covariance', () {
      final r = Matrix.column([1, 1]);
      final s = Matrix.fromRows([
        [1, 1],
        [1, 1],
      ]);
      expect(NavMath.nis(r, s), isNull);
    });

    test('horizontal sigma is the ellipse semi-major axis', () {
      // Uncorrelated, 9 m² north and 4 m² east => 3 m.
      expect(NavMath.horizontalSigma(9, 0, 4), closeTo(3, 1e-12));
      // Fully correlated equal variances => sqrt(2) times the marginal sigma.
      expect(NavMath.horizontalSigma(4, 4, 4), closeTo(math.sqrt(8), 1e-12));
    });
  });
}
