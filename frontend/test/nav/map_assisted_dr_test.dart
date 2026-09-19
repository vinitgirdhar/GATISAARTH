import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/model/nav_snapshot.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';
import 'package:gatisaarth/core/nav/sensors/sensor_sample.dart';

import 'support/drive_simulator.dart';

/// The road the simulated vehicle actually drives: due north from the start,
/// long enough to cover the whole test drive.
RoadGraph northRoad({bool tunnel = false}) {
  const startLat = 28.6139;
  const startLon = 77.2090;
  final end = NavMath.addNed(
    latDeg: startLat,
    lonDeg: startLon,
    altM: 0,
    north: 6000,
    east: 0,
    down: 0,
  );
  return RoadGraph(
    nodes: [
      const RoadNode(id: 1, lat: startLat, lon: startLon),
      RoadNode(id: 2, lat: end[0], lon: end[1]),
    ],
    edges: [
      RoadEdge(
        id: 10,
        fromNode: 1,
        toNode: 2,
        polyline: [startLat, startLon, end[0], end[1]],
        roadClass: RoadClass.primary,
        name: 'NH-48',
        tunnel: tunnel,
      ),
    ],
  );
}

void run(
  NavigationEngine engine,
  DriveSimulator sim,
  List<DriveSegment> segments, {
  required bool gnss,
  required _GnssClock clock,
}) {
  for (final segment in segments) {
    final steps = (segment.seconds * sim.imuHz).round();
    for (var i = 0; i < steps; i++) {
      final frame = sim.step(segment);
      engine.onImu(
        accelPhone: frame.accelPhone,
        gyroPhone: frame.gyroPhone,
        monotonicUs: frame.truth.monotonicUs,
      );
      if (frame.truth.monotonicUs >= clock.nextUs) {
        clock.nextUs = frame.truth.monotonicUs + 1000000;
        if (gnss) {
          engine.onGnss(sim.gnss());
        } else {
          engine.onGnssLost(frame.truth.monotonicUs);
        }
      }
    }
  }
}

class _GnssClock {
  int nextUs = 0;
}

void main() {
  group('map matching in the engine', () {
    test('with no road graph it stays unavailable and never fabricates a match',
        () {
      final engine = NavigationEngine();
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      final clock = _GnssClock();
      run(engine, sim, calibrationDrive(), gnss: true, clock: clock);

      expect(engine.hasRoadGraph, isFalse);
      expect(engine.mapMatch, isNull);
      final health = engine.snapshot!.mapMatch;
      expect(health.available, isFalse);
      expect(health.source, DataSource.unavailable);
      expect(health.detail, 'No road graph');
      expect(engine.snapshot!.mapMatchResult, isNull);
      expect(engine.snapshot!.matchedLatitude, isNull);
      expect(engine.snapshot!.contribution.map, 0);
    });

    test('with a graph it matches the road the vehicle is on', () {
      final engine = NavigationEngine(roadGraph: northRoad());
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      final clock = _GnssClock();
      run(engine, sim, calibrationDrive(), gnss: true, clock: clock);
      run(
        engine,
        sim,
        const [
          DriveSegment(seconds: 10, longitudinalAccel: 1.5),
          DriveSegment(seconds: 10),
        ],
        gnss: true,
        clock: clock,
      );

      expect(engine.hasRoadGraph, isTrue);
      final match = engine.mapMatch;
      expect(match, isNotNull);
      expect(match!.best?.edgeId, 10);
      expect(match.best?.roadName, 'NH-48');
      expect(match.snapped, isTrue);
      expect(engine.snapshot!.mapMatch.available, isTrue);
      expect(engine.snapshot!.mapMatch.source, DataSource.real);
    });

    test('the map constrains heading but never pushes position into the state',
        () {
      final engine = NavigationEngine(roadGraph: northRoad());
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      final clock = _GnssClock();
      run(engine, sim, calibrationDrive(), gnss: true, clock: clock);
      run(
        engine,
        sim,
        const [
          DriveSegment(seconds: 10, longitudinalAccel: 1.5),
          DriveSegment(seconds: 10),
        ],
        gnss: true,
        clock: clock,
      );

      final names =
          engine.recentMeasurements.map((m) => m.name).toSet();
      // Heading feedback happens...
      expect(names, contains('map_heading'));
      // ...and no position update ever comes from the map.
      expect(names.any((n) => n.startsWith('map') && n.contains('position')),
          isFalse);

      // The filter's own position is NOT the snapped one — the snap is
      // published for drawing, not folded in.
      final snapshot = engine.snapshot!;
      if (snapshot.matchedLatitude != null) {
        final difference = NavMath.horizontalDistance(
          lat0: snapshot.latitude!,
          lon0: snapshot.longitude!,
          lat1: snapshot.matchedLatitude!,
          lon1: snapshot.matchedLongitude!,
        );
        expect(difference, greaterThan(0));
      }
    });

    test('a matched outage reports map-assisted dead reckoning', () {
      final engine = NavigationEngine(roadGraph: northRoad(tunnel: true));
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      final clock = _GnssClock();
      run(engine, sim, calibrationDrive(), gnss: true, clock: clock);
      run(
        engine,
        sim,
        const [
          DriveSegment(seconds: 10, longitudinalAccel: 1.5),
          DriveSegment(seconds: 5),
        ],
        gnss: true,
        clock: clock,
      );
      run(
        engine,
        sim,
        const [DriveSegment(seconds: 30)],
        gnss: false,
        clock: clock,
      );

      expect(engine.mode, NavMode.mapAssistedDeadReckoning);
      expect(engine.mode.isDeadReckoning, isTrue);
      expect(engine.snapshot!.positionSource, DataSource.estimated);
      expect(engine.mapMatch!.best!.tunnel, isTrue);
    });

    test('map heading feedback shows up in the fusion contribution', () {
      final engine = NavigationEngine(roadGraph: northRoad());
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      final clock = _GnssClock();
      run(engine, sim, calibrationDrive(), gnss: true, clock: clock);
      run(
        engine,
        sim,
        const [
          DriveSegment(seconds: 10, longitudinalAccel: 1.5),
          DriveSegment(seconds: 10),
        ],
        gnss: true,
        clock: clock,
      );

      final contribution = engine.snapshot!.contribution;
      expect(contribution.map, greaterThan(0));
      expect(
        contribution.gnss + contribution.inertial + contribution.ai +
            contribution.map,
        closeTo(1.0, 1e-9),
      );
      // The map is a constraint, not the thing holding the position up.
      expect(contribution.map, lessThan(contribution.gnss));
    });

    test('a graph of the wrong roads is refused rather than snapped to', () {
      // The road runs east-west; the vehicle drives north.
      final start = NavMath.addNed(
        latDeg: 28.6139,
        lonDeg: 77.2090,
        altM: 0,
        north: 300,
        east: -3000,
        down: 0,
      );
      final end = NavMath.addNed(
        latDeg: 28.6139,
        lonDeg: 77.2090,
        altM: 0,
        north: 300,
        east: 3000,
        down: 0,
      );
      final wrongGraph = RoadGraph(
        nodes: [
          RoadNode(id: 1, lat: start[0], lon: start[1]),
          RoadNode(id: 2, lat: end[0], lon: end[1]),
        ],
        edges: [
          RoadEdge(
            id: 10,
            fromNode: 1,
            toNode: 2,
            polyline: [start[0], start[1], end[0], end[1]],
            name: 'Cross Street',
          ),
        ],
      );

      final engine = NavigationEngine(roadGraph: wrongGraph);
      final sim = DriveSimulator(mount: PhoneMount.tilted());
      final clock = _GnssClock();
      run(engine, sim, calibrationDrive(), gnss: true, clock: clock);
      run(
        engine,
        sim,
        const [
          DriveSegment(seconds: 10, longitudinalAccel: 1.5),
          DriveSegment(seconds: 15),
        ],
        gnss: true,
        clock: clock,
      );

      expect(engine.mapMatch?.snapped ?? false, isFalse);
      expect(engine.mode, isNot(NavMode.mapAssistedDeadReckoning));
      expect(engine.snapshot!.matchedLatitude, isNull);
    });
  });
}
