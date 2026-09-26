import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/pmtiles_road_graph.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/route/planned_route.dart';
import 'package:gatisaarth/core/nav/route/route_planner.dart';

import 'support/road_follower_fixtures.dart' show pointAt;
import 'support/route_fixtures.dart' show tileRoad, routeGraph;

void main() {
  group('planRoute', () {
    test('straight road: depart then arrive, no spurious maneuvers', () {
      final g = routeGraph([
        tileRoad([
          [0, 0],
          [0, 1000]
        ], name: 'Straight'),
      ]);
      final start = pointAt(0, 50);
      final dest = pointAt(0, 900);
      final route = planRoute(g,
          fromLat: start[0], fromLon: start[1], toLat: dest[0], toLon: dest[1]);

      expect(route, isNotNull);
      expect(route!.maneuvers.map((m) => m.kind),
          [ManeuverKind.depart, ManeuverKind.arrive]);
      expect(route.lengthM, closeTo(850, 2));
      expect(route.maneuvers.last.atM, closeTo(route.lengthM, 1e-6));
    });

    test('L-shaped T-junction: north then east is a right turn', () {
      final g = routeGraph([
        tileRoad([
          [-500, 0],
          [0, 0]
        ], name: 'North-South'),
        tileRoad([
          [0, 0],
          [500, 0]
        ], name: 'North-South'),
        tileRoad([
          [0, 0],
          [0, 500]
        ], name: 'Cross'),
      ]);
      final start = pointAt(-450, 0);
      final dest = pointAt(0, 450);
      final route = planRoute(g,
          fromLat: start[0], fromLon: start[1], toLat: dest[0], toLon: dest[1]);

      expect(route, isNotNull);
      final turns = route!.maneuvers
          .where((m) => m.kind != ManeuverKind.depart && m.kind != ManeuverKind.arrive)
          .toList();
      expect(turns, hasLength(1));
      expect(turns.single.kind, ManeuverKind.right);
      expect(turns.single.roadName, 'Cross');
    });

    test('prefers a faster road class over a shorter slower one', () {
      final g = routeGraph([
        tileRoad([
          [0, 0],
          [0, 1000]
        ], roadClass: RoadClass.residential, name: 'Direct'),
        tileRoad([
          [0, 0],
          [100, 0]
        ], roadClass: RoadClass.primary, name: 'DetourIn'),
        tileRoad([
          [100, 0],
          [100, 1000]
        ], roadClass: RoadClass.primary, name: 'DetourMain'),
        tileRoad([
          [100, 1000],
          [0, 1000]
        ], roadClass: RoadClass.primary, name: 'DetourOut'),
      ]);
      final start = pointAt(0, 0);
      final dest = pointAt(0, 1000);
      // A tight snap radius: the detour road sits 100 m off the direct line,
      // so a generous radius would let start/destination "snap" straight onto
      // it for free rather than actually driving the connecting roads.
      final route = planRoute(g,
          fromLat: start[0],
          fromLon: start[1],
          toLat: dest[0],
          toLon: dest[1],
          config: const RouteConfig(snapRadiusM: 20));

      expect(route, isNotNull);
      // The direct residential road is 1000 m at 6.5 m/s (~154 s); the 1200 m
      // primary detour at 12 m/s (~100 s) is faster overall, so it wins.
      expect(route!.lengthM, greaterThan(1100));
      expect(route.durationS, lessThan(120));
    });

    test('respects one-way: goes around instead of driving backwards', () {
      final g = routeGraph([
        tileRoad([
          [0, 0],
          [0, 1000]
        ], oneWay: true, name: 'OneWay'),
        tileRoad([
          [0, 1000],
          [300, 500],
          [0, 0]
        ], name: 'Around'),
      ]);
      // Travelling from the "to" end back to the "from" end of the one-way
      // is illegal, so the planner must take the loop road round instead.
      final start = pointAt(0, 1000);
      final dest = pointAt(0, 0);
      final route = planRoute(g,
          fromLat: start[0], fromLon: start[1], toLat: dest[0], toLon: dest[1]);

      expect(route, isNotNull);
      expect(route!.lengthM, greaterThan(1000));
    });

    test('no maneuver at a degree-2 split (tile-border artifact)', () {
      final g = routeGraph([
        tileRoad([
          [0, 0],
          [0, 500]
        ], name: 'Main'),
        tileRoad([
          [0, 500],
          [0, 1000]
        ], name: 'Main'),
      ]);
      final start = pointAt(0, 50);
      final dest = pointAt(0, 950);
      final route = planRoute(g,
          fromLat: start[0], fromLon: start[1], toLat: dest[0], toLon: dest[1]);

      expect(route, isNotNull);
      expect(route!.maneuvers.map((m) => m.kind),
          [ManeuverKind.depart, ManeuverKind.arrive]);
    });

    test('start and destination on the same edge', () {
      final g = routeGraph([
        tileRoad([
          [0, 0],
          [0, 1000]
        ], name: 'Same'),
      ]);
      final start = pointAt(0, 100);
      final dest = pointAt(0, 700);
      final route = planRoute(g,
          fromLat: start[0], fromLon: start[1], toLat: dest[0], toLon: dest[1]);

      expect(route, isNotNull);
      expect(route!.lengthM, closeTo(600, 1));
      expect(route.maneuvers, hasLength(2));
    });

    test('no road anywhere near either end returns null', () {
      final g = routeGraph([
        tileRoad([
          [0, 0],
          [0, 1000]
        ]),
      ]);
      final farStart = pointAt(50000, 50000);
      final farDest = pointAt(60000, 60000);
      final route = planRoute(g,
          fromLat: farStart[0],
          fromLon: farStart[1],
          toLat: farDest[0],
          toLon: farDest[1]);
      expect(route, isNull);
    });

    test('two disconnected road islands: unreachable returns null', () {
      final g = routeGraph([
        tileRoad([
          [0, 0],
          [0, 1000]
        ]),
        tileRoad([
          [50000, 50000],
          [50000, 51000]
        ]),
      ]);
      final start = pointAt(0, 0);
      final dest = pointAt(50000, 50500);
      final route = planRoute(g,
          fromLat: start[0], fromLon: start[1], toLat: dest[0], toLon: dest[1]);
      expect(route, isNull);
    });

    test('JSON round trip preserves the route', () {
      final g = routeGraph([
        tileRoad([
          [-500, 0],
          [0, 0]
        ], name: 'North-South'),
        tileRoad([
          [0, 0],
          [500, 0]
        ], name: 'North-South'),
        tileRoad([
          [0, 0],
          [0, 500]
        ], name: 'Cross'),
      ]);
      final start = pointAt(-450, 0);
      final dest = pointAt(0, 450);
      final route = planRoute(g,
          fromLat: start[0], fromLon: start[1], toLat: dest[0], toLon: dest[1])!;

      final decoded = PlannedRoute.fromJson(route.toJson())!;
      expect(decoded.polyline, route.polyline);
      expect(decoded.durationS, route.durationS);
      expect(decoded.maneuvers.map((m) => m.kind), route.maneuvers.map((m) => m.kind));
      expect(decoded.lengthM, closeTo(route.lengthM, 1e-6));
    });
  });

  group('planRoute on the real Mumbai map', () {
    final fixture = File('assets/maps/packs/mumbai.pmtiles');

    test('Bandra area: a real ~3 km drive', () async {
      // 19.04-19.08N, 72.82-72.86E covers Bandra; two points a few km apart.
      final graph = await buildRoadGraphFromPmtiles(
        fixture.path,
        south: 19.04,
        west: 72.82,
        north: 19.08,
        east: 72.86,
        zoom: 15,
      );
      expect(graph, isNotNull);

      const fromLat = 19.0550, fromLon = 72.8300;
      const toLat = 19.0700, toLon = 72.8400;
      final straightM = NavMath.horizontalDistance(
          lat0: fromLat, lon0: fromLon, lat1: toLat, lon1: toLon);

      final sw = Stopwatch()..start();
      final route = planRoute(graph!,
          fromLat: fromLat, fromLon: fromLon, toLat: toLat, toLon: toLon);
      sw.stop();
      print('planRoute over Bandra (${graph.edgeCount} edges): '
          '${sw.elapsedMilliseconds} ms');

      expect(route, isNotNull);
      expect(route!.lengthM, greaterThanOrEqualTo(straightM));
      expect(route.lengthM, lessThan(straightM * 2.5));
      expect(
          route.maneuvers.any((m) => m.roadName != null && m.roadName!.isNotEmpty),
          isTrue);

      for (var i = 0; i < route.pointCount; i += 5) {
        final near =
            graph.nearby(route.latAt(i), route.lonAt(i), radiusM: 30);
        expect(near, isNotEmpty,
            reason: 'vertex $i (${route.latAt(i)}, ${route.lonAt(i)}) is not '
                'near any graph edge');
      }
      expect(sw.elapsedMilliseconds, lessThan(3000));
    },
        skip: fixture.existsSync()
            ? false
            : 'assets/maps/packs/mumbai.pmtiles missing');
  });
}
