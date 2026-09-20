import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_follower.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';

const double originLat = 28.6139;
const double originLon = 77.2090;

/// `[lat, lon]` of a point [n] metres north and [e] metres east of the origin.
List<double> pointAt(double n, double e) {
  final p = NavMath.addNed(
      latDeg: originLat,
      lonDeg: originLon,
      altM: 0,
      north: n,
      east: e,
      down: 0);
  return [p[0], p[1]];
}

/// A road through `[north, east]` points. The node ids are junk on purpose:
/// real tile graphs have arbitrary ones and the follower must not read them.
RoadEdge road(
  int id,
  List<List<double>> pts, {
  bool oneWay = false,
  String? name,
  RoadClass roadClass = RoadClass.residential,
  Set<VehicleAccess> access = const {
    VehicleAccess.cars,
    VehicleAccess.twoWheelers,
  },
}) =>
    RoadEdge(
      id: id,
      fromNode: 1000 + id,
      toNode: 2000 + id,
      polyline: [for (final p in pts) ...pointAt(p[0], p[1])],
      oneWay: oneWay,
      name: name,
      roadClass: roadClass,
      access: access,
    );

RoadGraph graphOf(List<RoadEdge> edges) =>
    RoadGraph(nodes: const [], edges: edges);

RoadFollower lockedAt(RoadGraph g, double n, double e,
    {double? heading, VehicleAccess? vehicle}) {
  final f = RoadFollower(graph: g, vehicle: vehicle);
  final p = pointAt(n, e);
  expect(f.lock(lat: p[0], lon: p[1], headingDeg: heading), isTrue);
  return f;
}

/// `(north, east)` of a position relative to the origin.
({double n, double e}) offsetOf(RoadPosition p) {
  final d = NavMath.nedBetween(
      lat0: originLat,
      lon0: originLon,
      alt0: 0,
      lat1: p.lat,
      lon1: p.lon,
      alt1: 0);
  return (n: d.x, e: d.y);
}

void expectAt(RoadFollower f, double n, double e, {double tol = 0.5}) {
  final p = f.position!;
  final o = offsetOf(p);
  expect(o.n, closeTo(n, tol), reason: 'north of $p');
  expect(o.e, closeTo(e, tol), reason: 'east of $p');
}

void expectHeading(RoadFollower f, double deg, {double tol = 1.0}) {
  expect(NavMath.angleDiffDeg(f.position!.headingDeg, deg).abs(),
      lessThanOrEqualTo(tol),
      reason: 'heading ${f.position!.headingDeg} vs $deg');
}

/// Drives [metres] in [step] steps, spreading [totalYawDeg] evenly over them.
double steer(RoadFollower f, double metres,
    {double totalYawDeg = 0, double step = 1}) {
  final steps = (metres / step).round();
  var travelled = 0.0;
  for (var i = 0; i < steps; i++) {
    travelled += f.advance(step, yawDeg: totalYawDeg / steps);
  }
  return travelled;
}

/// Four roads meeting at the origin, each its own edge, all digitised
/// outwards from the centre except the southern one.
RoadGraph fourWay({
  String? southName = 'Main',
  String? northName = 'Main',
  RoadClass northClass = RoadClass.residential,
  RoadClass eastClass = RoadClass.residential,
}) =>
    graphOf([
      road(
          1,
          [
            [-300, 0],
            [0, 0]
          ],
          name: southName),
      road(
          2,
          [
            [0, 0],
            [300, 0]
          ],
          name: northName,
          roadClass: northClass),
      road(
          3,
          [
            [0, 0],
            [0, 300]
          ],
          name: 'Cross',
          roadClass: eastClass),
      road(
          4,
          [
            [0, 0],
            [0, -300]
          ],
          name: 'Cross'),
    ]);

/// One long west-east edge with a north road and a south road that START on
/// it. Real tile roads look like this: the crossing is inside the edge.
RoadGraph midEdgeCrossing() => graphOf([
      road(
          1,
          [
            [0, -300],
            [0, 300]
          ],
          name: 'Main'),
      road(
          2,
          [
            [0, 0],
            [300, 0]
          ],
          name: 'North'),
      road(
          3,
          [
            [0, 0],
            [-300, 0]
          ],
          name: 'South'),
    ]);

/// A city grid where every street is ONE edge crossing all the others
/// mid-edge, and each end sticks out 50 m past the outer streets.
RoadGraph gridGraph({int streets = 15, double spacing = 100}) {
  final extent = (streets - 1) * spacing;
  final edges = <RoadEdge>[];
  for (var k = 0; k < streets; k++) {
    final cls = RoadClass.values[k % 4];
    edges.add(road(
        100 + k,
        [
          [k * spacing, -50],
          [k * spacing, extent + 50]
        ],
        name: 'H$k',
        roadClass: cls));
    edges.add(road(
        200 + k,
        [
          [-50, k * spacing],
          [extent + 50, k * spacing]
        ],
        name: 'V$k',
        roadClass: cls));
  }
  return graphOf(edges);
}

/// A 5 km road of 400 vertices weaving about its axis.
List<List<double>> windingRoad() => [
      for (var i = 0; i <= 400; i++) [i * 12.5, 15 * math.sin(i / 20)],
    ];

/// Gyro noise plus an occasional 90 degree turn spread over 12 steps.
List<double> yawSchedule(int steps, int seed) {
  final r = math.Random(seed);
  final out = List<double>.filled(steps, 0);
  var perStep = 0.0;
  var left = 0;
  for (var i = 0; i < steps; i++) {
    if (left == 0 && r.nextInt(150) == 0) {
      perStep = (r.nextBool() ? 1 : -1) * 90.0 / 12;
      left = 12;
    }
    out[i] = (r.nextDouble() - 0.5) + (left > 0 ? perStep : 0);
    if (left > 0) left--;
  }
  return out;
}
