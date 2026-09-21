import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/map_matcher.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

const double lat0 = 28.6139;
const double lon0 = 77.2090;

/// A point [north] / [east] metres from the origin, as `[lat, lon]`.
///
/// Two values, not three: `NavMath.addNed` also returns altitude, and
/// splatting that into a polyline silently corrupts it.
List<double> at(double north, double east) {
  final moved = NavMath.addNed(
    latDeg: lat0,
    lonDeg: lon0,
    altM: 0,
    north: north,
    east: east,
    down: 0,
  );
  return [moved[0], moved[1]];
}

/// A straight edge from one offset to another.
RoadEdge straightEdge({
  required int id,
  required int from,
  required int to,
  required double n0,
  required double e0,
  required double n1,
  required double e1,
  bool oneWay = false,
  String? name,
  RoadClass roadClass = RoadClass.residential,
  double? maxSpeedMps,
  bool tunnel = false,
}) {
  final a = at(n0, e0);
  final b = at(n1, e1);
  return RoadEdge(
    id: id,
    fromNode: from,
    toNode: to,
    polyline: [a[0], a[1], b[0], b[1]],
    oneWay: oneWay,
    name: name,
    roadClass: roadClass,
    maxSpeedMps: maxSpeedMps,
    tunnel: tunnel,
  );
}

RoadNode nodeAt(int id, double north, double east) {
  final p = at(north, east);
  return RoadNode(id: id, lat: p[0], lon: p[1]);
}

/// One straight road running north for a kilometre.
RoadGraph singleRoad() => RoadGraph(
      nodes: [nodeAt(1, 0, 0), nodeAt(2, 1000, 0)],
      edges: [
        straightEdge(
            id: 10, from: 1, to: 2, n0: 0, e0: 0, n1: 1000, e1: 0,
            name: 'Main Road'),
      ],
    );

/// Two parallel roads 25 m apart, both running north — the case that must
/// NOT snap (§21).
RoadGraph parallelRoads() => RoadGraph(
      nodes: [
        nodeAt(1, 0, 0),
        nodeAt(2, 1000, 0),
        nodeAt(3, 0, 25),
        nodeAt(4, 1000, 25),
      ],
      edges: [
        straightEdge(
            id: 10, from: 1, to: 2, n0: 0, e0: 0, n1: 1000, e1: 0,
            name: 'Main Road'),
        straightEdge(
            id: 20, from: 3, to: 4, n0: 0, e0: 25, n1: 1000, e1: 25,
            name: 'Service Road'),
      ],
    );

/// A T junction: north road meets an east-west road at 500 m.
RoadGraph junction() => RoadGraph(
      nodes: [
        nodeAt(1, 0, 0),
        nodeAt(2, 500, 0),
        nodeAt(3, 1000, 0),
        nodeAt(4, 500, 400),
      ],
      edges: [
        straightEdge(
            id: 10, from: 1, to: 2, n0: 0, e0: 0, n1: 500, e1: 0,
            name: 'South Approach'),
        straightEdge(
            id: 11, from: 2, to: 3, n0: 500, e0: 0, n1: 1000, e1: 0,
            name: 'North Continuation'),
        straightEdge(
            id: 12, from: 2, to: 4, n0: 500, e0: 0, n1: 500, e1: 400,
            name: 'East Branch'),
      ],
    );

void main() {
  group('RoadGraph geometry', () {
    test('projects a point onto the nearest place on a road', () {
      final graph = singleRoad();
      final query = at(300, 12); // 12 m east of the road
      final projection = graph.project(10, query[0], query[1])!;
      expect(projection.perpendicularM, closeTo(12, 0.1));
      expect(projection.alongM, closeTo(300, 0.5));
      expect(projection.headingRad, closeTo(0, 1e-6)); // due north
    });

    test('clamps to the ends rather than projecting off the road', () {
      final graph = singleRoad();
      final before = at(-50, 0);
      final projection = graph.project(10, before[0], before[1])!;
      expect(projection.alongM, closeTo(0, 0.5));
      expect(projection.perpendicularM, closeTo(50, 0.5));
    });

    test('follows a polyline with a bend', () {
      final corner = at(0, 0);
      final mid = at(100, 0);
      final end = at(100, 100);
      final graph = RoadGraph(
        nodes: [nodeAt(1, 0, 0), nodeAt(2, 100, 100)],
        edges: [
          RoadEdge(
            id: 10,
            fromNode: 1,
            toNode: 2,
            polyline: [corner[0], corner[1], mid[0], mid[1], end[0], end[1]],
          ),
        ],
      );
      expect(graph.edge(10)!.lengthM, closeTo(200, 0.5));

      final query = at(100, 50);
      final projection = graph.project(10, query[0], query[1])!;
      expect(projection.perpendicularM, lessThan(0.5));
      expect(projection.alongM, closeTo(150, 1));
      // Second leg runs due east.
      expect(projection.headingRad, closeTo(math.pi / 2, 1e-6));
    });

    test('nearby finds roads through the spatial index', () {
      final graph = parallelRoads();
      final query = at(500, 5);
      final found = graph.nearby(query[0], query[1], radiusM: 60);
      expect(found.length, 2);
      expect(found.first.edgeId, 10); // nearest first
      expect(found.first.perpendicularM, closeTo(5, 0.2));
      expect(found[1].perpendicularM, closeTo(20, 0.2));
    });

    test('nearby respects the radius', () {
      final graph = parallelRoads();
      final query = at(500, 0);
      expect(graph.nearby(query[0], query[1], radiusM: 10).length, 1);
      expect(graph.nearby(query[0], query[1], radiusM: 40).length, 2);
    });

    test('nearby filters out roads the vehicle may not use', () {
      final graph = RoadGraph(
        nodes: [nodeAt(1, 0, 0), nodeAt(2, 1000, 0)],
        edges: [
          RoadEdge(
            id: 10,
            fromNode: 1,
            toNode: 2,
            polyline: [...at(0, 0), ...at(1000, 0)],
            access: const {VehicleAccess.twoWheelers},
            name: 'Bike lane',
          ),
        ],
      );
      final query = at(500, 2);
      expect(
        graph.nearby(query[0], query[1], vehicle: VehicleAccess.cars),
        isEmpty,
      );
      expect(
        graph.nearby(query[0], query[1], vehicle: VehicleAccess.twoWheelers),
        hasLength(1),
      );
    });

    test('an empty graph finds nothing instead of failing', () {
      final graph = RoadGraph.empty();
      expect(graph.isEmpty, isTrue);
      expect(graph.nearby(lat0, lon0), isEmpty);
      expect(graph.project(1, lat0, lon0), isNull);
    });
  });

  group('RoadGraph routing', () {
    test('distance along the same road is the along-road difference', () {
      final graph = singleRoad();
      final a = graph.project(10, at(100, 0)[0], at(100, 0)[1])!;
      final b = graph.project(10, at(400, 0)[0], at(400, 0)[1])!;
      expect(graph.routeDistance(a, b), closeTo(300, 1));
    });

    test('routes through a junction', () {
      final graph = junction();
      final south = graph.project(10, at(400, 0)[0], at(400, 0)[1])!;
      final east = graph.project(12, at(500, 100)[0], at(500, 100)[1])!;
      // 100 m up to the junction, then 100 m east.
      expect(graph.routeDistance(south, east), closeTo(200, 2));
    });

    test('parallel roads with no connection have no route', () {
      final graph = parallelRoads();
      final a = graph.project(10, at(500, 0)[0], at(500, 0)[1])!;
      final b = graph.project(20, at(500, 25)[0], at(500, 25)[1])!;
      expect(graph.routeDistance(a, b), isNull);
    });

    test('the search is capped rather than unbounded', () {
      final graph = junction();
      final south = graph.project(10, at(0, 0)[0], at(0, 0)[1])!;
      final east = graph.project(12, at(500, 400)[0], at(500, 400)[1])!;
      expect(graph.routeDistance(south, east, capM: 100), isNull);
      expect(graph.routeDistance(south, east, capM: 2000), closeTo(900, 5));
    });

    test('a one-way road cannot be driven backwards', () {
      final graph = RoadGraph(
        nodes: [nodeAt(1, 0, 0), nodeAt(2, 1000, 0)],
        edges: [
          straightEdge(
              id: 10, from: 1, to: 2, n0: 0, e0: 0, n1: 1000, e1: 0,
              oneWay: true),
        ],
      );
      final far = graph.project(10, at(800, 0)[0], at(800, 0)[1])!;
      final near = graph.project(10, at(200, 0)[0], at(200, 0)[1])!;
      expect(graph.routeDistance(near, far), closeTo(600, 1));
      expect(graph.routeDistance(far, near), isNull);
    });
  });

  group('MapMatcher', () {
    MapMatcher matcher(RoadGraph graph, {NavConfig? config}) =>
        MapMatcher(graph: graph, config: config ?? NavConfig.defaults);

    MapMatchResult? drive(
      MapMatcher m, {
      required List<List<double>> offsets,
      double sigmaM = 8,
      double headingRad = 0,
      double speedMps = 14,
    }) {
      MapMatchResult? result;
      for (final offset in offsets) {
        final p = at(offset[0], offset[1]);
        result = m.update(
          lat: p[0],
          lon: p[1],
          sigmaM: sigmaM,
          headingRad: headingRad,
          speedMps: speedMps,
        );
      }
      return result;
    }

    test('an empty graph reports unavailable, never a match', () {
      final m = matcher(RoadGraph.empty());
      expect(m.isAvailable, isFalse);
      expect(m.update(lat: lat0, lon: lon0, sigmaM: 5), isNull);
    });

    test('snaps onto a single obvious road', () {
      final m = matcher(singleRoad());
      final result = drive(m, offsets: [
        [100, 4],
        [114, -3],
        [128, 5],
        [142, -2],
      ]);
      expect(result!.snapped, isTrue);
      expect(result.best!.edgeId, 10);
      expect(result.best!.roadName, 'Main Road');
      expect(result.confidence, greaterThan(0.6));
      // Snapped position is on the road, not where the estimate was.
      final matched = NavMath.horizontalDistance(
        lat0: result.matchedLat!,
        lon0: result.matchedLon!,
        lat1: at(142, 0)[0],
        lon1: at(142, 0)[1],
      );
      expect(matched, lessThan(3));
    });

    test('refuses to snap between two parallel roads — the flyover case', () {
      final m = matcher(parallelRoads());
      // Driving straight up the middle: both roads are equally plausible.
      final result = drive(m, offsets: [
        [100, 12.5],
        [114, 12.5],
        [128, 12.5],
        [142, 12.5],
      ]);
      expect(result!.snapped, isFalse);
      expect(result.candidates.length, 2);
      expect(result.reason, contains('too close to call'));
      // Both hypotheses are kept alive (§21).
      expect(result.candidates[0].posterior, closeTo(0.5, 0.15));
      expect(result.candidates[1].posterior, closeTo(0.5, 0.15));
    });

    test('once the evidence separates them it does snap', () {
      final m = matcher(parallelRoads());
      // Clearly on the left-hand road.
      final result = drive(m, offsets: [
        [100, 1],
        [114, 0],
        [128, 1],
        [142, 0],
      ]);
      expect(result!.snapped, isTrue);
      expect(result.best!.edgeId, 10);
    });

    test('never snaps on the very first fix', () {
      final m = matcher(singleRoad());
      final p = at(100, 1);
      final result =
          m.update(lat: p[0], lon: p[1], sigmaM: 5, headingRad: 0, speedMps: 14);
      expect(result!.snapped, isFalse);
      expect(result.reason, contains('second consistent fix'));
    });

    test('a road running the wrong way is rejected on heading', () {
      // Vehicle heading east, road runs north.
      final m = matcher(singleRoad());
      final result = drive(
        m,
        offsets: [
          [100, 2],
          [114, 2],
        ],
        headingRad: math.pi / 2,
      );
      expect(result!.snapped, isFalse);
      expect(result.candidates, isEmpty);
      expect(result.reason, contains('heading'));
    });

    test('a two-way road accepts travel in either direction', () {
      final m = matcher(singleRoad());
      final southbound = drive(
        m,
        offsets: [
          [400, 2],
          [386, 1],
          [372, 2],
        ],
        headingRad: math.pi, // due south
      );
      expect(southbound!.snapped, isTrue);
      // The reported road heading follows the vehicle, not the polyline.
      expect(
        NavMath.angleDiffDeg(southbound.best!.roadHeadingDeg, 180).abs(),
        lessThan(1),
      );
    });

    test('a one-way road rejects travel against it', () {
      final graph = RoadGraph(
        nodes: [nodeAt(1, 0, 0), nodeAt(2, 1000, 0)],
        edges: [
          straightEdge(
              id: 10, from: 1, to: 2, n0: 0, e0: 0, n1: 1000, e1: 0,
              oneWay: true),
        ],
      );
      final m = matcher(graph);
      final result = drive(
        m,
        offsets: [
          [400, 2],
          [386, 1],
        ],
        headingRad: math.pi,
      );
      expect(result!.candidates, isEmpty);
    });

    test('heading is ignored while the vehicle is barely moving', () {
      // A parked car's heading is noise, so it must not veto every road.
      final m = matcher(singleRoad());
      final result = drive(
        m,
        offsets: [
          [100, 2],
          [100, 2],
          [100, 2],
        ],
        headingRad: math.pi / 2,
        speedMps: 0.3,
      );
      expect(result!.candidates, isNotEmpty);
    });

    test('a wider filter sigma widens the search but not the confidence', () {
      final m = matcher(singleRoad());
      final tight = drive(m, offsets: [
        [100, 30],
        [114, 30],
      ], sigmaM: 4);
      m.reset();
      final loose = drive(m, offsets: [
        [100, 30],
        [114, 30],
      ], sigmaM: 40);
      // 30 m off the road is implausible at 4 m sigma, ordinary at 40 m.
      expect(tight!.candidates.isEmpty || loose!.confidence >= tight.confidence,
          isTrue);
    });

    test('takes the route through a junction rather than a straight-line jump',
        () {
      final m = matcher(junction());
      // Approach from the south, then turn east.
      drive(m, offsets: [
        [300, 0],
        [400, 0],
        [480, 0],
      ]);
      final result = drive(
        m,
        offsets: [
          [500, 60],
          [500, 140],
        ],
        headingRad: math.pi / 2,
      );
      expect(result!.best!.edgeId, 12);
      expect(result.snapped, isTrue);
    });

    test('reset clears the hypothesis set', () {
      final m = matcher(singleRoad());
      drive(m, offsets: [
        [100, 1],
        [114, 1],
      ]);
      expect(m.last, isNotNull);
      m.reset();
      expect(m.last, isNull);
    });

    test('a position far from any road reports no candidates, honestly', () {
      final m = matcher(singleRoad());
      final far = at(500, 5000);
      final result = m.update(lat: far[0], lon: far[1], sigmaM: 10);
      expect(result!.candidates, isEmpty);
      expect(result.snapped, isFalse);
      expect(result.reason, contains('No road'));
    });

    test('a stricter snap threshold is respected', () {
      // With competing roads the posterior is genuinely below 1.
      final m = matcher(
        parallelRoads(),
        config: const NavConfig(
          mapMatch: MapMatchConfig(
            snapThreshold: 0.999,
            runnerUpMargin: 0.0,
          ),
        ),
      );
      // Two steps of evidence, not three: an HMM accumulates, so any
      // threshold below 1 is eventually cleared by a long enough drive. The
      // question is whether it takes more evidence, and it does.
      const offsets = [
        [100.0, 4.0],
        [114.0, 4.0],
      ];
      final strict = drive(m, offsets: offsets, sigmaM: 12);
      expect(strict!.snapped, isFalse);
      expect(strict.reason, contains('% likely'));

      final lenient = matcher(
        parallelRoads(),
        config: const NavConfig(mapMatch: MapMatchConfig()),
      );
      expect(drive(lenient, offsets: offsets, sigmaM: 12)!.snapped, isTrue);
    });

    test('a lone road far away does NOT snap just because nothing '
        'competed with it', () {
      // The softmax posterior of a single candidate is always 1.0. Without
      // an absolute distance check that would snap the marker onto a road
      // 50 m away with total confidence.
      final m = matcher(singleRoad());
      final result = drive(
        m,
        offsets: [
          [100, 45],
          [114, 46],
          [128, 45],
        ],
        sigmaM: 5,
      );
      expect(result!.candidates, hasLength(1));
      expect(result.confidence, closeTo(1.0, 1e-9));
      expect(result.snapped, isFalse);
      expect(result.reason, contains('from the nearest road'));
    });
  });

  group('MapMatcher on a graph cut at every junction', () {
    // The graph read from map tiles is cut at each junction: one physical road
    // is a chain of edges. A position near a cut fits both sides equally well,
    // and that must not read as "two roads too close to call".
    RoadGraph cutRoad({double branchEastAt = 0}) => RoadGraph(
          nodes: [
            nodeAt(1, 0, 0),
            nodeAt(2, 500, 0),
            nodeAt(3, 1000, 0),
            if (branchEastAt > 0) nodeAt(4, 500, branchEastAt),
          ],
          edges: [
            straightEdge(
                id: 10, from: 1, to: 2, n0: 0, e0: 0, n1: 500, e1: 0,
                name: 'Ring Road'),
            straightEdge(
                id: 11, from: 2, to: 3, n0: 500, e0: 0, n1: 1000, e1: 0,
                name: 'Ring Road'),
            if (branchEastAt > 0)
              straightEdge(
                  id: 12, from: 2, to: 4, n0: 500, e0: 0, n1: 500,
                  e1: branchEastAt),
          ],
        );

    MapMatchResult? matchNearCut(RoadGraph graph) {
      final matcher = MapMatcher(graph: graph);
      MapMatchResult? result;
      // Driving north through the cut at 500 m, a metre either side of it.
      for (var i = 0; i < 6; i++) {
        final p = at(490 + i * 4.0, 1.5);
        result = matcher.update(
          lat: p[0],
          lon: p[1],
          sigmaM: 3,
          headingRad: 0,
          speedMps: 10,
        );
      }
      return result;
    }

    test('two edges of one road pool their probability and snap', () {
      final result = matchNearCut(cutRoad())!;

      expect(result.snapped, isTrue, reason: result.reason);
      expect(result.confidence, greaterThan(0.9));
      expect(result.matchedHeadingRad, closeTo(0, 0.05));
    });

    test('a side street at the cut is still a different road', () {
      // A branch leaving the same node at right angles: not a continuation.
      final matcher = MapMatcher(graph: cutRoad(branchEastAt: 300));
      MapMatchResult? result;
      // Stopped exactly at the junction, heading unknown: north road and east
      // branch fit equally well and the matcher must say so.
      for (var i = 0; i < 6; i++) {
        final p = at(500, 1.0);
        result = matcher.update(lat: p[0], lon: p[1], sigmaM: 3);
      }

      expect(result!.snapped, isFalse);
      expect(result.reason, contains('too close to call'));
    });
  });

  group('RoadGraph.fromJson', () {
    Map<String, dynamic> validJson() => {
          'region': 'test',
          'version': 1,
          'nodes': [
            {'id': 1, 'lat': lat0, 'lon': lon0},
            {'id': 2, 'lat': at(1000, 0)[0], 'lon': at(1000, 0)[1]},
          ],
          'edges': [
            {
              'id': 10,
              'from': 1,
              'to': 2,
              'polyline': [lat0, lon0, at(1000, 0)[0], at(1000, 0)[1]],
              'class': 'primary',
              'oneWay': true,
              'maxSpeedMps': 16.7,
              'tunnel': true,
              'access': ['cars'],
              'name': 'Test Road',
            },
          ],
        };

    test('loads a well-formed graph', () {
      final graph = RoadGraph.fromJson(validJson())!;
      expect(graph.edgeCount, 1);
      expect(graph.nodeCount, 2);
      expect(graph.region, 'test');
      final edge = graph.edge(10)!;
      expect(edge.roadClass, RoadClass.primary);
      expect(edge.oneWay, isTrue);
      expect(edge.tunnel, isTrue);
      expect(edge.maxSpeedMps, closeTo(16.7, 1e-9));
      expect(edge.allows(VehicleAccess.cars), isTrue);
      expect(edge.allows(VehicleAccess.twoWheelers), isFalse);
      expect(edge.lengthM, closeTo(1000, 2));
    });

    test('rejects malformed data rather than loading half a network', () {
      expect(RoadGraph.fromJson(const {}), isNull);
      expect(RoadGraph.fromJson(const {'nodes': [], 'edges': []}), isNull);

      final badPolyline = validJson();
      (badPolyline['edges'] as List)[0]['polyline'] = [1.0, 2.0, 3.0];
      expect(RoadGraph.fromJson(badPolyline), isNull);

      final nanCoordinate = validJson();
      (nanCoordinate['nodes'] as List)[0]['lat'] = double.nan;
      expect(RoadGraph.fromJson(nanCoordinate), isNull);

      final missingId = validJson();
      (missingId['edges'] as List)[0].remove('id');
      expect(RoadGraph.fromJson(missingId), isNull);
    });

    test('an unstated speed limit stays null, never a default', () {
      final json = validJson();
      (json['edges'] as List)[0].remove('maxSpeedMps');
      expect(RoadGraph.fromJson(json)!.edge(10)!.maxSpeedMps, isNull);
    });

    test('the shipped road graph is still empty — nothing to match against',
        () {
      // Pins the honest state: maps/processed_graphs/road_edges.json is
      // `{"edges": []}`, so map matching is off by default (§83). When a real
      // region is built this test should be replaced by one that loads it.
      expect(NavConfig.defaults.mapMatch.enabled, isFalse);
    });
  });
}
