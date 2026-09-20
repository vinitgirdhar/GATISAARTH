import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_follower.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

import 'support/road_follower_fixtures.dart';

void main() {
  group('config', () {
    test('lives in NavConfig with the documented defaults', () {
      const c = NavConfig();
      expect(c.roadFollow.headingWeightMPerDeg, 0.1);
      expect(c.roadFollow.joinToleranceM, 3.0);
      expect(c.roadFollow.maxHopsPerAdvance, 64);
      final tuned =
          c.copyWith(roadFollow: const RoadFollowConfig(joinToleranceM: 5));
      expect(tuned.roadFollow.joinToleranceM, 5);
      expect(tuned.mapMatch, same(c.mapMatch));
    });
  });

  group('walking one edge', () {
    test('advances along a straight edge and reports the travel heading', () {
      final f = lockedAt(
          graphOf([
            road(1, [
              [0, 0],
              [1000, 0]
            ])
          ]),
          0,
          0,
          heading: 0);
      expect(f.isLocked, isTrue);
      expect(f.advance(100), closeTo(100, 1e-6));
      expectAt(f, 100, 0, tol: 0.01);
      expectHeading(f, 0, tol: 0.01);
      expect(f.position!.alongM, closeTo(100, 0.01));
      expect(f.position!.edgeId, 1);
    });

    test('a dead end returns short, stays locked and retries after a rebind',
        () {
      final f = lockedAt(
          graphOf([
            road(1, [
              [0, 0],
              [100, 0]
            ])
          ]),
          10,
          0,
          heading: 0);
      expect(f.advance(150), closeTo(90, 1e-6));
      expect(f.isLocked, isTrue);
      expectAt(f, 100, 0, tol: 0.01);
      expect(f.advance(10), 0);
      expectAt(f, 100, 0, tol: 0.01);

      // The rebuilt graph now has road beyond the old end.
      f.graph = graphOf([
        road(1, [
          [0, 0],
          [100, 0]
        ]),
        road(2, [
          [100, 0],
          [300, 0]
        ]),
      ]);
      expect(f.isLocked, isTrue);
      expect(f.advance(50), closeTo(50, 1e-6));
      expect(f.position!.edgeId, 2);
      expectAt(f, 150, 0, tol: 0.01);
    });

    test('a two-way edge can be driven from its far end backwards', () {
      final f = lockedAt(
          graphOf([
            road(1, [
              [0, 0],
              [200, 0]
            ])
          ]),
          150,
          0,
          heading: 180);
      expect(f.advance(100), closeTo(100, 1e-6));
      expectAt(f, 50, 0, tol: 0.01);
      expectHeading(f, 180, tol: 0.01);
      expect(f.advance(100), closeTo(50, 1e-6)); // ran out at the start
    });

    test('a long many-vertex edge is walked without leaving it', () {
      final g = graphOf([road(1, windingRoad())]);
      final f = lockedAt(g, 0, 0, heading: 0);
      var total = 0.0;
      for (var i = 0; i < 5000; i++) {
        total += f.advance(1);
        if (i % 10 != 0) continue;
        final p = f.position!;
        expect(g.nearby(p.lat, p.lon, radiusM: 0.05).isNotEmpty, isTrue,
            reason: 'off the road at step $i');
      }
      expect(total, closeTo(5000, 40)); // the sinuous edge is a bit longer
    });
  });

  group('joining edges by geometry', () {
    for (final gap in [0.0, 2.0]) {
      test('passes through collinear edges across a $gap m gap', () {
        final f = lockedAt(
            graphOf([
              road(1, [
                [0, 0],
                [100, 0]
              ]),
              road(2, [
                [100 + gap, 0],
                [300, 0]
              ]),
            ]),
            10,
            0,
            heading: 0);
        expect(f.advance(150), closeTo(150, 1e-6));
        expect(f.position!.edgeId, 2);
        expectAt(f, 160 + gap, 0, tol: 0.05);
        expectHeading(f, 0, tol: 0.01);
      });
    }

    for (final skew in [0.0, 1.0]) {
      test('tile-border overlap is seamless (copy offset $skew m)', () {
        // A ends at P (n=200). The neighbour tile's copy B starts 15 m
        // BEFORE P and runs on for 300 m.
        final g = graphOf([
          road(
              1,
              [
                [0, 0],
                [200, 0]
              ],
              name: 'Ring Road'),
          road(
              2,
              [
                [185, skew],
                [485, skew]
              ],
              name: 'Ring Road'),
        ]);
        final f = lockedAt(g, 0, 0, heading: 0);
        var last = 0.0;
        final edges = <int>{};
        for (var i = 0; i < 400; i++) {
          expect(f.advance(1), closeTo(1, 1e-9), reason: 'stalled at $i');
          final n = offsetOf(f.position!).n;
          expect(n - last, closeTo(1, 0.05), reason: 'jump at step $i');
          last = n;
          expectHeading(f, 0, tol: 0.5);
          edges.add(f.position!.edgeId);
        }
        expect(edges, {1, 2});
        expectAt(f, 400, skew, tol: 0.05);
      });
    }

    test('a closed ring edge keeps going round, both ways', () {
      final ring = [
        [0.0, 0.0],
        [0.0, 100.0],
        [100.0, 100.0],
        [100.0, 0.0],
        [0.0, 0.0],
      ];
      for (final heading in [90.0, 270.0]) {
        final g = graphOf([road(1, ring)]);
        final f = lockedAt(g, 0, 50, heading: heading);
        var total = 0.0;
        for (var i = 0; i < 1000; i++) {
          total += f.advance(1);
          final p = f.position!;
          expect(g.nearby(p.lat, p.lon, radiusM: 0.1).isNotEmpty, isTrue);
        }
        expect(total, closeTo(1000, 1e-6), reason: 'heading $heading');
      }
    });

    test('a duplicated edge does not make the vehicle turn round', () {
      final f = lockedAt(
          graphOf([
            road(1, [
              [0, 0],
              [100, 0]
            ]),
            road(2, [
              [0, 0],
              [100, 0]
            ]),
          ]),
          50,
          0,
          heading: 0);
      expect(f.advance(200), closeTo(50, 1e-6));
      expectAt(f, 100, 0, tol: 0.01);
    });
  });

  group('junctions', () {
    test('a T picks a side, stays on the road and never U-turns', () {
      final g = graphOf([
        road(
            1,
            [
              [-100, 0],
              [0, 0]
            ],
            name: 'Stem'),
        road(
            2,
            [
              [0, -100],
              [0, 100]
            ],
            name: 'Bar'),
      ]);
      final f = lockedAt(g, -100, 0, heading: 0);
      expect(f.advance(150), closeTo(150, 1e-6));
      expect(f.position!.edgeId, 2);
      final o = offsetOf(f.position!);
      expect(o.n, closeTo(0, 0.05));
      expect(o.e.abs(), closeTo(50, 0.05));
      final h = f.position!.headingDeg;
      expect(h > 89 && h < 91 || h > 269 && h < 271, isTrue, reason: '$h');
      // Only 50 m of the bar is left; a U-turn would give more.
      expect(f.advance(1000), closeTo(50, 1e-3));
    });

    test('a fork follows the small turn the driver made', () {
      final r = 20 * math.pi / 180;
      final g = graphOf([
        road(1, [
          [-100, 0],
          [0, 0]
        ]),
        road(2, [
          [0, 0],
          [100 * math.cos(r), 100 * math.sin(r)]
        ]),
        road(3, [
          [0, 0],
          [100 * math.cos(r), -100 * math.sin(r)]
        ]),
      ]);
      for (final c in [(15.0, 2, 20.0), (-15.0, 3, 340.0)]) {
        final f = lockedAt(g, -100, 0, heading: 0);
        f.advance(99.5);
        f.advance(10, yawDeg: c.$1);
        expect(f.position!.edgeId, c.$2, reason: 'yaw ${c.$1}');
        expectHeading(f, c.$3, tol: 0.5);
      }
    });

    test('4-way at an edge end: yaw 0 straight, +90 right, -90 left', () {
      for (final c in [(0.0, 2, 0.0), (90.0, 3, 90.0), (-90.0, 4, 270.0)]) {
        final f = lockedAt(fourWay(), -100, 0, heading: 0);
        f.advance(99.5);
        expect(f.advance(10, yawDeg: c.$1), closeTo(10, 1e-6));
        expect(f.position!.edgeId, c.$2, reason: 'yaw ${c.$1}');
        expectHeading(f, c.$3, tol: 0.5);
        expect(f.unexplainedYawDeg.abs(), lessThan(1),
            reason: 'the turn was taken, nothing left over');
      }
    });

    test('4-way, a turn spread over the last 10 m of the approach', () {
      for (final c in [(90.0, 3, 90.0, 0.0), (-90.0, 4, 270.0, 0.0)]) {
        final f = lockedAt(fourWay(), -100, 0, heading: 0);
        f.advance(90);
        steer(f, 10, totalYawDeg: c.$1);
        expect(f.position!.edgeId, c.$2, reason: 'yaw ${c.$1}');
        expectHeading(f, c.$3, tol: 1);
        expect(offsetOf(f.position!).n, closeTo(c.$4, 0.5));
        f.advance(50);
        expect(f.position!.edgeId, c.$2, reason: 'and it stays there');
        expect(f.unexplainedYawDeg.abs(), lessThan(3));
      }
    });

    test('4-way crossing inside one long edge: straight, left and right', () {
      final cases = [
        (0.0, 1, 90.0),
        (-90.0, 2, 0.0),
        (90.0, 3, 180.0),
      ];
      for (final c in cases) {
        final f = lockedAt(midEdgeCrossing(), 0, -100, heading: 90);
        f.advance(90);
        steer(f, 10, totalYawDeg: c.$1);
        f.advance(40);
        expect(f.position!.edgeId, c.$2, reason: 'yaw ${c.$1}');
        expectHeading(f, c.$3, tol: 1);
        if (c.$1 == 0) expectAt(f, 0, 40, tol: 0.05);
      }
    });

    test('a turn fed in one call at a mid-edge crossing is found too', () {
      final f = lockedAt(midEdgeCrossing(), 0, -100, heading: 90);
      f.advance(105);
      f.advance(1, yawDeg: -90);
      expect(f.position!.edgeId, 2);
      expectHeading(f, 0, tol: 0.5);
    });

    test('at 45 degrees the same name wins, then the higher road class', () {
      int taken(RoadGraph g) {
        final f = lockedAt(g, -100, 0, heading: 0);
        f.advance(99.5);
        f.advance(10, yawDeg: 45);
        return f.position!.edgeId;
      }

      expect(taken(fourWay()), 2); // Main -> Main, not Cross
      final unnamed = fourWay(
          southName: null, northName: null, eastClass: RoadClass.primary);
      expect(taken(unnamed), 3);
    });

    test('a one-way is never entered against its direction', () {
      // B is digitised southwards; arriving from the south the only way on
      // would be backwards along it.
      final g = graphOf([
        road(1, [
          [0, 0],
          [100, 0]
        ]),
        road(
            2,
            [
              [200, 0],
              [100, 0]
            ],
            oneWay: true),
      ]);
      final f = lockedAt(g, 0, 0, heading: 0);
      expect(f.advance(300), closeTo(100, 1e-6));
      expect(f.position!.edgeId, 1);
    });

    test('at a T the one-way side is the only one taken', () {
      final g = graphOf([
        road(1, [
          [-100, 0],
          [0, 0]
        ]),
        road(
            2,
            [
              [0, 200],
              [0, -200]
            ],
            oneWay: true), // runs westwards
      ]);
      final f = lockedAt(g, -100, 0, heading: 0);
      f.advance(150);
      expect(f.position!.edgeId, 2);
      expectHeading(f, 270, tol: 0.5);
      expectAt(f, 0, -50, tol: 0.05);
    });
  });

  group('lock', () {
    test('picks the direction consistent with the heading', () {
      final g = graphOf([
        road(1, [
          [0, 0],
          [1000, 0]
        ])
      ]);
      final north = lockedAt(g, 500, 3, heading: 10);
      final south = lockedAt(g, 500, 3, heading: 190);
      expectHeading(north, 0, tol: 0.01);
      expectHeading(south, 180, tol: 0.01);
      south.advance(100);
      expectAt(south, 400, 0, tol: 0.01);
    });

    test('a one-way forces its own direction whatever the heading', () {
      final f = lockedAt(
          graphOf([
            road(
                1,
                [
                  [0, 0],
                  [1000, 0]
                ],
                oneWay: true)
          ]),
          500,
          2,
          heading: 180);
      expectHeading(f, 0, tol: 0.01);
      f.advance(10);
      expectAt(f, 510, 0, tol: 0.01);
    });

    test(
        'prefers the nearer parallel road unless heading strongly favours the other',
        () {
      final g = graphOf([
        road(1, [
          [0, 0],
          [1000, 0]
        ]),
        road(2, [
          [0, 25],
          [1000, 25]
        ]),
      ]);
      expect(lockedAt(g, 500, 8, heading: 0).position!.edgeId, 1);
      expect(lockedAt(g, 500, 17, heading: 0).position!.edgeId, 2);
      // 5 m from a northbound one-way, 20 m from a southbound one.
      final oneWays = graphOf([
        road(
            1,
            [
              [0, 0],
              [1000, 0]
            ],
            oneWay: true),
        road(
            2,
            [
              [1000, 25],
              [0, 25]
            ],
            oneWay: true),
      ]);
      expect(lockedAt(oneWays, 500, 5, heading: 0).position!.edgeId, 1);
      expect(lockedAt(oneWays, 500, 5, heading: 180).position!.edgeId, 2);
    });

    test('snaps the position onto the road', () {
      final f = lockedAt(
          graphOf([
            road(1, [
              [0, 0],
              [1000, 0]
            ])
          ]),
          500,
          7);
      expectAt(f, 500, 0, tol: 0.01);
      expectHeading(f, 0, tol: 0.01); // no heading given: digitised direction
    });

    test('fails beyond the radius and leaves the state as it was', () {
      final g = graphOf([
        road(1, [
          [0, 0],
          [1000, 0]
        ]),
        road(2, [
          [0, 500],
          [1000, 500]
        ]),
      ]);
      final f = lockedAt(g, 500, 0, heading: 0);
      final far = pointAt(500, 250);
      expect(f.lock(lat: far[0], lon: far[1], maxRadiusM: 40), isFalse);
      expect(f.position!.edgeId, 1);
      expectAt(f, 500, 0, tol: 0.01);

      final fresh = RoadFollower(graph: g);
      expect(fresh.lock(lat: far[0], lon: far[1]), isFalse);
      expect(fresh.isLocked, isFalse);
      expect(fresh.position, isNull);
    });

    test('respects the vehicle filter', () {
      final g = graphOf([
        road(1, [
          [0, 0],
          [1000, 0]
        ], access: const {
          VehicleAccess.cars
        }),
      ]);
      final p = pointAt(500, 0);
      final bike = RoadFollower(graph: g, vehicle: VehicleAccess.twoWheelers);
      expect(bike.lock(lat: p[0], lon: p[1]), isFalse);
      final car = RoadFollower(graph: g, vehicle: VehicleAccess.cars);
      expect(car.lock(lat: p[0], lon: p[1]), isTrue);
    });
  });

  group('graph rebind', () {
    test('keeps position and the unexplained turn across new edge ids', () {
      final f = lockedAt(
          graphOf([
            road(10, [
              [0, 0],
              [1000, 0]
            ])
          ]),
          100,
          0,
          heading: 0);
      f.advance(200);
      f.advance(0, yawDeg: 12);
      final before = f.position!;

      f.graph = graphOf([
        road(77, [
          [0, 0],
          [500, 0]
        ]),
        road(78, [
          [500, 0],
          [1000, 0]
        ]),
      ]);
      expect(f.isLocked, isTrue);
      expect(f.position!.edgeId, 77);
      expect(f.position!.lat, closeTo(before.lat, 1e-8));
      expect(f.position!.lon, closeTo(before.lon, 1e-8));
      expectHeading(f, 0, tol: 0.01);
      expect(f.unexplainedYawDeg, closeTo(12, 1e-9));

      expect(f.advance(300), closeTo(300, 1e-6));
      expect(f.position!.edgeId, 78);
      expectAt(f, 600, 0, tol: 0.05);
    });

    test('unlocks when the road is not in the new graph', () {
      final f = lockedAt(
          graphOf([
            road(1, [
              [0, 0],
              [1000, 0]
            ])
          ]),
          100,
          0);
      f.graph = graphOf([
        road(5, [
          [0, 20],
          [1000, 20]
        ])
      ]); // 20 m away
      expect(f.isLocked, isFalse);
      expect(f.position, isNull);
      expect(f.advance(10), 0);
      f.graph = null;
      expect(f.graph, isNull);

      final g = graphOf([
        road(1, [
          [0, 0],
          [1000, 0]
        ])
      ]);
      final released = lockedAt(g, 500, 0)..release();
      expect(released.isLocked, isFalse);
      expect(released.advance(10), 0);
    });
  });

  group('correct', () {
    RoadFollower atHundred({double heading = 0, double n = 100}) => lockedAt(
        graphOf([
          road(1, [
            [0, 0],
            [1000, 0]
          ])
        ]),
        n,
        0,
        heading: heading);

    test('pulls along-track, by the gain, capped by the step', () {
      final f = atHundred();
      final small = pointAt(130, 4);
      expect(f.correct(small[0], small[1], sigmaM: 5), isTrue);
      expect(f.position!.alongM, closeTo(109, 0.05)); // 0.3 * 30

      final far = pointAt(400, 4);
      expect(f.correct(far[0], far[1], sigmaM: 5), isTrue);
      expect(f.position!.alongM, closeTo(121, 0.05)); // capped at 12
      expectAt(f, 121, 0, tol: 0.05);
    });

    test('a fix behind pulls the vehicle back', () {
      final f = atHundred();
      final behind = pointAt(90, 0);
      expect(f.correct(behind[0], behind[1], sigmaM: 5, gain: 0.5), isTrue);
      expect(f.position!.alongM, closeTo(95, 0.05));
    });

    test('works in the travel direction on a backwards drive', () {
      final f = atHundred(heading: 180, n: 500);
      final ahead = pointAt(400, 2); // ahead of a southbound vehicle
      expect(f.correct(ahead[0], ahead[1], sigmaM: 5), isTrue);
      expect(f.position!.alongM, closeTo(488, 0.05));
      final behind = pointAt(550, 2);
      expect(f.correct(behind[0], behind[1], sigmaM: 5), isTrue);
      expect(f.position!.alongM, closeTo(500, 0.05));
    });

    test('refuses a fix too far off the road, unless sigma is huge', () {
      final f = atHundred();
      final off = pointAt(200, 60);
      expect(f.correct(off[0], off[1], sigmaM: 5), isFalse);
      expect(f.position!.alongM, closeTo(100, 1e-6));
      expect(f.correct(off[0], off[1], sigmaM: 40), isTrue);
      expect(f.position!.alongM, greaterThan(100));
    });

    test('never runs off the end of the edge', () {
      final f = lockedAt(
          graphOf([
            road(1, [
              [0, 0],
              [100, 0]
            ])
          ]),
          95,
          0,
          heading: 0);
      final beyond = pointAt(115, 0); // 15 m past the end, still on the road
      expect(f.correct(beyond[0], beyond[1], sigmaM: 5, gain: 3, maxStepM: 50),
          isTrue);
      expect(f.position!.alongM, closeTo(100, 1e-9));
      expect(f.correct(double.nan, 0, sigmaM: 5), isFalse);
    });
  });

  group('bad input', () {
    test('NaN, infinite and negative distances travel nothing', () {
      final f = lockedAt(
          graphOf([
            road(1, [
              [0, 0],
              [1000, 0]
            ])
          ]),
          100,
          0,
          heading: 0);
      for (final m in [double.nan, double.infinity, -5.0, 0.0]) {
        expect(f.advance(m), 0, reason: '$m');
        expectAt(f, 100, 0, tol: 1e-6);
      }
      expect(f.advance(10, yawDeg: double.nan), closeTo(10, 1e-9));
      expect(f.unexplainedYawDeg.isFinite, isTrue);
      expect(f.advance(double.nan, yawDeg: 20), 0);
      expect(f.unexplainedYawDeg, closeTo(20, 1e-9)); // yaw still accumulates
    });

    test('lock rejects non-finite positions', () {
      final f = RoadFollower(
          graph: graphOf([
        road(1, [
          [0, 0],
          [100, 0]
        ])
      ]));
      expect(f.lock(lat: double.nan, lon: originLon), isFalse);
      expect(f.lock(lat: originLat, lon: double.infinity), isFalse);
      expect(f.lock(lat: originLat, lon: originLon, maxRadiusM: double.nan),
          isFalse);
      expect(f.isLocked, isFalse);
    });

    test('an empty or missing graph never locks or moves', () {
      final none = RoadFollower();
      expect(none.lock(lat: originLat, lon: originLon), isFalse);
      expect(none.advance(10), 0);
      expect(
          none.correct(originLat, originLon, sigmaM: 5), isFalse); // unlocked
      final empty = RoadFollower(graph: RoadGraph.empty());
      expect(empty.lock(lat: originLat, lon: originLon), isFalse);
    });

    test('a zero-length edge does not hang or produce NaN', () {
      final f = RoadFollower(
          graph: graphOf([
        road(1, [
          [0, 0],
          [0, 0]
        ]),
        road(2, [
          [0, 0],
          [50, 0],
          [50, 0],
          [100, 0]
        ]),
      ]));
      final p = pointAt(20, 0);
      expect(f.lock(lat: p[0], lon: p[1], headingDeg: 0), isTrue);
      expect(f.advance(200), closeTo(80, 1e-3));
      expect(
          f.position!.lat.isFinite && f.position!.headingDeg.isFinite, isTrue);
    });
  });
}
