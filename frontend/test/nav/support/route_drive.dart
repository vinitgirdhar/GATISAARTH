import 'dart:math' as math;

import 'package:gatisaarth/core/nav/map/road_follower.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';

import 'drive_simulator.dart';

/// One point of a route along real streets.
class RoutePoint {
  const RoutePoint(this.lat, this.lon, this.bearingDeg);
  final double lat;
  final double lon;
  final double bearingDeg;
}

/// A route along the streets of [graph], one point per metre, that starts with
/// a straight stretch of at least [straightM] metres (the mount alignment
/// needs a straight road to calibrate on) and is at least [totalM] long.
///
/// The route is what a driver would do who never turns: the road follower goes
/// straight through every crossing. Null when the graph has no such road.
List<RoutePoint>? straightThenOnRoute(
  RoadGraph graph, {
  double straightM = 700,
  double totalM = 4500,
  double maxBendDeg = 3,
  int maxCandidates = 400,
}) {
  var tried = 0;
  for (final edge in graph.edges) {
    if (tried >= maxCandidates) break;
    for (final start in [0.0, edge.lengthM]) {
      if (edge.lengthM < 20) continue;
      tried++;
      final route = _routeFrom(graph, edge, start, totalM);
      if (route != null && _straightAtStart(route, straightM, maxBendDeg)) {
        return route;
      }
    }
  }
  return null;
}

List<RoutePoint>? _routeFrom(
    RoadGraph graph, RoadEdge edge, double alongM, double totalM) {
  final follower = RoadFollower(graph: graph);
  final p = _pointAt(edge, alongM);
  final heading = _bearingAt(edge, alongM, forward: alongM == 0);
  if (!follower.lock(
      lat: p.$1, lon: p.$2, headingDeg: heading, maxRadiusM: 5)) {
    return null;
  }
  final route = <RoutePoint>[];
  for (var m = 0; m < totalM; m++) {
    final position = follower.position!;
    route.add(RoutePoint(position.lat, position.lon, position.headingDeg));
    if (follower.advance(1) < 0.999) return null; // dead end: too short
  }
  return route;
}

bool _straightAtStart(List<RoutePoint> route, double metres, double maxBend) {
  if (route.length < metres) return false;
  final first = route.first.bearingDeg;
  for (var i = 0; i < metres; i++) {
    if (NavMath.angleDiffDeg(route[i].bearingDeg, first).abs() > maxBend) {
      return false;
    }
  }
  return true;
}

(double, double) _pointAt(RoadEdge edge, double alongM) {
  if (alongM <= 0) return (edge.latAt(0), edge.lonAt(0));
  final last = edge.pointCount - 1;
  return (edge.latAt(last), edge.lonAt(last));
}

double _bearingAt(RoadEdge edge, double alongM, {required bool forward}) {
  final a = forward ? 0 : edge.pointCount - 1;
  final b = forward ? 1 : edge.pointCount - 2;
  final d = NavMath.nedBetween(
    lat0: edge.latAt(a),
    lon0: edge.lonAt(a),
    alt0: 0,
    lat1: edge.latAt(b),
    lon1: edge.lonAt(b),
    alt1: 0,
  );
  return NavMath.wrap360(math.atan2(d.y, d.x) * NavMath.radToDeg);
}

/// Steers a [DriveSimulator] along a route: pure pursuit on a point a little
/// ahead, and a simple speed controller. The truth therefore follows the road
/// the way a real driver does - close to it, cutting corners slightly.
class RoutePursuit {
  RoutePursuit(this.route,
      {this.lookaheadM = 12,
      this.maxYawRate = 0.5,
      this.maxLateralAccel = 2.0});

  final List<RoutePoint> route;
  final int lookaheadM;
  final double maxYawRate;
  final double maxLateralAccel;
  int _nearest = 0;

  /// Metres of route the vehicle has covered.
  int get progressM => _nearest;

  DriveSegment next(TruthSample truth, {required double targetSpeed}) {
    _advanceNearest(truth);
    final target = route[math.min(_nearest + lookaheadM, route.length - 1)];
    final d = NavMath.nedBetween(
      lat0: truth.latitude,
      lon0: truth.longitude,
      alt0: 0,
      lat1: target.lat,
      lon1: target.lon,
      alt1: 0,
    );
    final wanted = math.atan2(d.y, d.x);
    final error = NavMath.wrapPi(wanted - truth.headingRad);
    final yaw = (2.0 * error).clamp(-maxYawRate, maxYawRate).toDouble();
    final speed = math.min(targetSpeed, _cornerSpeed());
    final accel =
        (0.8 * (speed - truth.speedMps)).clamp(-2.0, 2.0).toDouble();
    return DriveSegment(seconds: 0.02, longitudinalAccel: accel, yawRate: yaw);
  }

  /// A driver slows for a bend: the fastest speed that keeps the lateral
  /// acceleration on the next stretch of road at or below [maxLateralAccel].
  double _cornerSpeed() {
    const ahead = 40;
    final here = route[_nearest].bearingDeg;
    final there = route[math.min(_nearest + ahead, route.length - 1)].bearingDeg;
    final turn = NavMath.angleDiffDeg(there, here).abs() * NavMath.degToRad;
    final curvature = turn / ahead;
    if (curvature < 1e-6) return double.infinity;
    return math.max(3.0, math.sqrt(maxLateralAccel / curvature));
  }

  void _advanceNearest(TruthSample truth) {
    var best = _nearest;
    var bestDist = double.infinity;
    final end = math.min(_nearest + 60, route.length - 1);
    for (var i = _nearest; i <= end; i++) {
      final d = NavMath.horizontalDistance(
        lat0: truth.latitude,
        lon0: truth.longitude,
        lat1: route[i].lat,
        lon1: route[i].lon,
      );
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    _nearest = best;
  }
}
