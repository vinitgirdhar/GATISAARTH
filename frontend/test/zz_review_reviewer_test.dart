import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_follower.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';

import 'nav/support/road_follower_fixtures.dart';

List<List<double>> ring(
    {double r = 25, int n = 48, bool cw = false, double cn = 25}) {
  return [
    for (var k = 0; k <= n; k++)
      [
        cn - r * math.cos(2 * math.pi * k / n),
        (cw ? -1 : 1) * r * math.sin(2 * math.pi * k / n),
      ],
  ];
}

List<List<double>> arc(List<List<double>> r, int a, int b) => r.sublist(a, b + 1);

String fmt(RoadFollower f) {
  final p = f.position;
  if (p == null) return 'unlocked';
  final o = offsetOf(p);
  return 'edge ${p.edgeId} along ${p.alongM.toStringAsFixed(1)} '
      'at (${o.n.toStringAsFixed(1)},${o.e.toStringAsFixed(1)}) '
      'hdg ${p.headingDeg.toStringAsFixed(0)} unexpl ${f.unexplainedYawDeg.toStringAsFixed(1)}';
}

List<List<double>> densify(List<List<double>> poly, double step) {
  final out = <List<double>>[poly.first];
  var carry = 0.0;
  for (var i = 0; i + 1 < poly.length; i++) {
    final a = poly[i], b = poly[i + 1];
    final dn = b[0] - a[0], de = b[1] - a[1];
    final len = math.sqrt(dn * dn + de * de);
    if (len == 0) continue;
    var s = step - carry;
    while (s <= len) {
      out.add([a[0] + dn * s / len, a[1] + de * s / len]);
      s += step;
    }
    carry = len - (s - step);
  }
  return out;
}

class Drive {
  Drive(this.f, this.edges, this.maxDev, this.endDev, this.maxUnexpl,
      this.switches, this.finalEdge);
  final RoadFollower f;
  final List<int> edges;
  final double maxDev;
  final double endDev;
  final double maxUnexpl;
  final int switches;
  final int finalEdge;
  String edgeTrail() {
    final out = <String>[];
    int? last;
    for (final e in edges) {
      if (e != last) out.add('$e');
      last = e;
    }
    return out.join('>');
  }
}

Drive truthDrive(RoadGraph g, List<List<double>> truth,
    {double noiseDeg = 0.05,
    double biasDegPerStep = 0,
    int seed = 1,
    double smoothM = 8,
    double step = 1.0,
    bool reverseAtDeadEnd = false}) {
  final pts = densify(truth, step);
  final n = pts.length - 1;
  final bearing = <double>[
    for (var i = 0; i < n; i++)
      NavMath.wrap360(math.atan2(pts[i + 1][1] - pts[i][1],
              pts[i + 1][0] - pts[i][0]) *
          180 /
          math.pi)
  ];
  final raw = <double>[
    for (var i = 0; i < n; i++)
      i == 0 ? 0.0 : NavMath.angleDiffDeg(bearing[i], bearing[i - 1])
  ];
  final w = math.max(1, (smoothM / step).round());
  final h = w ~/ 2;
  final yaw = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    var s = 0.0;
    for (var k = -h; k <= h; k++) {
      final j = i + k;
      if (j < 0 || j >= n) continue;
      s += raw[j];
    }
    yaw[i] = s / (2 * h + 1);
  }
  final rnd = math.Random(seed);
  double gauss() {
    final u1 = rnd.nextDouble(), u2 = rnd.nextDouble();
    return math.sqrt(-2 * math.log(u1 + 1e-12)) * math.cos(2 * math.pi * u2);
  }

  final f = lockedAt(g, pts[0][0], pts[0][1], heading: bearing[0]);
  final edges = <int>[];
  var maxDev = 0.0, maxU = 0.0, sw = 0;
  var lastEdge = f.position!.edgeId;
  var endDev = 0.0;
  for (var i = 0; i < n; i++) {
    var y = yaw[i] + noiseDeg * gauss() + biasDegPerStep;
    if (y == 0) y = 1e-6;
    f.advance(step, yawDeg: y, reverseAtDeadEnd: reverseAtDeadEnd);
    final p = f.position!;
    edges.add(p.edgeId);
    if (p.edgeId != lastEdge) {
      sw++;
      lastEdge = p.edgeId;
    }
    final o = offsetOf(p);
    final dev = math.sqrt(math.pow(o.n - pts[i + 1][0], 2) +
        math.pow(o.e - pts[i + 1][1], 2));
    if (dev > maxDev) maxDev = dev;
    endDev = dev;
    maxU = math.max(maxU, f.unexplainedYawDeg.abs());
  }
  return Drive(f, edges, maxDev, endDev, maxU, sw, lastEdge);
}

void report(String name, Drive d) {
  print('$name: trail ${d.edgeTrail()}  maxDev ${d.maxDev.toStringAsFixed(1)} m  '
      'endDev ${d.endDev.toStringAsFixed(1)} m  maxUnexpl ${d.maxUnexpl.toStringAsFixed(1)}  '
      'final: ${fmt(d.f)}');
}

void main() {

  RoadGraph dense({int n = 60, double sp = 20}) {
    final es = <RoadEdge>[];
    var id = 1;
    bool hole(double a, double b) => a > 540 && a < 700 && b > 540 && b < 700;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (j + 1 < n && !hole(i * sp, j * sp) && !hole(i * sp, (j + 1) * sp)) {
          es.add(road(id++, [
            [i * sp, j * sp],
            [i * sp, (j + 1) * sp]
          ]));
        }
        if (i + 1 < n && !hole(i * sp, j * sp) && !hole((i + 1) * sp, j * sp)) {
          es.add(road(id++, [
            [i * sp, j * sp],
            [(i + 1) * sp, j * sp]
          ]));
        }
      }
    }
    es.add(road(99999, [
      [600, 600],
      [600, 620]
    ], name: 'iso'));
    return graphOf(es);
  }

  test('P1 perf: dead end in a dense graph', () {
    final g = dense();
    final f = lockedAt(g, 600, 600, heading: 0);
    f.advance(19.9);
    final sw = Stopwatch()..start();
    var moved = 0.0;
    for (var i = 0; i < 2000; i++) {
      moved += f.advance(0.24);
    }
    sw.stop();
    print('P1 edges ${g.edgeCount}; dead end: ${sw.elapsedMicroseconds / 2000} us/call, moved $moved, ${fmt(f)}');
    final h = lockedAt(g, 605, 800, heading: 0);
    h.advance(1, yawDeg: 40);
    var calls = 0;
    final sw2 = Stopwatch()..start();
    while (h.unexplainedYawDeg.abs() >= 35 && calls < 5000) {
      h.advance(0.24, yawDeg: 0.001);
      calls++;
    }
    sw2.stop();
    print('P1 U=40 unmatched: $calls calls, ${sw2.elapsedMicroseconds / calls} us/call');
  });
}
