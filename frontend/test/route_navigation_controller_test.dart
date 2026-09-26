import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/route/planned_route.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_road_source.dart';
import 'package:gatisaarth/features/navigation_engine/domain/entities/navigation_state.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

// A T-junction: a north-south street with a branch turning east at the
// junction. A vehicle driving north with no gyro evidence of a turn
// continues north (the plain road follower's own rule); the route below
// instead turns east at the same junction, which is what proves route-locked
// dead reckoning follows the *route*, not just any road.
const _south = 18.5180;
const _junctionLat = 18.5200;
const _north = 18.5220;
const _lon0 = 73.8580;
const _east = 73.8600;

RoadGraph _tJunction() => RoadGraph(
      nodes: const [
        RoadNode(id: 1, lat: _south, lon: _lon0),
        RoadNode(id: 2, lat: _junctionLat, lon: _lon0),
        RoadNode(id: 3, lat: _north, lon: _lon0),
        RoadNode(id: 4, lat: _junctionLat, lon: _east),
      ],
      edges: [
        RoadEdge(
          id: 1,
          fromNode: 1,
          toNode: 2,
          polyline: const [_south, _lon0, _junctionLat, _lon0],
        ),
        RoadEdge(
          id: 2,
          fromNode: 2,
          toNode: 3,
          polyline: const [_junctionLat, _lon0, _north, _lon0],
        ),
        RoadEdge(
          id: 3,
          fromNode: 2,
          toNode: 4,
          polyline: const [_junctionLat, _lon0, _junctionLat, _east],
        ),
      ],
    );

/// A route from just south of the junction, turning east at it (the branch
/// the plain road follower would *not* take with no gyro evidence).
PlannedRoute _turningRoute({double startLat = _south + 0.00045}) => PlannedRoute(
      polyline: [startLat, _lon0, _junctionLat, _lon0, _junctionLat, _east],
      maneuvers: [
        RouteManeuver(kind: ManeuverKind.depart, atM: 0, lat: startLat, lon: _lon0),
        RouteManeuver(
            kind: ManeuverKind.right, atM: 50, lat: _junctionLat, lon: _lon0),
        RouteManeuver(
            kind: ManeuverKind.arrive, atM: 250, lat: _junctionLat, lon: _east),
      ],
      durationS: 60,
    );

/// A route that keeps going straight north through the junction, for the
/// divergence test (a real turn the route did not call for).
PlannedRoute _straightRoute({double startLat = _south + 0.00045}) => PlannedRoute(
      polyline: [startLat, _lon0, _junctionLat, _lon0, _north, _lon0],
      maneuvers: [
        RouteManeuver(kind: ManeuverKind.depart, atM: 0, lat: startLat, lon: _lon0),
        RouteManeuver(kind: ManeuverKind.arrive, atM: 400, lat: _north, lon: _lon0),
      ],
      durationS: 60,
    );

/// Serves one fixed graph.
class _FixedRoads implements RoadGraphSource {
  _FixedRoads(this.graph);
  final RoadGraph graph;

  @override
  Future<RoadCoverage?> roadsAround(double lat, double lon) async =>
      RoadCoverage(
        graph: graph,
        safeSouth: 18.0,
        safeWest: 73.0,
        safeNorth: 19.0,
        safeEast: 74.0,
      );
}

/// Frame layout: [ax, ay, az, gx, gy, gz, t, mx, my, mz, pressure, altitude].
List<double> _frame(double t, {double gz = 0}) =>
    [0, 0, 9.81, 0, 0, gz, t, 0, 30, 0, double.nan, double.nan];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSensors sensors;
  late FakeLocationGateway gateway;
  late RoadGraph graph;
  late LiveSessionController controller;
  var t = 100.0;
  var now = DateTime(2026, 9, 27, 12);

  LiveSessionController build({RoadGraphSource? roads}) {
    final hardware = FakeHardware();
    return LiveSessionController(
      sensors: sensors,
      alignment: VehicleAlignmentEngine(),
      hardware: hardware,
      speedEstimator: FakeSpeed(),
      telemetry: FakeTelemetry(),
      location: LiveLocationService(gateway: gateway, clock: () => now),
      clock: () => now,
      autoTick: false,
      haptics: Haptics(hardware, pause: (_) async {}),
      roads: roads,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sensors = FakeSensors();
    gateway = FakeLocationGateway();
    graph = _tJunction();
    controller = build(roads: _FixedRoads(graph));
    t = 100.0;
    now = DateTime(2026, 9, 27, 12);
  });

  tearDown(() => controller.dispose());

  Future<void> fix(double lat, double lon,
      {double speed = 10, double accuracy = 5}) async {
    gateway.fixController.add(GnssFix(
      latitude: lat,
      longitude: lon,
      altitude: 10,
      accuracy: accuracy,
      speed: speed,
    ));
    await settle();
    controller.tick();
  }

  Future<void> goLive(double lat, double lon, {double speed = 10}) async {
    await controller.start();
    await fix(lat, lon, speed: speed);
    controller.tick();
    await settle();
  }

  /// Drives [frames] sensor frames of 0.1 s, ticking after each one.
  Future<void> drive(int frames, {double gz = 0}) async {
    for (var i = 0; i < frames; i++) {
      t += 0.1;
      sensors.frames.add(_frame(t, gz: gz));
      await settle();
      controller.tick();
    }
  }

  test('GNSS-live progress advances along the route and off-route recovers',
      () async {
    final route = _turningRoute();
    await goLive(_south + 0.00045, _lon0);
    controller.startRoute(route);

    expect(controller.routeProgress, isNotNull);
    final start = controller.routeProgress!.alongM;
    expect(controller.isOffRoute, isFalse);

    // Fixes moving north along the route.
    await fix(_south + 0.0006, _lon0);
    await fix(_south + 0.0008, _lon0);
    expect(controller.routeProgress!.alongM, greaterThan(start));
    expect(controller.isOffRoute, isFalse);

    // Several fixes well off the route (a different street to the west).
    for (var i = 0; i < 3; i++) {
      await fix(_south + 0.0008, _lon0 - 0.002);
    }
    expect(controller.isOffRoute, isTrue);

    // Back on the route.
    await fix(_south + 0.0009, _lon0);
    expect(controller.isOffRoute, isFalse);
  });

  // The route tracker treats the route's own turns as real turns the vehicle
  // must be seen (by the gyro) to make: an `advance()` that crosses a route
  // segment boundary compares the gyro yaw fed since the last `advance()`
  // against the route's own bearing change there, and a mismatch is exactly
  // what `hasDiverged` is for. So "follow the route's turn" only holds when
  // the simulated drive actually turns the right amount, on the frame that
  // reaches the junction — worked out here from the same distance-per-frame
  // (`speed * dt`, speed 10 m/s, dt 0.1 s) `_integrate` itself advances by.
  const double _mPerFrame = 1.0;

  // `_onImu`'s very first frame ever forces `dt = 0.02 s` (there is no prior
  // frame timestamp to diff against yet), not the `t`-derived 0.1 s every
  // later frame gets; one throwaway frame absorbs that so the distance
  // budget below is exact.
  const double _firstFrameM = 1.0 * 0.02 / 0.1;

  int _crossingFrame(double remainingBeforeTurnM) =>
      (remainingBeforeTurnM / _mPerFrame).floor() + 1;

  test('a tunnel outage on a route follows the route\'s turn, not the road',
      () async {
    final startLat = _south + 0.00045;
    await goLive(startLat, _lon0);
    controller.startRoute(_turningRoute(startLat: startLat));
    controller.startTunnelTest();

    expect(controller.isRouteLocked, isTrue);
    expect(controller.fusionMode, FusionMode.deadReckoning);

    await drive(1); // absorbs the first-frame dt anomaly noted above
    final beforeTurnM = NavMath.horizontalDistance(
            lat0: startLat, lon0: _lon0, lat1: _junctionLat, lon1: _lon0) -
        _firstFrameM;
    final turnFrame = _crossingFrame(beforeTurnM);

    // Straight north up to the junction...
    await drive(turnFrame - 1);
    expect(controller.isRouteLocked, isTrue, reason: 'no divergence yet');
    // ...a real ~90 degree right turn on the one frame that crosses into the
    // east branch (a full turn packed into a single 0.1 s frame: -15.708
    // rad/s so pendingYaw matches the route's own +90 deg bearing change
    // there), then on down the east branch.
    await drive(1, gz: -15.708);
    expect(controller.isRouteLocked, isTrue,
        reason: 'the turn matches the route: no divergence');
    await drive(150);

    // The route turns east at the junction; the plain road follower (with no
    // gyro turn recorded here) would instead have gone straight on north —
    // see the "with no route" test below for that contrast.
    expect(controller.latitude, closeTo(_junctionLat, 1e-4));
    expect(controller.longitude, greaterThan(_lon0));
    expect(controller.isRouteLocked, isTrue);
  });

  test('isRouteLocked clears on GNSS recovery and the marker eases to it',
      () async {
    final startLat = _south + 0.00045;
    await goLive(startLat, _lon0);
    controller.startRoute(_turningRoute(startLat: startLat));
    controller.startTunnelTest();
    // Well short of the junction: no turn needed yet, so no divergence risk.
    await drive(50);
    expect(controller.isRouteLocked, isTrue);
    expect(controller.latitude, greaterThan(startLat));

    controller.resetSimulation();
    expect(controller.isRouteLocked, isFalse);

    // The marker eases toward the live fix (back at the start) over a few
    // ticks rather than snapping there instantly.
    final afterReset = controller.latitude;
    now = now.add(const Duration(milliseconds: 100));
    controller.tick();
    final oneTickLater = controller.latitude;
    expect(oneTickLater, isNot(equals(afterReset)));

    for (var i = 0; i < 40; i++) {
      now = now.add(const Duration(milliseconds: 100));
      controller.tick();
    }
    expect(controller.latitude, closeTo(startLat, 1e-5));
  });

  test('a real turn the route did not call for releases the route lock',
      () async {
    await goLive(_south + 0.00045, _lon0);
    controller.startRoute(_straightRoute());
    controller.startTunnelTest();
    expect(controller.isRouteLocked, isTrue);

    // Approach the junction, then a real 90 degree right turn (the route
    // says continue straight), then keep driving.
    await drive(30);
    await drive(10, gz: -1.5708);
    await drive(80);

    expect(controller.isRouteLocked, isFalse);
    expect(controller.isOnRoad, isTrue,
        reason: 'the road follower takes over once the route is left');
  });

  test('ending the route during an outage keeps dead reckoning on the road',
      () async {
    await goLive(_south + 0.00045, _lon0);
    controller.startRoute(_turningRoute());
    controller.startTunnelTest();
    await drive(20);
    expect(controller.isRouteLocked, isTrue);

    controller.endRoute();

    expect(controller.isRouteLocked, isFalse);
    expect(controller.activeRoute, isNull);
    expect(controller.isOnRoad, isTrue);

    // Dead reckoning keeps moving on the road after the route is gone.
    final before = controller.longitude;
    await drive(30);
    expect(controller.latitude, isNot(isNaN));
    expect(controller.longitude, isNot(isNaN));
    expect(
      controller.longitude != before || controller.latitude != _south,
      isTrue,
    );
  });

  test('with no route, behaviour is unchanged: the tunnel test follows '
      'the road straight through the junction', () async {
    await goLive(_south + 0.00045, _lon0);
    controller.startTunnelTest();

    await drive(400);

    expect(controller.activeRoute, isNull);
    expect(controller.isRouteLocked, isFalse);
    expect(controller.routeProgress, isNull);
    expect(controller.isOffRoute, isFalse);
    // No route: the road follower continues straight through the junction
    // (north), never turning onto the east branch.
    expect(controller.longitude, closeTo(_lon0, 1e-5));
    expect(controller.latitude, greaterThan(_junctionLat));
  });
}
