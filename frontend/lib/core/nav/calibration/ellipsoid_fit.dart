import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/matrix.dart';
import '../math/nav_math.dart';

/// Result of fitting an axis-aligned ellipsoid to a cloud of 3-vectors.
@immutable
class EllipsoidFit {
  const EllipsoidFit({
    required this.centre,
    required this.radii,
    required this.residualRms,
    required this.coverage,
    required this.sampleCount,
  });

  /// Offset of the cloud from the origin.
  ///
  /// For a stationary accelerometer sampled in many orientations this is the
  /// accelerometer bias; for a magnetometer swung through many orientations it
  /// is the hard-iron offset.
  final Vector3 centre;

  /// Semi-axis lengths. Equal radii mean no scale error; unequal radii are
  /// axis scale-factor error (accelerometer) or soft-iron distortion
  /// (magnetometer).
  final Vector3 radii;

  /// RMS of `|corrected| - meanRadius`, in the input's units. The honest
  /// measure of how well the data actually fits an ellipsoid.
  final double residualRms;

  /// 0..1 — fraction of the 8 direction octants the samples visited. A fit
  /// from one orientation is meaningless however small its residual, so this
  /// is what stops a stationary phone reporting a confident calibration.
  final double coverage;

  final int sampleCount;

  double get meanRadius => (radii.x + radii.y + radii.z) / 3;

  /// Per-axis scale factors that map the fitted ellipsoid onto a sphere of
  /// [meanRadius].
  Vector3 get scale => Vector3(
        radii.x == 0 ? 1 : meanRadius / radii.x,
        radii.y == 0 ? 1 : meanRadius / radii.y,
        radii.z == 0 ? 1 : meanRadius / radii.z,
      );

  /// Applies the calibration: remove the offset, then correct the scale.
  Vector3 correct(Vector3 raw) {
    final s = scale;
    return Vector3(
      (raw.x - centre.x) * s.x,
      (raw.y - centre.y) * s.y,
      (raw.z - centre.z) * s.z,
    );
  }
}

/// Least-squares fit of an axis-aligned ellipsoid to 3-D samples.
///
/// Both of the calibrations that need it reduce to the same geometry (§5):
/// * a **stationary accelerometer** rotated through many orientations traces a
///   sphere of radius g centred on its own bias;
/// * a **magnetometer** swung through many orientations traces an ellipsoid
///   centred on the hard-iron offset, with the axis lengths carrying the
///   diagonal part of the soft-iron distortion.
///
/// Solving one problem twice is the whole point — a general 9-parameter
/// soft-iron fit needs far better excitation than a driver waving a phone can
/// give, and would report confident nonsense when it does not get it.
class EllipsoidFitter {
  const EllipsoidFitter._();

  /// Minimum samples before a fit is attempted at all.
  static const int minimumSamples = 40;

  /// Fits [samples]. Returns null when the data cannot support a fit —
  /// too few points, degenerate geometry, or a singular normal matrix.
  /// Callers report "not calibrated" rather than falling back to a guess.
  static EllipsoidFit? fit(List<Vector3> samples) {
    if (samples.length < minimumSamples) return null;

    // The ellipsoid x^2/a^2 + ... = 1 expands to
    //   u1 x^2 + u2 y^2 + u3 z^2 + u4 x + u5 y + u6 z + u7 = 0,
    // which is linear in u. Normalising u1 = 1 turns it into an ordinary
    // least-squares problem with x^2 on the left:
    //   x^2 = -(v0 y^2 + v1 z^2 + v2 x + v3 y + v4 z + v5).
    const n = 6;
    final ata = Matrix(n, n);
    final atb = Matrix(n, 1);

    for (final s in samples) {
      if (!s.x.isFinite || !s.y.isFinite || !s.z.isFinite) continue;
      final row = <double>[
        s.y * s.y,
        s.z * s.z,
        s.x,
        s.y,
        s.z,
        1,
      ];
      final target = -(s.x * s.x);
      for (var i = 0; i < n; i++) {
        atb.add(i, 0, row[i] * target);
        for (var j = 0; j < n; j++) {
          ata.add(i, j, row[i] * row[j]);
        }
      }
    }

    final inverse = ata.inverse();
    if (inverse == null) return null;
    final v = (inverse * atb).columnValues;
    if (v.any((e) => !e.isFinite)) return null;

    final u1 = 1.0;
    final u2 = v[0];
    final u3 = v[1];
    final u4 = v[2];
    final u5 = v[3];
    final u6 = v[4];
    final u7 = v[5];

    // All three quadratic coefficients must share a sign for the surface to be
    // an ellipsoid rather than a hyperboloid.
    if (!(u2 > 0) || !(u3 > 0)) return null;

    final centre = Vector3(
      -u4 / (2 * u1),
      -u5 / (2 * u2),
      -u6 / (2 * u3),
    );
    final rSquared = u1 * centre.x * centre.x +
        u2 * centre.y * centre.y +
        u3 * centre.z * centre.z -
        u7;
    if (!(rSquared > 0) || !rSquared.isFinite) return null;

    final radii = Vector3(
      math.sqrt(rSquared / u1),
      math.sqrt(rSquared / u2),
      math.sqrt(rSquared / u3),
    );
    if (!radii.x.isFinite || !radii.y.isFinite || !radii.z.isFinite) {
      return null;
    }
    // A radius ratio this extreme is a fit to noise, not to a real sensor.
    final maxRadius = math.max(radii.x, math.max(radii.y, radii.z));
    final minRadius = math.min(radii.x, math.min(radii.y, radii.z));
    if (minRadius <= 0 || maxRadius / minRadius > 4) return null;

    final provisional = EllipsoidFit(
      centre: centre,
      radii: radii,
      residualRms: 0,
      coverage: 0,
      sampleCount: samples.length,
    );

    final mean = provisional.meanRadius;
    var sumSq = 0.0;
    for (final s in samples) {
      final d = provisional.correct(s).length - mean;
      sumSq += d * d;
    }

    return EllipsoidFit(
      centre: centre,
      radii: radii,
      residualRms: math.sqrt(sumSq / samples.length),
      coverage: directionCoverage(samples, centre),
      sampleCount: samples.length,
    );
  }

  /// Fraction of the eight direction octants the samples visit, relative to
  /// [centre].
  ///
  /// Coverage — not residual — is what separates a real calibration from a
  /// phone that sat on a desk. Eight octants is coarse on purpose: a driver
  /// following an on-screen prompt will not produce dense sphere coverage, and
  /// a finer grid would report low confidence for a perfectly usable fit.
  static double directionCoverage(List<Vector3> samples, Vector3 centre) {
    final visited = <int>{};
    for (final s in samples) {
      final d = s - centre;
      if (d.length < 1e-6) continue;
      final octant = (d.x >= 0 ? 1 : 0) | (d.y >= 0 ? 2 : 0) | (d.z >= 0 ? 4 : 0);
      visited.add(octant);
    }
    return visited.length / 8;
  }

  /// Angular spread of the samples about [centre], in steradians-ish terms:
  /// the smallest eigenvalue of the direction scatter matrix, normalised.
  ///
  /// Complements [directionCoverage]: octants catch "did it move at all",
  /// this catches "did it only move in a plane", which is the realistic
  /// failure when someone waves a phone in a figure of eight.
  static double planarity(List<Vector3> samples, Vector3 centre) {
    if (samples.length < 3) return 1;
    var xx = 0.0, yy = 0.0, zz = 0.0, xy = 0.0, xz = 0.0, yz = 0.0;
    var used = 0;
    for (final s in samples) {
      final d = s - centre;
      final len = d.length;
      if (len < 1e-6) continue;
      final u = d / len;
      xx += u.x * u.x;
      yy += u.y * u.y;
      zz += u.z * u.z;
      xy += u.x * u.y;
      xz += u.x * u.z;
      yz += u.y * u.z;
      used++;
    }
    if (used < 3) return 1;
    final m = Matrix.fromRows([
      [xx / used, xy / used, xz / used],
      [xy / used, yy / used, yz / used],
      [xz / used, yz / used, zz / used],
    ]);
    // Smallest eigenvalue of a 3x3 symmetric matrix, by the trigonometric
    // closed form. 1/3 means isotropic; near 0 means the samples lie in a
    // plane and one axis is unobserved.
    final smallest = _smallestSymmetricEigenvalue(m);
    return (smallest * 3).clamp(0.0, 1.0);
  }

  static double _smallestSymmetricEigenvalue(Matrix m) {
    final p1 = m.at(0, 1) * m.at(0, 1) +
        m.at(0, 2) * m.at(0, 2) +
        m.at(1, 2) * m.at(1, 2);
    final trace = m.at(0, 0) + m.at(1, 1) + m.at(2, 2);
    if (p1 == 0) {
      return math.min(m.at(0, 0), math.min(m.at(1, 1), m.at(2, 2)));
    }
    final q = trace / 3;
    final p2 = (m.at(0, 0) - q) * (m.at(0, 0) - q) +
        (m.at(1, 1) - q) * (m.at(1, 1) - q) +
        (m.at(2, 2) - q) * (m.at(2, 2) - q) +
        2 * p1;
    final p = math.sqrt(p2 / 6);
    if (p <= 0) return q;
    final b = Matrix.fromRows([
      for (var r = 0; r < 3; r++)
        [for (var c = 0; c < 3; c++) (m.at(r, c) - (r == c ? q : 0)) / p],
    ]);
    final det = b.at(0, 0) *
            (b.at(1, 1) * b.at(2, 2) - b.at(1, 2) * b.at(2, 1)) -
        b.at(0, 1) * (b.at(1, 0) * b.at(2, 2) - b.at(1, 2) * b.at(2, 0)) +
        b.at(0, 2) * (b.at(1, 0) * b.at(2, 1) - b.at(1, 1) * b.at(2, 0));
    final phi = math.acos((det / 2).clamp(-1.0, 1.0)) / 3;
    // eig1 >= eig2 >= eig3; we want the smallest.
    final eig1 = q + 2 * p * math.cos(phi);
    final eig3 = 3 * q - eig1 - (q + 2 * p * math.cos(phi + 2 * math.pi / 3));
    return math.min(eig3, q + 2 * p * math.cos(phi + 2 * math.pi / 3));
  }
}

/// Convenience for the accelerometer case, where the true radius is known.
extension AccelerometerFit on EllipsoidFit {
  /// How far the fitted sphere radius is from standard gravity (m/s²).
  ///
  /// A large value means the fit is not describing a stationary
  /// accelerometer — the phone was moving during calibration.
  double get gravityError => (meanRadius - NavMath.gravity).abs();
}
