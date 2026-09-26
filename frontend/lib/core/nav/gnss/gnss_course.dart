import 'dart:math' as math;

import '../nav_config.dart';

/// A direction of travel over the ground and how sure it is.
class GnssCourse {
  const GnssCourse({required this.courseDeg, required this.sigmaDeg});

  /// Compass course, degrees clockwise from north, 0..360.
  final double courseDeg;
  final double sigmaDeg;
}

/// The course the GNSS fixes themselves trace out, for receivers (and logs)
/// that never report a bearing.
///
/// Without a bearing the core has no heading at start-up and no GNSS
/// velocity to correct one, and a wrong heading is self-sealing: the
/// non-holonomic constraint pins velocity along the wrong axis, the fused
/// speed collapses, and heading is then unobservable from position alone.
/// Found on a real drive (2026-09-26, realme RMX3851 on a rickshaw seat):
/// the core ran ~90 degrees off the GNSS course for ten minutes.
///
/// The course is taken over a baseline of at least
/// [GnssCourseConfig.minBaselineM], only while the path is straight (the two
/// halves of the baseline agree), and its sigma follows from how far apart
/// the end fixes are against their relative error.
class GnssCourseTracker {
  GnssCourseTracker({GnssCourseConfig config = const GnssCourseConfig()})
      : _c = config;

  final GnssCourseConfig _c;
  final List<_Point> _points = [];

  GnssCourse? _last;

  /// The most recent course, or null when none is currently measurable.
  GnssCourse? get course => _last;

  void reset() {
    _points.clear();
    _last = null;
  }

  /// Feeds one fix; returns the course it completes, if any.
  GnssCourse? add({
    required double latitudeDeg,
    required double longitudeDeg,
    required double accuracyM,
    required int monotonicUs,
  }) {
    _last = null;
    if (!accuracyM.isFinite || accuracyM > _c.maxAccuracyM) return null;
    final p = _Point(latitudeDeg, longitudeDeg, accuracyM, monotonicUs);
    _points.add(p);
    final windowUs = (_c.maxBaselineS * 1e6).round();
    _points.removeWhere((q) => monotonicUs - q.us > windowUs);

    // The newest point far enough back to give a baseline.
    _Point? anchor;
    for (final q in _points) {
      if (_distanceM(q, p) >= _c.minBaselineM) anchor = q;
    }
    if (anchor == null) return null;
    final dtS = (p.us - anchor.us) / 1e6;
    final baseline = _distanceM(anchor, p);
    if (dtS <= 0 || baseline / dtS < _c.minSpeedMps) return null;

    // Straight only: a bend inside the baseline makes the chord a poor
    // course. Compare the two halves against the whole.
    final mid = _points.firstWhere((q) => q.us >= (anchor!.us + p.us) ~/ 2);
    final whole = _bearing(anchor, p);
    if (_distanceM(anchor, mid) >= _c.minBaselineM / 4 &&
        _distanceM(mid, p) >= _c.minBaselineM / 4) {
      final bend = math.max(
        _angleDiff(_bearing(anchor, mid), whole).abs(),
        _angleDiff(_bearing(mid, p), whole).abs(),
      );
      if (bend > _c.maxBendDeg) return null;
    }

    final relativeError =
        _c.relativeErrorFraction * math.max(anchor.accuracyM, p.accuracyM);
    final sigma = math.max(
      _c.minSigmaDeg,
      math.atan2(relativeError * math.sqrt2, baseline) * 180 / math.pi,
    );
    return _last = GnssCourse(courseDeg: whole, sigmaDeg: sigma);
  }

  static double _distanceM(_Point a, _Point b) {
    final dn = (b.lat - a.lat) * _mPerDeg;
    final de = (b.lon - a.lon) * _mPerDeg * math.cos(a.lat * math.pi / 180);
    return math.sqrt(dn * dn + de * de);
  }

  static double _bearing(_Point a, _Point b) {
    final dn = (b.lat - a.lat) * _mPerDeg;
    final de = (b.lon - a.lon) * _mPerDeg * math.cos(a.lat * math.pi / 180);
    return (math.atan2(de, dn) * 180 / math.pi + 360) % 360;
  }

  static const double _mPerDeg = 111320;
}

/// Signed smallest difference a - b, degrees, in (-180, 180].
double _angleDiff(double a, double b) {
  var d = (a - b) % 360;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
}

/// Public for the engine's heading guard.
double courseDifferenceDeg(double a, double b) => _angleDiff(a, b);

class _Point {
  _Point(this.lat, this.lon, this.accuracyM, this.us);
  final double lat;
  final double lon;
  final double accuracyM;
  final int us;
}
