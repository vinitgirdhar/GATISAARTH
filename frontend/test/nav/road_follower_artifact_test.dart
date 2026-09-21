import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_follower.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

import 'support/road_follower_fixtures.dart';

/// Real graphs read from map tiles carry slivers: closed edges a metre or so
/// long, and edges that overlap the road they hang off. On real Delhi data the
/// follower went round one of these forever and the marker sat oscillating in
/// place (`test/road_real_follower_property_test.dart` walks real roads to
/// catch it; these are the small synthetic cases).
void main() {
  // A road east from the origin with a 1.4 m closed sliver hanging on it at
  // 80 m, and the road carrying on beyond.
  RoadFollower withSliver({RoadFollowConfig config = const RoadFollowConfig()}) {
    final g = graphOf([
      road(1, [
        [0, 0],
        [0, 80],
      ]),
      road(2, [
        [0, 80],
        [0.5, 80.4],
        [0, 80],
      ]),
      road(3, [
        [0, 80],
        [0, 300],
      ]),
    ]);
    final f = RoadFollower(graph: g, config: config);
    final p = pointAt(0, 10);
    expect(f.lock(lat: p[0], lon: p[1], headingDeg: 90), isTrue);
    return f;
  }

  test('a sliver of a closed edge is not a roundabout: the road carries on',
      () {
    final f = withSliver();

    for (var i = 0; i < 150; i++) {
      f.advance(1);
    }

    expectAt(f, 0, 160);
    expectHeading(f, 90);
  });

  test('a real ring road is still followed round (the guard is only for slivers)',
      () {
    // A 100 m circumference loop street: a real ring keeps its own far end.
    final ring = <List<double>>[
      for (var k = 0; k <= 32; k++)
        [
          16 * (1 - _cos(2 * 3.14159265 * k / 32)),
          16 * _sin(2 * 3.14159265 * k / 32)
        ],
    ];
    final g = graphOf([road(1, ring)]);
    final f = RoadFollower(graph: g);
    final p = pointAt(ring[3][0], ring[3][1]);
    expect(f.lock(lat: p[0], lon: p[1], headingDeg: 45), isTrue);

    var travelled = 0.0;
    for (var i = 0; i < 300; i++) {
      travelled += f.advance(1);
    }

    expect(travelled, closeTo(300, 0.5), reason: 'never stuck on the ring');
  });
}

double _cos(double x) => _series(x, 1);
double _sin(double x) => _series(x, 0);

// Small local sin/cos so the test needs no dart:math import alias juggling.
double _series(double x, int cosine) {
  final twoPi = 2 * 3.14159265358979;
  var r = x % twoPi;
  if (r > 3.14159265358979) r -= twoPi;
  var term = cosine == 1 ? 1.0 : r;
  var sum = term;
  for (var n = 1; n < 12; n++) {
    term *= -r * r / (cosine == 1 ? (2 * n - 1) * (2 * n) : (2 * n) * (2 * n + 1));
    sum += term;
  }
  return sum;
}
