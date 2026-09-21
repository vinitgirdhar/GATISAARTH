import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_road_source.dart';
import 'package:gatisaarth/features/navigation_engine/domain/entities/navigation_state.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

// A crossroads at (18.5200, 73.8580): a west-east street of ~420 m with a
// north-south street through it. Each arm is its own edge, the way a tile cut
// or an OSM split leaves them.
const _junctionLat = 18.5200;
const _junctionLon = 73.8580;
const _west = 73.8560;
const _east = 73.8600;
const _north = 18.5220;
const _south = 18.5180;

RoadGraph _crossroads() => RoadGraph(
      nodes: const [
        RoadNode(id: 1, lat: _junctionLat, lon: _west),
        RoadNode(id: 2, lat: _junctionLat, lon: _junctionLon),
        RoadNode(id: 3, lat: _junctionLat, lon: _east),
        RoadNode(id: 4, lat: _north, lon: _junctionLon),
        RoadNode(id: 5, lat: _south, lon: _junctionLon),
      ],
      edges: [
        RoadEdge(
          id: 1,
          fromNode: 1,
          toNode: 2,
          polyline: const [_junctionLat, _west, _junctionLat, _junctionLon],
        ),
        RoadEdge(
          id: 2,
          fromNode: 2,
          toNode: 3,
          polyline: const [_junctionLat, _junctionLon, _junctionLat, _east],
        ),
        RoadEdge(
          id: 3,
          fromNode: 2,
          toNode: 4,
          polyline: const [_junctionLat, _junctionLon, _north, _junctionLon],
        ),
        RoadEdge(
          id: 4,
          fromNode: 2,
          toNode: 5,
          polyline: const [_junctionLat, _junctionLon, _south, _junctionLon],
        ),
      ],
    );

/// Serves one fixed graph, counting how often it was asked.
class _FixedRoads implements RoadGraphSource {
  _FixedRoads(this.graph);
  final RoadGraph graph;
  int asked = 0;

  @override
  Future<RoadCoverage?> roadsAround(double lat, double lon) async {
    asked++;
    return RoadCoverage(
      graph: graph,
      safeSouth: 18.0,
      safeWest: 73.0,
      safeNorth: 19.0,
      safeEast: 74.0,
    );
  }
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
  var now = DateTime(2026, 9, 20, 12);

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
    graph = _crossroads();
    controller = build(roads: _FixedRoads(graph));
    t = 100.0;
    now = DateTime(2026, 9, 20, 12);
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

  /// How far the drawn marker is from the nearest drawn road (m).
  double offRoad() {
    final near = graph.nearby(controller.latitude, controller.longitude,
        radiusM: 50, limit: 1);
    return near.isEmpty ? double.infinity : near.first.perpendicularM;
  }

  /// Starts the session with a fix and lets the roads load.
  Future<void> goLive(double lat, double lon, {double speed = 10}) async {
    await controller.start();
    await fix(lat, lon, speed: speed);
    controller.tick();
    await settle();
  }

  /// Drives [frames] sensor frames of 0.1 s, ticking after each one, and
  /// returns the worst distance from any road seen on the way.
  Future<double> drive(int frames, {double gz = 0}) async {
    var worst = 0.0;
    for (var i = 0; i < frames; i++) {
      t += 0.1;
      sensors.frames.add(_frame(t, gz: gz));
      await settle();
      controller.tick();
      worst = worst > offRoad() ? worst : offRoad();
    }
    return worst;
  }

  test('a tunnel test follows the street, however far it runs', () async {
    await goLive(_junctionLat, 73.8562);
    controller.startTunnelTest();
    expect(controller.fusionMode, FusionMode.deadReckoning);

    // 12.5 m/s for 40 s: from near the west end, through the crossroads and on
    // to the east end, where the street stops and so does the marker.
    final worst = await drive(400);

    expect(worst, lessThan(0.5), reason: 'never off the drawn road');
    expect(controller.latitude, closeTo(_junctionLat, 1e-5));
    expect(controller.longitude, greaterThan(73.8562));
    expect(controller.heading, closeTo(90, 1));
  });

  test('going straight at a crossroads stays on the street', () async {
    await goLive(_junctionLat, 73.8570);
    controller.startTunnelTest();

    // 105 m to the crossroads and 45 m beyond it.
    await drive(150);

    expect(controller.latitude, closeTo(_junctionLat, 1e-5));
    expect(controller.longitude, greaterThan(_junctionLon));
    expect(controller.heading, closeTo(90, 1));
  });

  // Speed is the fix's 10 m/s, so a frame of 0.1 s is 1 m. The crossroads is
  // 32 m ahead of this start; the turn is made over the last 10 m before it.
  const approachLon = 73.8577;

  test('a right turn measured by the gyroscope is taken at the crossroads',
      () async {
    await goLive(_junctionLat, approachLon);
    controller.startTunnelTest();

    // Straight, then a 90 degree right turn in a second (a right turn is a
    // negative rotation about the phone's up axis), then on down the new street.
    await drive(20);
    await drive(10, gz: -1.5708);
    final worst = await drive(60);

    expect(worst, lessThan(0.5));
    expect(controller.longitude, closeTo(_junctionLon, 1e-5));
    expect(controller.latitude, lessThan(_junctionLat - 0.0002),
        reason: 'the right-hand exit of an eastbound street goes south');
    expect(controller.heading, closeTo(180, 1));
  });

  test('a left turn goes the other way', () async {
    await goLive(_junctionLat, approachLon);
    controller.startTunnelTest();

    await drive(20);
    await drive(10, gz: 1.5708);
    final worst = await drive(60);

    expect(worst, lessThan(0.5));
    expect(controller.longitude, closeTo(_junctionLon, 1e-5));
    expect(controller.latitude, greaterThan(_junctionLat + 0.0002));
    expect(controller.heading, closeTo(0, 1));
  });

  test('the urban canyon keeps the marker on the street while fixes wander',
      () async {
    await goLive(_junctionLat, 73.8562, speed: 8);
    controller.startUrbanCanyon();
    expect(controller.fusionMode, FusionMode.gnssDegraded);

    // Fixes 15 m off the street and moving: the canyon's multipath. The old
    // simulation drew the marker on them, weaving about the street.
    var worst = 0.0;
    for (var i = 0; i < 10; i++) {
      await drive(10);
      await fix(_junctionLat + (i.isEven ? 0.000135 : -0.000135),
          controller.longitude,
          speed: 8, accuracy: 15);
      worst = worst > offRoad() ? worst : offRoad();
    }

    expect(worst, lessThan(0.5));
    expect(controller.accuracy, greaterThanOrEqualTo(25));
    expect(controller.longitude, greaterThan(73.8562));
  });

  test('a standing phone does not stop the urban canyon simulation',
      () async {
    await goLive(_junctionLat, 73.8562, speed: 0);
    controller.startUrbanCanyon();
    final start = controller.longitude;

    for (var i = 0; i < 5; i++) {
      await drive(10);
      // The receiver keeps reporting the same standing fix.
      await fix(_junctionLat, 73.8562, speed: 0);
    }

    expect(controller.speed, greaterThan(5));
    expect(controller.longitude, greaterThan(start));
    expect(offRoad(), lessThan(0.5));
  });

  test('roads that arrive after the outage began are picked up', () async {
    final lazy = _LateRoads(graph);
    controller.dispose();
    controller = build(roads: lazy);
    await controller.start();
    await fix(_junctionLat, 73.8562);

    controller.startTunnelTest();
    await drive(20); // no roads yet: straight ahead on the heading
    lazy.arrive();
    await settle();
    await drive(20);

    expect(offRoad(), lessThan(0.5));
  });

  test('ending the simulation puts the marker back on the live fix',
      () async {
    await goLive(_junctionLat, 73.8562);
    controller.startTunnelTest();
    await drive(100);
    expect(controller.longitude, greaterThan(73.8570));

    controller.resetSimulation();
    // The marker glides back to the fix over a second or two.
    for (var i = 0; i < 40; i++) {
      now = now.add(const Duration(milliseconds: 100));
      controller.tick();
    }

    expect(controller.longitude, closeTo(73.8562, 1e-5));
    expect(controller.isSimulatingTunnel, isFalse);
  });

  test('with no roads at all the simulation still runs, straight ahead',
      () async {
    controller.dispose();
    controller = build();
    await goLive(_junctionLat, 73.8562);
    controller.startTunnelTest();

    await drive(40);

    expect(controller.latitude, isNot(isNaN));
    expect(controller.longitude, isNot(isNaN));
    expect(controller.speed, greaterThan(5));
  });

  test('roads are read once for a whole area, not once per tick', () async {
    final roads = _FixedRoads(graph);
    controller.dispose();
    controller = build(roads: roads);
    await goLive(_junctionLat, 73.8562);
    controller.startTunnelTest();
    await drive(200);

    expect(roads.asked, 1);
  });

  // ---- behaviours a review of the first version found missing ---------------

  test('a receiver that jitters while standing does not stall the canyon',
      () async {
    await goLive(_junctionLat, 73.8562, speed: 0);
    controller.startUrbanCanyon();

    // Doppler speed 0, but the position wanders 3 m from fix to fix: derived
    // from positions that is a crawl of a few m/s, which used to overwrite the
    // simulated cruise.
    for (var i = 0; i < 8; i++) {
      await drive(10);
      now = now.add(const Duration(seconds: 1));
      await fix(_junctionLat + (i.isEven ? 0.00003 : -0.00003), 73.8562,
          speed: 0, accuracy: 5);
    }

    expect(controller.speed, closeTo(8.33, 0.01));
    expect(controller.longitude, greaterThan(73.8565));
    expect(offRoad(), lessThan(0.5));
  });

  test('one wild fix does not throw the canyon marker off its street',
      () async {
    await goLive(_junctionLat, 73.8562, speed: 8);
    controller.startUrbanCanyon();
    await drive(20);

    // 60 m off the street, moving, and it claims to be accurate to 5 m.
    await fix(_junctionLat + 0.00054, controller.longitude,
        speed: 8, accuracy: 5);
    await drive(10);

    expect(controller.isOnRoad, isTrue);
    expect(offRoad(), lessThan(0.5));
  });

  test('the compass readout keeps updating while the marker is on a road',
      () async {
    await goLive(_junctionLat, 73.8562);
    controller.startTunnelTest();
    await drive(5);

    expect(controller.isOnRoad, isTrue);
    expect(controller.magY, closeTo(30, 1e-9));
  });

  test('a parked vehicle is not pulled onto the nearest street when the '
      'signal is lost', () async {
    // 20 m north of the street, standing still.
    await goLive(_junctionLat + 0.00018, 73.8562, speed: 0);
    now = now.add(const Duration(minutes: 1));
    controller.tick();

    expect(controller.inOutage, isTrue);
    expect(controller.isOnRoad, isFalse);
    expect(controller.latitude, closeTo(_junctionLat + 0.00018, 1e-7));
  });

  test('Reset GNSS during a real outage leaves the dead-reckoned position',
      () async {
    await goLive(_junctionLat, 73.8562, speed: 10);
    now = now.add(const Duration(minutes: 1)); // the signal is gone
    controller.tick();
    expect(controller.inOutage, isTrue);
    expect(controller.isSimulatingTunnel, isFalse);

    await drive(60);
    final travelled = controller.longitude;
    expect(travelled, greaterThan(73.8564)); // the fake model says "still" after a few seconds

    controller.resetSimulation();
    controller.tick();

    expect(controller.longitude, closeTo(travelled, 1e-9));
  });
}

/// A source whose roads arrive when the test says so.
class _LateRoads implements RoadGraphSource {
  _LateRoads(this.graph);
  final RoadGraph graph;
  final _gate = Completer<void>();

  void arrive() => _gate.complete();

  @override
  Future<RoadCoverage?> roadsAround(double lat, double lon) async {
    await _gate.future;
    return RoadCoverage(
      graph: graph,
      safeSouth: 18.0,
      safeWest: 73.0,
      safeNorth: 19.0,
      safeEast: 74.0,
    );
  }
}
