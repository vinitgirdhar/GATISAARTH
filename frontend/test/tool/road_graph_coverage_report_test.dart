import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/map/tile_roads.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' show TileIdentity;

import '../support/real_map_packs.dart';

/// Developer tool, not a test: measures what real road network the offline map
/// archives give the app, per region, and writes it to
/// `$EVIDENCE_DIR/road_graph_coverage.json` (pending_work.md items "populate
/// the Delhi NCR / Maharashtra road graph").
///
///     EVIDENCE_DIR=docs/evidence MAP_PACK_DIR=<folder of .pmtiles> \
///       flutter test test/tool/road_graph_coverage_report_test.dart
///
/// Region totals come from every tile of the archive (lines clipped at tile
/// edges, so nothing is counted twice); topology figures come from real 5x5
/// tile blocks of the same archive, built exactly as the phone builds them.
const _regions = <String>[
  'delhi-ncr',
  'mumbai',
  'pune',
  'nagpur',
  'nashik',
  'sambhajinagar',
  'maharashtra-state',
];

double _km(List<double> latLon) {
  var m = 0.0;
  for (var i = 0; i + 3 < latLon.length; i += 2) {
    m += NavMath.horizontalDistance(
      lat0: latLon[i],
      lon0: latLon[i + 1],
      lat1: latLon[i + 2],
      lon1: latLon[i + 3],
    );
  }
  return m / 1000;
}

/// Share of the graph's nodes in its biggest connected piece, degree stats.
Map<String, Object> _topology(RoadGraph graph) {
  final adjacency = <int, Set<int>>{};
  for (final e in graph.edges) {
    adjacency.putIfAbsent(e.fromNode, () => {}).add(e.toNode);
    adjacency.putIfAbsent(e.toNode, () => {}).add(e.fromNode);
  }
  final seen = <int>{};
  var largest = 0;
  for (final start in adjacency.keys) {
    if (seen.contains(start)) continue;
    var size = 0;
    final stack = [start];
    seen.add(start);
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      size++;
      for (final next in adjacency[n]!) {
        if (seen.add(next)) stack.add(next);
      }
    }
    largest = math.max(largest, size);
  }
  final nodes = adjacency.length;
  var junctions = 0;
  var deadEnds = 0;
  for (final neighbours in adjacency.values) {
    if (neighbours.length >= 3) junctions++;
    if (neighbours.length == 1) deadEnds++;
  }
  double pct(num a) => nodes == 0 ? 0 : double.parse((100 * a / nodes).toStringAsFixed(1));
  return {
    'edges': graph.edgeCount,
    'nodes': nodes,
    'junction_nodes_percent': pct(junctions),
    'dead_end_nodes_percent': pct(deadEnds),
    'largest_connected_piece_percent': pct(largest),
    'one_way_edges_percent': graph.edgeCount == 0
        ? 0
        : double.parse((100 *
                graph.edges.where((e) => e.oneWay).length /
                graph.edgeCount)
            .toStringAsFixed(1)),
  };
}

void main() {
  final out = Platform.environment['EVIDENCE_DIR'];
  final report = <String, Object>{};

  tearDownAll(() {
    if (out == null || report.isEmpty) return;
    File('$out/road_graph_coverage.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'what': 'Road network the app derives on the phone from its installed '
            'offline map archives (OpenStreetMap vector tiles, Protomaps '
            'schema v4). Region totals: every tile of the archive. Topology: '
            'sample 5x5-tile blocks built exactly as on the phone.',
        'regions': report,
      }),
    );
  });

  for (final id in _regions) {
    test('road network of $id',
        skip: out == null
            ? 'set EVIDENCE_DIR to write the coverage report'
            : skipUnlessPack(id),
        timeout: const Timeout(Duration(minutes: 15)), () async {
      final pack = OfflineCatalog.packs.firstWhere((p) => p.id == id);
      final source = (await openRealRoadSource(id))!;
      // The source keeps its service private; read tiles through a second one.
      final provider = source.maps.installed.single.provider;
      final z = math.min(15, provider.maximumZoom);
      final nw = tileOf(pack.north, pack.west, z);
      final se = tileOf(pack.south, pack.east, z);

      final kmByClass = <String, double>{};
      var oneWayKm = 0.0;
      var bridgeKm = 0.0;
      var tunnelKm = 0.0;
      var namedKm = 0.0;
      var lines = 0;
      var tilesWithRoads = 0;
      var tilesScanned = 0;
      final busiest = <({int x, int y, int lines})>[];

      for (var y = nw.y; y <= se.y; y++) {
        for (var x = nw.x; x <= se.x; x++) {
          tilesScanned++;
          List<TileRoadLine> tile;
          try {
            final bytes = await provider.provide(TileIdentity(z, x, y));
            tile = decodeRoadTile(bytes, z, x, y, clipToTile: true);
          } catch (_) {
            continue; // a hole in the archive is normal
          }
          if (tile.isEmpty) continue;
          tilesWithRoads++;
          lines += tile.length;
          busiest.add((x: x, y: y, lines: tile.length));
          for (final l in tile) {
            final km = _km(l.latLon);
            kmByClass.update(l.roadClass.name, (v) => v + km,
                ifAbsent: () => km);
            if (l.oneWay) oneWayKm += km;
            if (l.bridge) bridgeKm += km;
            if (l.tunnel) tunnelKm += km;
            if (l.name != null) namedKm += km;
          }
        }
      }

      final totalKm = kmByClass.values.fold(0.0, (a, b) => a + b);
      busiest.sort((a, b) => b.lines.compareTo(a.lines));
      final samples = <Map<String, Object>>[];
      // Blocks around the busiest tiles, spaced apart.
      final centres = <({int x, int y})>[];
      for (final t in busiest) {
        if (centres.any((c) => (c.x - t.x).abs() < 6 && (c.y - t.y).abs() < 6)) {
          continue;
        }
        centres.add((x: t.x, y: t.y));
        if (centres.length >= 6) break;
      }
      final n = (1 << z).toDouble();
      for (final c in centres) {
        final lon = (c.x + 0.5) / n * 360 - 180;
        final lat = tileCorner(z, c.x + 0.5, c.y + 0.5).lat;
        final coverage = await source.roadsAround(lat, lon);
        if (coverage == null) continue;
        samples.add(_topology(coverage.graph));
      }

      double r(double v) => double.parse(v.toStringAsFixed(1));
      report[id] = {
        'pack': pack.name,
        'archive_max_zoom': provider.maximumZoom,
        'tile_zoom_used': z,
        'tiles_scanned': tilesScanned,
        'tiles_with_roads': tilesWithRoads,
        'road_lines': lines,
        'drivable_km_total': r(totalKm),
        'drivable_km_by_class': {
          for (final e in kmByClass.entries) e.key: r(e.value),
        },
        'one_way_km_percent': totalKm == 0 ? 0 : r(100 * oneWayKm / totalKm),
        'bridge_km': r(bridgeKm),
        'tunnel_km': r(tunnelKm),
        'named_km_percent': totalKm == 0 ? 0 : r(100 * namedKm / totalKm),
        'minor_streets_present': z >= 13,
        'sample_block_topology': samples,
      };
      expect(lines, greaterThan(0));
    });
  }
}
