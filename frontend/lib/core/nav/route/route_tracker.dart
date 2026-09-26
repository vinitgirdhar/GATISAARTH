import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';
import '../nav_config.dart';
import 'planned_route.dart';

/// A point on the route.
@immutable
class RoutePoint {
  const RoutePoint({
    required this.lat,
    required this.lon,
    required this.headingDeg,
    required this.alongM,
  });

  final double lat;
  final double lon;

  /// Direction of travel along the route, compass degrees [0, 360).
  final double headingDeg;

  /// Metres from the route start.
  final double alongM;
}

/// How far along the journey the vehicle is.
@immutable
class RouteProgress {
  const RouteProgress({
    required this.alongM,
    required this.remainingM,
    required this.remainingS,
    required this.arrived,
    this.next,
    this.distanceToNextM,
    this.offRouteM,
  });

  final double alongM;
  final double remainingM;

  /// The route's own duration estimate, pro rata to the distance left.
  final double remainingS;
  final bool arrived;

  /// The next maneuver ahead (the arrival once the last turn is passed).
  final RouteManeuver? next;
  final double? distanceToNextM;

  /// Perpendicular distance of the last observed position from the route,
  /// null when the last update was dead reckoning along the route.
  final double? offRouteM;
}

/// A best-match projection of a point onto some segment range of [polyline].
({double alongM, double perpendicularM, double lat, double lon}) _projectOntoRoute(
  List<double> polyline,
  List<double> cum,
  double lat,
  double lon, {
  required int loSeg,
  required int hiSeg,
  required double expectedAlongM,
  required double alongPenaltyPerM,
}) {
  var bestScore = double.infinity;
  var bestPerp = double.infinity;
  var bestAlong = 0.0;
  var bestLat = polyline[loSeg * 2];
  var bestLon = polyline[loSeg * 2 + 1];
  for (var i = loSeg; i <= hiSeg; i++) {
    final aLat = polyline[i * 2], aLon = polyline[i * 2 + 1];
    final bLat = polyline[(i + 1) * 2], bLon = polyline[(i + 1) * 2 + 1];
    final ab = NavMath.nedBetween(
        lat0: aLat, lon0: aLon, alt0: 0, lat1: bLat, lon1: bLon, alt1: 0);
    final ap = NavMath.nedBetween(
        lat0: aLat, lon0: aLon, alt0: 0, lat1: lat, lon1: lon, alt1: 0);
    final segLength2 = ab.x * ab.x + ab.y * ab.y;
    final segLength = math.sqrt(segLength2);
    final t = segLength2 < 1e-9
        ? 0.0
        : ((ap.x * ab.x + ap.y * ab.y) / segLength2).clamp(0.0, 1.0);
    final closestN = ab.x * t, closestE = ab.y * t;
    final dN = ap.x - closestN, dE = ap.y - closestE;
    final perp = math.sqrt(dN * dN + dE * dE);
    final along = cum[i] + segLength * t;
    final score = perp + alongPenaltyPerM * (along - expectedAlongM).abs();
    if (score < bestScore) {
      bestScore = score;
      bestPerp = perp;
      bestAlong = along;
      final moved = NavMath.addNed(
          latDeg: aLat, lonDeg: aLon, altM: 0, north: closestN, east: closestE, down: 0);
      bestLat = moved[0];
      bestLon = moved[1];
    }
  }
  return (alongM: bestAlong, perpendicularM: bestPerp, lat: bestLat, lon: bestLon);
}

/// Follows one [PlannedRoute].
///
/// Two ways to move:
/// * [observe] - a measured position (GNSS or the fused solution) is projected
///   onto the route near the current progress (never jumping to a far-away
///   stretch that happens to pass close, e.g. a loop or flyover); progress
///   only updates when the point is on the route. [isOffRoute] turns true after
///   `config.offRouteObservations` consecutive points beyond
///   `max(config.offRouteM, 2 * accuracyM)`.
/// * dead reckoning - [lockAt] then [advance]: the position moves along the
///   route polyline by the distance travelled. [addYaw] feeds gyro yaw
///   (compass-positive, right = +); when the yaw the route's own bends do not
///   explain exceeds `config.divergeYawDeg` over `config.yawWindowM` of
///   travel, [hasDiverged] turns true (the vehicle left the route) and the
///   caller should release and fall back to road-following.
class RouteTracker {
  RouteTracker(this.route, {this.config = const RouteConfig()})
      : _bearingDeg = _bearingsOf(route);

  final PlannedRoute route;
  final RouteConfig config;

  /// Compass bearing (deg) of each polyline segment, degenerate (near-zero
  /// length) ones inheriting a neighbour's — same construction as
  /// `RoadFollower`'s internal `_Geom`.
  final List<double> _bearingDeg;

  double _alongM = 0;
  bool _locked = false;
  bool _diverged = false;
  int _offRouteStreak = 0;
  bool _isOffRoute = false;
  double? _lastOffRouteM;

  /// Gyro yaw accumulated since the last [advance] (deg, right = +).
  double _pendingYawDeg = 0;

  /// Metres driven since [lockAt], and the running (odometer, unexplained
  /// total) sum, so the last `config.yawWindowM` of it can be read back out —
  /// same pattern as `RoadFollower`'s bend-registration trail.
  double _odoM = 0;
  double _unexplainedTotalDeg = 0;
  final Queue<({double odo, double val})> _yawTrail = Queue();

  double get alongM => _alongM;

  RouteProgress get progress {
    final remaining = math.max(0.0, route.lengthM - _alongM);
    final remainingS =
        route.lengthM > 0 ? route.durationS * (remaining / route.lengthM) : 0.0;
    RouteManeuver? next;
    for (final m in route.maneuvers) {
      if (m.atM > _alongM + config.maneuverPassedM) {
        next = m;
        break;
      }
    }
    return RouteProgress(
      alongM: _alongM,
      remainingM: remaining,
      remainingS: remainingS,
      arrived: remaining < config.arrivalRadiusM,
      next: next,
      distanceToNextM: next == null ? null : next.atM - _alongM,
      offRouteM: _lastOffRouteM,
    );
  }

  /// Projects a measured position; returns its distance from the route (m).
  double observe(double lat, double lon, {double? accuracyM}) {
    final cum = route.cumM;
    final loSeg = _segmentAt(math.max(0.0, _alongM - config.observeWindowBackM));
    final hiSeg =
        _segmentAt(math.min(route.lengthM, _alongM + config.observeWindowForwardM));
    var result = _projectOntoRoute(route.polyline, cum, lat, lon,
        loSeg: loSeg,
        hiSeg: hiSeg,
        expectedAlongM: _alongM,
        alongPenaltyPerM: config.observeAlongPenaltyPerM);

    if (result.perpendicularM > config.offRouteM && _lastSegment > 0) {
      final global = _projectOntoRoute(route.polyline, cum, lat, lon,
          loSeg: 0,
          hiSeg: _lastSegment,
          expectedAlongM: _alongM,
          alongPenaltyPerM: config.observeAlongPenaltyPerM);
      if (global.perpendicularM < result.perpendicularM) result = global;
    }

    _lastOffRouteM = result.perpendicularM;
    final threshold =
        math.max(config.offRouteM, accuracyM != null ? 2 * accuracyM : 0.0);
    if (result.perpendicularM <= threshold) {
      _alongM = result.alongM;
      _offRouteStreak = 0;
      _isOffRoute = false;
    } else {
      _offRouteStreak++;
      if (_offRouteStreak >= config.offRouteObservations) _isOffRoute = true;
    }
    return result.perpendicularM;
  }

  bool get isOffRoute => _isOffRoute;

  /// Locks dead reckoning onto the route at the point nearest [lat]/[lon]:
  /// fails (false) beyond `config.lockRadiusM`, or when [headingDeg] is given
  /// and differs from the route direction there by more than
  /// `config.lockHeadingTolDeg`.
  bool lockAt(double lat, double lon, {double? headingDeg}) {
    final result = _projectOntoRoute(route.polyline, route.cumM, lat, lon,
        loSeg: 0, hiSeg: _lastSegment, expectedAlongM: 0, alongPenaltyPerM: 0);
    if (result.perpendicularM > config.lockRadiusM) return false;
    if (headingDeg != null && headingDeg.isFinite) {
      final routeHeading = _bearingDeg[_segmentAt(result.alongM)];
      if (NavMath.angleDiffDeg(headingDeg, routeHeading).abs() >
          config.lockHeadingTolDeg) {
        return false;
      }
    }
    _alongM = result.alongM;
    _locked = true;
    _diverged = false;
    _odoM = 0;
    _unexplainedTotalDeg = 0;
    _pendingYawDeg = 0;
    _yawTrail.clear();
    _lastOffRouteM = null;
    return true;
  }

  bool get isLocked => _locked;

  void release() {
    _locked = false;
    _diverged = false;
    _pendingYawDeg = 0;
    _yawTrail.clear();
  }

  /// Gyro yaw since the last [advance] (deg, right = +). Ignored unless locked.
  void addYaw(double degrees) {
    if (!_locked || !degrees.isFinite) return;
    _pendingYawDeg += degrees;
  }

  /// Moves [meters] along the route (stops at the destination). Null when not
  /// locked.
  RoutePoint? advance(double meters) {
    if (!_locked) return null;
    if (meters.isFinite && meters > 0) {
      final before = _alongM;
      final target = math.min(before + meters, route.lengthM);
      final travelled = target - before;
      final routeHeadingChange = NavMath.angleDiffDeg(
          _bearingDeg[_segmentAt(target)], _bearingDeg[_segmentAt(before)]);
      _unexplainedTotalDeg += _pendingYawDeg - routeHeadingChange;
      _odoM += travelled;
      _yawTrail.addLast((odo: _odoM, val: _unexplainedTotalDeg));
      final windowStart = _odoM - config.yawWindowM;
      while (_yawTrail.length > 1 && _yawTrail.elementAt(1).odo < windowStart) {
        _yawTrail.removeFirst();
      }
      _checkDivergence();
      _alongM = target;
      _lastOffRouteM = null;
    }
    _pendingYawDeg = 0;
    return pointAt(_alongM);
  }

  void _checkDivergence() {
    final windowStart = _odoM - config.yawWindowM;
    final baseline = (_yawTrail.isNotEmpty && _yawTrail.first.odo < windowStart)
        ? _yawTrail.first.val
        : 0.0;
    if ((_unexplainedTotalDeg - baseline).abs() > config.divergeYawDeg) {
      _diverged = true;
    }
  }

  bool get hasDiverged => _diverged;

  /// The point [alongM] metres from the start (clamped to the route).
  RoutePoint pointAt(double alongM) {
    final clamped = alongM.clamp(0.0, route.lengthM);
    final cum = route.cumM;
    final seg = _segmentAt(clamped);
    final span = cum[seg + 1] - cum[seg];
    final t = span > 1e-9 ? (clamped - cum[seg]) / span : 0.0;
    final lat = route.latAt(seg) + (route.latAt(seg + 1) - route.latAt(seg)) * t;
    final lon = route.lonAt(seg) + (route.lonAt(seg + 1) - route.lonAt(seg)) * t;
    return RoutePoint(
        lat: lat, lon: lon, headingDeg: _bearingDeg[seg], alongM: clamped);
  }

  int get _lastSegment => route.pointCount - 2;

  /// The segment index `s` with `cumM[s] <= along < cumM[s + 1]`.
  int _segmentAt(double along) {
    final cum = route.cumM;
    final clamped = along.clamp(0.0, cum.last);
    var lo = 0, hi = cum.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] <= clamped) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo.clamp(0, _lastSegment);
  }

  static List<double> _bearingsOf(PlannedRoute route) {
    final n = route.pointCount;
    final bearing = List<double>.filled(math.max(n - 1, 0), 0);
    for (var i = 0; i < bearing.length; i++) {
      final d = NavMath.nedBetween(
        lat0: route.latAt(i),
        lon0: route.lonAt(i),
        alt0: 0,
        lat1: route.latAt(i + 1),
        lon1: route.lonAt(i + 1),
        alt1: 0,
      );
      final len = math.sqrt(d.x * d.x + d.y * d.y);
      bearing[i] =
          len < 1e-9 ? double.nan : NavMath.wrap360(math.atan2(d.y, d.x) * NavMath.radToDeg);
    }
    var last = 0.0;
    for (var i = 0; i < bearing.length; i++) {
      if (bearing[i].isNaN) {
        bearing[i] = last;
      } else {
        last = bearing[i];
      }
    }
    for (var i = bearing.length - 2; i >= 0; i--) {
      if (bearing[i].isNaN) bearing[i] = bearing[i + 1];
    }
    return bearing;
  }
}
