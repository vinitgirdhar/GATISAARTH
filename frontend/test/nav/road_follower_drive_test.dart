import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_follower.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';

import 'support/road_follower_fixtures.dart';

void main() {
  group('turn accounting', () {
    /// A 100 m radius arc from the origin, north then curving to east,
    /// vertices every ~2 m, plus a street crossing it at 30 degrees round.
    RoadGraph arcWorld() {
      const r = 100.0;
      final pts = <List<double>>[
        for (var k = 0; k <= 78; k++)
          [
            r * math.sin(k / 78 * math.pi / 2),
            r - r * math.cos(k / 78 * math.pi / 2),
          ],
      ];
      return graphOf([
        road(1, pts, name: 'Bend'),
        road(
            2,
            [
              [100, -73.2],
              [0, 100]
            ],
            name: 'Cut'),
      ]);
    }

    test('yaw equal to the road curvature does not trigger a turn', () {
      final f = lockedAt(arcWorld(), 0, 0, heading: 0);
      for (var i = 0; i < 300; i++) {
        f.advance(0.5, yawDeg: 0.5 / 100 * 180 / math.pi);
        expect(f.position!.edgeId, 1, reason: 'left the bend at step $i');
        expect(f.unexplainedYawDeg.abs(), lessThan(2.5), reason: 'step $i');
      }
      expectHeading(f, 150 / 100 * 180 / math.pi, tol: 2);
    });

    test('with no yaw at all the follower never changes edge mid-edge', () {
      final f = lockedAt(arcWorld(), 0, 0, heading: 0);
      var total = 0.0;
      for (var i = 0; i < 300; i++) {
        total += f.advance(0.5);
        expect(f.position!.edgeId, 1, reason: 'left the bend at step $i');
      }
      expect(total, closeTo(150, 1e-6));
      expectHeading(f, 150 / 100 * 180 / math.pi, tol: 2);
    });

    test('no yaw and a sharp bend beside a through road stays on the bend', () {
      // North road bends hard east at 100 m; a through road goes straight on.
      // The vehicle reports no yaw, so it follows its edge round the bend.
      final g = graphOf([
        road(1, [
          [0, 0],
          [100, 0],
          [100, 300]
        ]),
        road(2, [
          [100, 0],
          [400, 0]
        ]),
      ]);
      final f = lockedAt(g, 0, 0, heading: 0);
      for (var i = 0; i < 200; i++) {
        f.advance(1);
        expect(f.position!.edgeId, 1, reason: 'step $i');
      }
      expectAt(f, 100, 100, tol: 0.05);
    });

    test('a small gyro bias on a straight road never turns the vehicle', () {
      final g = graphOf([
        road(1, [
          [0, 0],
          [2000, 0]
        ]),
        road(2, [
          [1000, -300],
          [1000, 300]
        ]),
      ]);
      final f = lockedAt(g, 0, 0, heading: 0);
      for (var i = 0; i < 1100; i++) {
        f.advance(1, yawDeg: 0.02);
        expect(f.position!.edgeId, 1, reason: 'step $i');
        expect(f.unexplainedYawDeg.abs(), lessThan(5));
      }
      expectAt(f, 1100, 0, tol: 0.05);
    });

    test('turning left where the road only bends right is not lost', () {
      // Bend right at 100 m, but the vehicle turns LEFT onto a side road that
      // starts mid-edge just before it.
      final g = graphOf([
        road(1, [
          [0, 0],
          [100, 0],
          [100, 300]
        ]),
        road(2, [
          [60, 0],
          [60, -300]
        ]),
      ]);
      final f = lockedAt(g, 0, 0, heading: 0);
      f.advance(50);
      steer(f, 10, totalYawDeg: -90);
      f.advance(20);
      expect(f.position!.edgeId, 2);
      expectHeading(f, 270, tol: 1);
    });
  });

  group('property and performance', () {
    /// One deterministic drive of the grid. A driver who reaches a dead end
    /// turns round, so all of the run is spent on roads and at crossings
    /// instead of parked at the first boundary.
    ({RoadFollower f, double travelled, int switches, int offRoad}) drive(
      RoadGraph g,
      List<double> yaw, {
      bool check = false,
    }) {
      final f = lockedAt(g, 700, 250, heading: 90);
      var travelled = 0.0, switches = 0, offRoad = 0;
      var edge = f.position!.edgeId;
      for (final y in yaw) {
        final t = f.advance(0.8, yawDeg: y);
        travelled += t;
        var p = f.position!;
        if (t < 0.8 - 1e-9) {
          f.lock(
              lat: p.lat,
              lon: p.lon,
              headingDeg: p.headingDeg + 180,
              maxRadiusM: 5);
          p = f.position!;
        }
        if (p.edgeId != edge) {
          switches++;
          edge = p.edgeId;
        }
        if (check &&
            !(p.lat.isFinite &&
                p.lon.isFinite &&
                p.headingDeg.isFinite &&
                g.nearby(p.lat, p.lon, radiusM: 0.5, limit: 1).isNotEmpty)) {
          offRoad++;
        }
      }
      return (f: f, travelled: travelled, switches: switches, offRoad: offRoad);
    }

    test('20 000 random steps never leave the roads or go non-finite', () {
      final r = drive(gridGraph(), yawSchedule(20000, 42), check: true);
      expect(r.offRoad, 0);
      expect(r.f.unexplainedYawDeg.isFinite, isTrue);
      // It really drove (16 km possible) and really turned at crossings.
      expect(r.travelled, greaterThan(12000));
      expect(r.switches, greaterThan(30));
    });

    test('with no yaw the grid drive stays on its street past every crossing',
        () {
      // 2.4 km through 13 crossings, all inside one edge; no gyroscope, so no
      // reason to turn. The simulator relies on exactly this.
      final f = lockedAt(gridGraph(), 700, 250, heading: 90);
      final edge = f.position!.edgeId;
      for (var i = 0; i < 3000; i++) {
        f.advance(0.8);
        expect(f.position!.edgeId, edge, reason: 'changed edge at step $i');
      }
    });

    test('the same drive twice gives the identical result', () {
      final yaw = yawSchedule(5000, 7);
      final a = drive(gridGraph(), yaw).f.position!;
      final b = drive(gridGraph(), yaw).f.position!;
      expect(a.lat, b.lat);
      expect(a.lon, b.lon);
      expect(a.edgeId, b.edgeId);
      expect(a.headingDeg, b.headingDeg);
    });

    test('20 000 advance calls on the grid finish inside 500 ms', () {
      final yaw = yawSchedule(20000, 42);
      final f = lockedAt(gridGraph(), 700, 250, heading: 90);
      f.advance(1); // build the first geometry outside the clock
      final sw = Stopwatch()..start();
      for (final y in yaw) {
        if (f.advance(0.8, yawDeg: y) < 0.8 - 1e-9) {
          final p = f.position!;
          f.lock(
              lat: p.lat,
              lon: p.lon,
              headingDeg: p.headingDeg + 180,
              maxRadiusM: 5);
        }
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('a 5 km, 400-vertex edge costs O(1) per 1 m step', () {
      final f = lockedAt(graphOf([road(1, windingRoad())]), 0, 0, heading: 0);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 4000; i++) {
        f.advance(1, yawDeg: 0.001);
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(150));
    });
  });
}
