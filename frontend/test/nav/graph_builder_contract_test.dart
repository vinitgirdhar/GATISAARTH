import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/map_matcher.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';

/// The Python builder and the Dart loader have to agree, and nothing else
/// checks that: `maps/tools/graph_builder.py` writes the file, this reads it.
///
/// The fixture was produced by that builder from a small Overpass document
/// (see its `_self_check`). Regenerate it if the format changes — a silent
/// mismatch here would mean the app quietly refuses every region a user builds.
void main() {
  late RoadGraph graph;

  setUpAll(() {
    final file = File('test/nav/support/graph_builder_fixture.json');
    expect(file.existsSync(), isTrue,
        reason: 'fixture missing; regenerate with graph_builder.py');
    final loaded = RoadGraph.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
    expect(loaded, isNotNull, reason: 'Dart could not load the built graph');
    graph = loaded!;
  });

  test('loads what the Python builder wrote', () {
    expect(graph.region, 'fixture');
    expect(graph.version, 1);
    expect(graph.nodeCount, 4);
    expect(graph.edgeCount, 3);
  });

  test('the through road was split at the junction', () {
    final throughEdges = graph.edges
        .where((e) => e.name == 'North Road')
        .toList();
    expect(throughEdges, hasLength(2));
    for (final edge in throughEdges) {
      expect(edge.roadClass, RoadClass.primary);
      expect(edge.lengthM, closeTo(500, 15));
    }
  });

  test('tags survive the round trip', () {
    final north = graph.edges.firstWhere((e) => e.name == 'North Road');
    expect(north.tunnel, isTrue);
    expect(north.bridge, isFalse);
    expect(north.oneWay, isFalse);
    expect(north.maxSpeedMps, closeTo(16.67, 0.02));
    expect(north.allows(VehicleAccess.cars), isTrue);

    final lane = graph.edges.firstWhere((e) => e.name == 'Bike Lane');
    expect(lane.oneWay, isTrue);
    expect(lane.allows(VehicleAccess.cars), isFalse);
    expect(lane.allows(VehicleAccess.twoWheelers), isTrue);
    expect(lane.maxSpeedMps, isNull, reason: 'no tag means no value');
  });

  test('the footway was dropped, not imported as a road', () {
    expect(graph.edges.any((e) => e.roadClass == RoadClass.service), isFalse);
    expect(graph.edgeCount, 3);
  });

  test('the matcher works on it, and honours the access restriction', () {
    // A point just off the through road.
    final north = graph.edges.firstWhere((e) => e.name == 'North Road');
    final lat = north.latAt(0) + 0.0005;
    final lon = north.lonAt(0) + 0.00005;

    final forCars = MapMatcher(graph: graph, vehicle: VehicleAccess.cars);
    final first = forCars.update(lat: lat, lon: lon, sigmaM: 8);
    expect(first!.candidates, isNotEmpty);
    expect(first.snapped, isFalse, reason: 'never on the first fix');

    final second = forCars.update(
      lat: lat + 0.0002,
      lon: lon,
      sigmaM: 8,
      headingRad: 0,
      speedMps: 12,
    );
    expect(second!.snapped, isTrue);
    expect(second.best!.roadName, 'North Road');

    // The car-only matcher must not offer the bike lane.
    final lane = graph.edges.firstWhere((e) => e.name == 'Bike Lane');
    final onLane = forCars.update(
      lat: lane.latAt(1),
      lon: lane.lonAt(1),
      sigmaM: 5,
    );
    expect(
      onLane!.candidates.any((c) => c.roadName == 'Bike Lane'),
      isFalse,
    );
  });
}
