import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_follower.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';

import 'support/real_map_packs.dart';

/// The follower on the real streets of the offline map archives: from many
/// real starting points, drive 1.5 km straight through every crossing and
/// require that the vehicle either reaches a dead end or actually covers
/// ground. A marker oscillating on a sliver of digitising noise "drives"
/// 1.5 km within a few metres of where it started - that is the failure this
/// walks for. (Going round a real roundabout for 1.5 km, which a driver who
/// never turns does, is not: its diameter is 15 m and more.)
const _places = [
  ('delhi-ncr', 'Delhi, Dwarka', 28.5921, 77.0460),
  ('delhi-ncr', 'Delhi, Connaught Place', 28.6315, 77.2167),
  ('mumbai', 'Mumbai, Andheri', 19.1136, 72.8697),
  ('pune', 'Pune, Kothrud', 18.5074, 73.8077),
];

/// Wider than any sliver of noise, narrower than the smallest real roundabout.
const _trapExtentM = 8.0;

double _metres(double lat0, double lon0, double lat1, double lon1) {
  final dLat = (lat1 - lat0) * 111320;
  final dLon = (lon1 - lon0) * 111320 * math.cos(lat0 * math.pi / 180);
  return math.sqrt(dLat * dLat + dLon * dLon);
}

void main() {
  for (final (pack, name, lat, lon) in _places) {
    test('$name: driving straight through real streets always gets somewhere',
        skip: skipUnlessPack(pack),
        timeout: const Timeout(Duration(minutes: 3)), () async {
      final source = (await openRealRoadSource(pack))!;
      final graph = (await source.roadsAround(lat, lon))!.graph;

      final edges = graph.edges.where((e) => e.lengthM >= 30).toList();
      final step = math.max(1, edges.length ~/ 300);
      var walked = 0;
      var deadEnds = 0;
      final trapped = <String>[];

      for (var i = 0; i < edges.length; i += step) {
        final edge = edges[i];
        // From both ends of the edge, facing along it: where a route starts.
        for (final atStart in [true, false]) {
          final follower = RoadFollower(graph: graph);
          final a = atStart ? 0 : edge.pointCount - 1;
          final b = atStart ? 1 : edge.pointCount - 2;
          final d = NavMath.nedBetween(
              lat0: edge.latAt(a),
              lon0: edge.lonAt(a),
              alt0: 0,
              lat1: edge.latAt(b),
              lon1: edge.lonAt(b),
              alt1: 0);
          final heading =
              NavMath.wrap360(math.atan2(d.y, d.x) * NavMath.radToDeg);
          if (!follower.lock(
              lat: edge.latAt(a),
              lon: edge.lonAt(a),
              headingDeg: heading,
              maxRadiusM: 5)) {
            continue;
          }
          final start = follower.position!;
          var travelled = 0.0;
          var farthest = 0.0;
          for (var m = 0; m < 1500; m++) {
            final moved = follower.advance(1);
            travelled += moved;
            if (moved < 0.999) break;
            final p = follower.position!;
            farthest =
                math.max(farthest, _metres(start.lat, start.lon, p.lat, p.lon));
          }
          walked++;
          if (travelled < 1499) {
            deadEnds++;
          } else if (farthest < _trapExtentM) {
            trapped.add('edge ${edge.id} (${edge.name ?? "unnamed"}) '
                '${atStart ? "from its start" : "from its end"}: 1.5 km '
                'driven, never more than ${farthest.toStringAsFixed(0)} m '
                'from where it started');
          }
        }
      }

      printOnFailure('$name: $walked real starts, $deadEnds reached a dead end');
      expect(walked, greaterThan(30));
      expect(trapped, isEmpty, reason: trapped.take(5).join('\n'));
    });
  }
}
