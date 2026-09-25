import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_follower.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

/// One edge shaped like an L: 200 m north, then 200 m east.
const _lat0 = 28.60, _lon0 = 77.20;
const _mPerDegLat = 110850.0;
const _mPerDegLon = 97740.0; // at 28.6 N

RoadGraph _lRoad() => RoadGraph(
      nodes: const [
        RoadNode(id: 1, lat: _lat0, lon: _lon0),
        RoadNode(id: 2, lat: _lat0, lon: _lon0),
      ],
      edges: [
        RoadEdge(
          id: 1,
          fromNode: 1,
          toNode: 2,
          polyline: [
            _lat0, _lon0, //
            _lat0 + 200 / _mPerDegLat, _lon0,
            _lat0 + 200 / _mPerDegLat, _lon0 + 200 / _mPerDegLon,
          ],
        ),
      ],
    );

/// The truth drives 300 m round the corner at 10 m/s; the dead-reckoned
/// distance is [scale] × the truth (a speed error) and the gyro turns 90° over
/// the 3 s the truth takes through the corner. Returns the error at the end.
({double errorM, int registrations}) _drive(double scale, {required bool on}) {
  final f = RoadFollower(
    graph: _lRoad(),
    config: RoadFollowConfig(bendRegistration: on),
  )..lock(lat: _lat0, lon: _lon0, headingDeg: 0);
  const dt = 0.1, speed = 10.0;
  for (var t = 0.0; t < 30 - 1e-9; t += dt) {
    final truthAlong = speed * t;
    // The corner is taken between 185 m and 215 m of truth.
    final turning = truthAlong >= 185 && truthAlong < 215;
    f.advance(speed * dt * scale, yawDeg: turning ? 90 * dt / 3 : 1e-4);
  }
  final p = f.position!;
  final truth = (lat: _lat0 + 200 / _mPerDegLat, lon: _lon0 + 100 / _mPerDegLon);
  return (
    errorM: NavMath.horizontalDistance(
        lat0: p.lat, lon0: p.lon, lat1: truth.lat, lon1: truth.lon),
    registrations: f.bendRegistrations,
  );
}

void main() {
  test('a marker behind the vehicle jumps to the bend the gyro just took', () {
    final off = _drive(0.8, on: false);
    final on = _drive(0.8, on: true);
    expect(on.registrations, greaterThanOrEqualTo(1));
    expect(on.errorM, lessThan(off.errorM * 0.6));
  });

  test('a marker ahead of the vehicle is pulled back to the bend', () {
    final off = _drive(1.2, on: false);
    final on = _drive(1.2, on: true);
    expect(on.registrations, greaterThanOrEqualTo(1));
    expect(on.errorM, lessThan(off.errorM * 0.6));
  });

  test('an exact odometer is left alone', () {
    final off = _drive(1.0, on: false);
    final on = _drive(1.0, on: true);
    expect(on.errorM, lessThan(off.errorM + 3));
  });

  test('off by default', () {
    expect(const RoadFollowConfig().bendRegistration, isFalse);
  });
}
