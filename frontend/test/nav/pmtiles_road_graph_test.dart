import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/pmtiles_road_graph.dart';

// The same small archive offline_map_service_test.dart, pack_installer_test.dart
// and region_extractor_test.dart use, cut around 77.050-77.080E, 28.630-28.650N
// (Delhi). No network, no app packs: proves buildRoadGraphFromPmtiles reads a
// bare .pmtiles file directly with the app's own tile decoder and graph
// builder (tile_roads.dart), which is what DRIVE_MAP on the headless benchmark
// relies on.
void main() {
  final fixture = File('test/fixtures/mini_delhi.pmtiles');

  test('builds a road graph from a small pmtiles fixture', () async {
    final graph = await buildRoadGraphFromPmtiles(
      fixture.path,
      south: 28.630,
      west: 77.050,
      north: 28.650,
      east: 77.080,
    );

    expect(graph, isNotNull);
    expect(graph!.edgeCount, greaterThan(0));
    // A point in the middle of the box should have a road nearby.
    expect(graph.nearby(28.640, 77.065, radiusM: 500), isNotEmpty);
  }, skip: fixture.existsSync() ? false : 'test/fixtures/mini_delhi.pmtiles missing');

  test('a box with nothing in it gives an empty-or-null graph, never throws',
      () async {
    final graph = await buildRoadGraphFromPmtiles(
      fixture.path,
      south: 0,
      west: 0,
      north: 0.01,
      east: 0.01,
    );
    expect(graph == null || graph.isEmpty, isTrue);
  }, skip: fixture.existsSync() ? false : 'test/fixtures/mini_delhi.pmtiles missing');
}
