import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/map/tunnel_lookahead.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';

/// A straight road due north from (28.60, 77.20): open road, then a tunnel in
/// two pieces (a graph cut at a junction inside it), then open road again.
/// Metres north are converted with the local meridian scale.
const _lat0 = 28.60, _lon = 77.20;
double _north(double metres) => _lat0 + metres / 110850.0;

RoadGraph _road({bool secondPieceStoredBackwards = false}) {
  RoadEdge e(int id, double fromM, double toM, {bool tunnel = false}) =>
      RoadEdge(
        id: id,
        fromNode: id,
        toNode: id + 1,
        polyline: [_north(fromM), _lon, _north(toM), _lon],
        tunnel: tunnel,
        name: tunnel ? 'Pragati Maidan Tunnel' : 'Mathura Road',
      );
  return RoadGraph(
    nodes: [
      for (var i = 1; i <= 5; i++) RoadNode(id: i, lat: _lat0, lon: _lon),
    ],
    edges: [
      e(1, 0, 1000),
      e(2, 1000, 1400, tunnel: true),
      secondPieceStoredBackwards
          ? e(3, 1800, 1400, tunnel: true)
          : e(3, 1400, 1800, tunnel: true),
      e(4, 1800, 3000),
    ],
  );
}

void main() {
  final look = TunnelLookahead();

  test('sees a tunnel ahead on the road being driven', () {
    final t = look.find(_road(), lat: _north(300), lon: _lon, headingDeg: 0);
    expect(t, isNotNull);
    expect(t!.distanceM, closeTo(700, 15));
    expect(t.lengthM, closeTo(800, 15), reason: 'both pieces are one tunnel');
    expect(t.name, 'Pragati Maidan Tunnel');
    expect(t.exitLat, closeTo(_north(1800), 1e-5));
  });

  test('ignores a tunnel behind the vehicle', () {
    final t = look.find(_road(), lat: _north(2400), lon: _lon, headingDeg: 0);
    expect(t, isNull);
  });

  test('driving the other way the far portal is the entry', () {
    final t =
        look.find(_road(), lat: _north(2400), lon: _lon, headingDeg: 180);
    expect(t, isNotNull);
    expect(t!.distanceM, closeTo(600, 15));
    expect(t.exitLat, closeTo(_north(1000), 1e-5));
  });

  test('ignores a tunnel beyond the look-ahead distance', () {
    final t = look.find(_road(), lat: _north(-2500), lon: _lon, headingDeg: 0);
    expect(t, isNull);
  });

  test('ignores a tunnel off to the side', () {
    final t = look.find(_road(),
        lat: _north(900), lon: _lon + 0.01, headingDeg: 0); // ~1 km east
    expect(t, isNull);
  });

  test('reports being inside the tunnel', () {
    final t = look.find(_road(), lat: _north(1300), lon: _lon, headingDeg: 0);
    expect(t, isNotNull);
    expect(t!.inside, isTrue);
    expect(t.distanceM, 0);
    expect(t.remainingM, closeTo(500, 15));
  });

  test('a piece digitised the other way round is still one tunnel', () {
    final g = _road(secondPieceStoredBackwards: true);
    final ahead = look.find(g, lat: _north(300), lon: _lon, headingDeg: 0);
    expect(ahead!.lengthM, closeTo(800, 15));
    expect(ahead.exitLat, closeTo(_north(1800), 1e-5));
    final inside = look.find(g, lat: _north(1600), lon: _lon, headingDeg: 0);
    expect(inside!.inside, isTrue);
    expect(inside.remainingM, closeTo(200, 15));
  });

  test('an empty graph has no tunnels', () {
    expect(
        look.find(RoadGraph.empty(), lat: _lat0, lon: _lon, headingDeg: 0),
        isNull);
  });

  test('distance helper agrees with the navigation maths', () {
    expect(
      NavMath.horizontalDistance(
          lat0: _north(0), lon0: _lon, lat1: _north(1000), lon1: _lon),
      closeTo(1000, 5),
    );
  });
}
