import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/map/tile_roads.dart';
import 'package:gatisaarth/core/platform/maps/pack_reader.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../support/synthetic_road_tile.dart';

const _tileZ = 15, _tileX = 23398, _tileY = 13661; // 28.639, 77.0661

/// Independent of the code under test: standard slippy-map inverse, with
/// fractional tile coordinates.
double _lonAt(int z, double x) => x / (1 << z) * 360 - 180;
double _latAt(int z, double y) {
  final n = math.pi * (1 - 2 * y / (1 << z));
  return math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
}

/// A point [eastM] / [northM] metres from a fixed origin in Delhi.
const _lat0 = 28.639, _lon0 = 77.0661;
double _latOf(double northM) => _lat0 + northM / 111320.0;
double _lonOf(double eastM) =>
    _lon0 + eastM / (111320.0 * math.cos(_lat0 * math.pi / 180));

TileRoadLine _line(
  List<(double, double)> eastNorth, {
  RoadClass roadClass = RoadClass.residential,
  bool oneWay = false,
  bool bridge = false,
  String? name,
}) =>
    TileRoadLine(
      latLon: [
        for (final p in eastNorth) ...[_latOf(p.$2), _lonOf(p.$1)],
      ],
      roadClass: roadClass,
      oneWay: oneWay,
      bridge: bridge,
      name: name,
    );

double _totalLengthM(RoadGraph g) => g.edges.fold(0.0, (s, e) => s + e.lengthM);

List<TileRoadLine> _decode(List<SynthRoad> roads, {bool clip = false}) =>
    decodeRoadTile(syntheticRoadTile(roads), _tileZ, _tileX, _tileY,
        clipToTile: clip);

SynthRoad _road(String kind, String? detail, [Map<String, Object>? more]) =>
    SynthRoad([
      [(100, 100), (900, 100)]
    ], {
      'kind': kind,
      if (detail != null) 'kind_detail': detail,
      ...?more,
    });

void main() {
  group('tileOf', () {
    test('finds the Delhi tile and clamps at the poles and the date line', () {
      expect(tileOf(28.639, 77.0661, 15), (x: _tileX, y: _tileY));
      expect(tileOf(0, 0, 1), (x: 1, y: 1));
      expect(tileOf(89.9, 0, 3).y, 0);
      expect(tileOf(-89.9, 0, 3).y, 7);
      expect(tileOf(0, 180, 3).x, 7);
      expect(tileOf(0, -180, 3).x, 0);
    });
  });

  group('decodeRoadTile on a hand-made tile', () {
    test('keeps roads a car can use and drops everything else', () {
      final roads = <(SynthRoad, RoadClass?)>[
        (_road('highway', 'motorway'), RoadClass.motorway),
        (_road('highway', 'motorway_link'), RoadClass.motorway),
        (_road('major_road', 'trunk'), RoadClass.trunk),
        (_road('major_road', 'primary'), RoadClass.primary),
        (_road('major_road', 'primary_link'), RoadClass.primary),
        (_road('major_road', 'secondary'), RoadClass.secondary),
        (_road('major_road', 'tertiary'), RoadClass.tertiary),
        (_road('medium_road', 'secondary'), RoadClass.secondary),
        (_road('medium_road', 'tertiary'), RoadClass.tertiary),
        (_road('medium_road', null), RoadClass.secondary),
        (_road('minor_road', 'residential'), RoadClass.residential),
        (_road('minor_road', 'service'), RoadClass.service),
        (_road('minor_road', 'alley'), RoadClass.service),
        (_road('minor_road', 'unclassified'), RoadClass.unclassified),
        (_road('minor_road', 'road'), RoadClass.unclassified),
        (_road('other', 'living_street'), RoadClass.residential),
        (_road('other', 'busway'), null),
        (_road('other', 'bus_stop'), null),
        (_road('path', 'footway'), null),
        (_road('path', 'pedestrian'), null),
        (_road('path', 'steps'), null),
        (_road('path', 'cycleway'), null),
        (_road('rail', 'rail'), null),
        (_road('rail', 'subway'), null),
        (_road('ferry', null), null),
        (_road('aeroway', 'runway'), null),
        (_road('aerialway', 'gondola'), null),
      ];
      // Every feature sits at its own height so its line can be told apart.
      final tile = [
        for (var i = 0; i < roads.length; i++)
          SynthRoad([
            [(100, 100 + i * 100), (900, 100 + i * 100)]
          ], roads[i].$1.props),
      ];
      final decoded = _decode(tile);
      final expected = [
        for (var i = 0; i < roads.length; i++)
          if (roads[i].$2 != null) roads[i].$2,
      ];
      expect(decoded.map((l) => l.roadClass).toList(), expected);
      expect(decoded, hasLength(16));
    });

    test('drops private, no-access and military roads, keeps the rest', () {
      final decoded = _decode([
        for (final (i, a) in ['private', 'no', 'military', 'permissive', 'yes',
            'customers', 'destination'].indexed)
          SynthRoad([
            [(100, 100 + i * 100), (900, 100 + i * 100)]
          ], {'kind': 'minor_road', 'kind_detail': 'service', 'access': a}),
        _road('minor_road', 'service'),
      ]);
      // permissive, yes, customers, destination and the one without a tag.
      expect(decoded, hasLength(5));
    });

    test('oneway yes keeps the digitised direction', () {
      final l = _decode([
        SynthRoad([
          [(100, 100), (500, 100), (900, 300)]
        ], {'kind': 'minor_road', 'kind_detail': 'residential', 'oneway': 'yes'})
      ]).single;
      expect(l.oneWay, isTrue);
      // West to east: longitude grows along the line.
      expect(l.latLon[3], lessThan(l.latLon[l.latLon.length - 1]));
    });

    test('oneway -1 reverses the line and marks it one-way', () {
      final yes = _decode([
        SynthRoad([
          [(100, 100), (500, 100), (900, 300)]
        ], {'kind': 'minor_road', 'kind_detail': 'residential', 'oneway': 'yes'})
      ]).single;
      final rev = _decode([
        SynthRoad([
          [(100, 100), (500, 100), (900, 300)]
        ], {'kind': 'minor_road', 'kind_detail': 'residential', 'oneway': '-1'})
      ]).single;
      expect(rev.oneWay, isTrue);
      final pts = yes.latLon.length ~/ 2;
      for (var i = 0; i < pts; i++) {
        expect(rev.latLon[i * 2], yes.latLon[(pts - 1 - i) * 2]);
        expect(rev.latLon[i * 2 + 1], yes.latLon[(pts - 1 - i) * 2 + 1]);
      }
    });

    test('oneway no, reversible and absent mean both directions', () {
      for (final v in ['no', 'reversible', null]) {
        final l = _decode([
          _road('minor_road', 'residential', {if (v != null) 'oneway': v})
        ]).single;
        expect(l.oneWay, isFalse, reason: '$v');
      }
    });

    test('carries bridge, tunnel and name', () {
      final l = _decode([
        _road('major_road', 'primary', {
          'is_bridge': true,
          'is_tunnel': false,
          'name': 'Ring Road',
        })
      ]).single;
      expect(l.bridge, isTrue);
      expect(l.tunnel, isFalse);
      expect(l.name, 'Ring Road');
      final t = _decode([
        _road('major_road', 'primary', {'is_tunnel': true})
      ]).single;
      expect(t.tunnel, isTrue);
      expect(t.bridge, isFalse);
      expect(t.name, isNull);
    });

    test('a MultiLineString becomes one line per part', () {
      final lines = _decode([
        SynthRoad([
          [(100, 100), (900, 100)],
          [(100, 2000), (500, 2200), (900, 2000)],
        ], {'kind': 'minor_road', 'kind_detail': 'residential', 'oneway': 'yes'})
      ]);
      expect(lines, hasLength(2));
      expect(lines.map((l) => l.latLon.length ~/ 2), [2, 3]);
      expect(lines.every((l) => l.oneWay), isTrue);
    });

    test('Web-Mercator conversion is accurate to well under half a metre', () {
      // Tile 2/2/1 starts at longitude 0 and at the latitude where the world
      // square's y is 1/4: atan(sinh(pi/2)) = 66.51326044 degrees, a
      // textbook constant. Its middle (px 2048) is 45 degrees east.
      final l = decodeRoadTile(
        syntheticRoadTile([
          SynthRoad([
            [(0, 0), (2048, 0)]
          ], {'kind': 'major_road', 'kind_detail': 'primary'})
        ]),
        2,
        2,
        1,
      ).single;
      const mPerDeg = 111320.0;
      expect((l.latLon[0] - 66.51326044) * mPerDeg, closeTo(0, 0.5));
      expect((l.latLon[1] - 0.0) * mPerDeg, closeTo(0, 0.5));
      expect((l.latLon[3] - 45.0) * mPerDeg * math.cos(66.5 * math.pi / 180),
          closeTo(0, 0.5));
    });

    test('the world centre is 0, 0', () {
      final l = decodeRoadTile(
        syntheticRoadTile([
          SynthRoad([
            [(2048, 2048), (2100, 2048)]
          ], {'kind': 'major_road', 'kind_detail': 'primary'})
        ]),
        0,
        0,
        0,
      ).single;
      expect(l.latLon[0], closeTo(0, 1e-9));
      expect(l.latLon[1], closeTo(0, 1e-9));
    });

    test('lines shorter than a metre are dropped', () {
      // z15 is ~0.27 m per tile unit at this latitude.
      final decoded = _decode([
        SynthRoad([
          [(100, 100), (101, 100)]
        ], {'kind': 'minor_road', 'kind_detail': 'service'}),
        SynthRoad([
          [(200, 100), (200, 100)]
        ], {'kind': 'minor_road', 'kind_detail': 'service'}),
        SynthRoad([
          [(300, 100), (310, 100)]
        ], {'kind': 'minor_road', 'kind_detail': 'service'}),
      ]);
      expect(decoded, hasLength(1));
    });

    test('vertices reach into the tile buffer unless asked to clip', () {
      final road = SynthRoad([
        [(-64, 2000), (2000, 2000), (4160, 2000)]
      ], {'kind': 'major_road', 'kind_detail': 'primary'});
      final raw = _decode([road]).single;
      final west = _lonAt(_tileZ, _tileX.toDouble());
      final east = _lonAt(_tileZ, _tileX + 1.0);
      expect(raw.latLon.first, isNotNull);
      expect(raw.latLon[1], lessThan(west));
      expect(raw.latLon[raw.latLon.length - 1], greaterThan(east));

      final clipped = _decode([road], clip: true).single;
      expect(clipped.latLon[1], closeTo(west, 1e-9));
      expect(clipped.latLon[clipped.latLon.length - 1], closeTo(east, 1e-9));
    });

    test('clipping cuts a line that leaves and re-enters into two pieces', () {
      final lines = _decode([
        SynthRoad([
          [(100, 100), (2000, 100), (2000, -60), (3000, -60), (3000, 300),
            (3500, 300)]
        ], {'kind': 'minor_road', 'kind_detail': 'residential'})
      ], clip: true);
      expect(lines, hasLength(2));
      final north = _latAt(_tileZ, _tileY.toDouble());
      for (final l in lines) {
        for (var i = 0; i < l.latLon.length; i += 2) {
          expect(l.latLon[i], lessThanOrEqualTo(north + 1e-9));
        }
      }
    });

    test('clipping drops a line that never enters the tile', () {
      final lines = _decode([
        SynthRoad([
          [(-60, 100), (-10, 100)]
        ], {'kind': 'minor_road', 'kind_detail': 'residential'}),
        SynthRoad([
          [(4100, 100), (4150, 3000)]
        ], {'kind': 'minor_road', 'kind_detail': 'residential'}),
      ], clip: true);
      expect(lines, isEmpty);
    });

    test('a tile without a roads layer, an empty tile and junk give nothing',
        () {
      expect(
        decodeRoadTile(
          syntheticRoadTile([_road('major_road', 'primary')], layer: 'water'),
          _tileZ,
          _tileX,
          _tileY,
        ),
        isEmpty,
      );
      expect(decodeRoadTile(Uint8List(0), _tileZ, _tileX, _tileY), isEmpty);
      final junk = Uint8List.fromList(List.generate(300, (i) => (i * 37) % 251));
      expect(decodeRoadTile(junk, _tileZ, _tileX, _tileY), isEmpty);
      // Truncated in the middle of a valid tile.
      final good = syntheticRoadTile([_road('major_road', 'primary')]);
      final cut = Uint8List.sublistView(good, 0, good.length - 7);
      expect(() => decodeRoadTile(cut, _tileZ, _tileX, _tileY), returnsNormally);
    });

    test('one damaged feature does not cost the tile its other roads', () {
      final tile = syntheticRoadTile([
        _road('major_road', 'primary'),
        SynthRoad([
          [(100, 900), (900, 900)]
        ], const {}, true),
        _road('minor_road', 'residential'),
      ]);
      expect(decodeRoadTile(tile, _tileZ, _tileX, _tileY), hasLength(2));
    });
  });

  group('buildRoadGraph', () {
    test('no lines, or only degenerate ones, gives no graph', () {
      expect(buildRoadGraph(const []), isNull);
      expect(
        buildRoadGraph([
          const TileRoadLine(latLon: [28.0, 77.0]),
          const TileRoadLine(latLon: [28.0, 77.0, 28.0, 77.0]),
        ]),
        isNull,
      );
    });

    test('two roads crossing at a shared vertex meet in one node', () {
      final g = buildRoadGraph([
        _line([(-100, 0), (0, 0), (100, 0)]),
        _line([(0, -100), (0, 0), (0, 100)]),
      ])!;
      expect(g.edgeCount, 4, reason: 'each road is cut at the junction');
      expect(g.nodeCount, 5);
      final hub = g.nearby(_latOf(0), _lonOf(0), radiusM: 2).first;
      final node = g.edge(hub.edgeId)!;
      final hubNode = [node.fromNode, node.toNode]
          .firstWhere((n) => g.outgoing(n).length == 4);
      expect(g.outgoing(hubNode), hasLength(4));
    });

    test('a side street ending on a road vertex splits that road there', () {
      final g = buildRoadGraph([
        _line([(-100, 0), (0, 0), (100, 0)]),
        _line([(0, 0), (0, 100)]),
      ])!;
      expect(g.edgeCount, 3);
      expect(g.nodeCount, 4);
    });

    test('a road ending on a straight road that has no vertex there joins it',
        () {
      // A straight carriageway loses its junction vertex when a tile is
      // simplified, so the side street ends 0.3 m from a bare segment.
      final g = buildRoadGraph([
        _line([(-100, 0), (100, 0)]),
        _line([(0, 0.3), (0, 100)]),
      ])!;
      expect(g.edgeCount, 3, reason: 'the through road is cut at the join');
      expect(g.nodeCount, 4);
      final joint = g.nearby(_latOf(0), _lonOf(0), radiusM: 2)
          .map((p) => g.edge(p.edgeId)!)
          .expand((e) => [e.fromNode, e.toNode])
          .firstWhere((n) => g.outgoing(n).length == 3);
      expect(g.outgoing(joint), hasLength(3));
    });

    test('two side streets ending at the same spot from both sides make one '
        'crossing', () {
      final g = buildRoadGraph([
        _line([(-100, 0), (100, 0)]),
        _line([(0, 0.3), (0, 100)]),
        _line([(0, -0.3), (0, -100)]),
      ])!;
      expect(g.edgeCount, 4);
      expect(g.nodeCount, 5);
    });

    test('a road ending 3 m short of another is not joined to it', () {
      final g = buildRoadGraph([
        _line([(-100, 0), (100, 0)]),
        _line([(0, 3), (0, 100)]),
      ])!;
      expect(g.edgeCount, 2);
      expect(g.nodeCount, 4);
    });

    test('a road ending on another one keeps a one-way road one-way', () {
      final g = buildRoadGraph([
        _line([(-100, 0), (100, 0)], oneWay: true),
        _line([(0, 0.3), (0, 100)]),
      ])!;
      final through = g.edges.where((e) => e.oneWay).toList();
      expect(through, hasLength(2));
      // The first half runs into the joint, the second leaves it.
      expect(through[0].toNode, through[1].fromNode);
      expect(g.node(through[0].fromNode)!.lon, lessThan(_lonOf(0)));
      expect(g.node(through[1].toNode)!.lon, greaterThan(_lonOf(0)));
    });

    test('two straight roads crossing with no vertex on either still meet',
        () {
      // Both lose their junction vertex when a tile is simplified.
      final g = buildRoadGraph([
        _line([(-100, 0), (100, 0)]),
        _line([(0, -100), (0, 100)]),
      ])!;
      expect(g.edgeCount, 4);
      expect(g.nodeCount, 5);
      final hub = g.nearby(_latOf(0), _lonOf(0), radiusM: 2)
          .map((p) => g.edge(p.edgeId)!)
          .expand((e) => [e.fromNode, e.toNode])
          .firstWhere((n) => g.outgoing(n).length == 4);
      expect(g.outgoing(hub), hasLength(4));
    });

    test('a crossing on a bridge or in a tunnel is not a junction', () {
      for (final other in [
        _line([(0, -100), (0, 100)], bridge: true),
        TileRoadLine(
          latLon: [_latOf(-100), _lonOf(0), _latOf(100), _lonOf(0)],
          tunnel: true,
        ),
      ]) {
        final g = buildRoadGraph([
          _line([(-100, 0), (100, 0)]),
          other,
        ])!;
        expect(g.edgeCount, 2);
        expect(g.nodeCount, 4);
      }
    });

    test('two roads crossing at a shallow angle are one road beside another',
        () {
      // 2 degrees apart: a merge or a copy of the same road, not a junction.
      final g = buildRoadGraph([
        _line([(-100, 0), (100, 0)]),
        _line([(-100, -3.5), (100, 3.5)]),
      ])!;
      expect(g.edgeCount, 2);
    });

    test('many straight roads crossing in a grid all meet', () {
      final g = buildRoadGraph([
        for (var i = 0; i < 4; i++) _line([(-150, i * 60.0), (150, i * 60.0)]),
        for (var i = 0; i < 4; i++) _line([(i * 80.0 - 120, -30), (i * 80.0 - 120, 220)]),
      ])!;
      // 16 crossings; each of the 8 roads is cut into 5 pieces.
      expect(g.edgeCount, 40);
      expect(g.nodeCount, 16 + 16);
    });

    test('ends within a metre share a node, ends 5 m apart do not', () {
      final near = buildRoadGraph([
        _line([(0, 0), (100, 0)]),
        _line([(100.6, 0.3), (200, 0)]),
      ])!;
      expect(near.nodeCount, 3);
      expect(near.edgeCount, 2);

      final far = buildRoadGraph([
        _line([(0, 0), (100, 0)]),
        _line([(105, 0), (200, 0)]),
      ])!;
      expect(far.nodeCount, 4);
    });

    test('an exact duplicate, in either direction, is one edge', () {
      final a = _line([(0, 0), (50, 20), (100, 0)]);
      final g = buildRoadGraph([a, a, _line([(100, 0), (50, 20), (0, 0)])])!;
      expect(g.edgeCount, 1);
    });

    test('overlapping copies from neighbouring tiles collapse to one road',
        () {
      // Tile A's copy runs 0..150 m, tile B's 100..250 m: they share the
      // vertices at 100 and 150 m, exactly as two tiles' buffers do.
      final a = _line([(0, 0), (50, 0), (100, 0), (150, 0)]);
      final b = _line([(100, 0), (150, 0), (200, 0), (250, 0)]);
      final g = buildRoadGraph([a, b])!;
      expect(g.edgeCount, 3);
      expect(_totalLengthM(g), closeTo(250, 2));
      final firstNode = g.node(g.edges.first.fromNode)!;
      expect(firstNode, isNotNull);
    });

    test('a one-way road keeps its direction of travel', () {
      final g = buildRoadGraph([
        _line([(0, 0), (60, 0), (120, 10)], oneWay: true),
      ])!;
      final e = g.edges.single;
      expect(e.oneWay, isTrue);
      expect(g.node(e.fromNode)!.lon, closeTo(_lonOf(0), 1e-7));
      expect(g.node(e.toNode)!.lon, closeTo(_lonOf(120), 1e-7));
      expect(g.outgoing(e.fromNode), [e.id]);
      expect(g.outgoing(e.toNode), isEmpty);
    });

    test('a bridge over a road is not joined to it', () {
      final g = buildRoadGraph([
        _line([(-100, 0), (100, 0)]),
        _line([(0, -100), (0, 100)], bridge: true),
      ])!;
      expect(g.edgeCount, 2);
      expect(g.nodeCount, 4);
      expect(g.edges.where((e) => e.bridge), hasLength(1));
    });

    test('class, name and access reach the edge, and nearby finds the road',
        () {
      final g = buildRoadGraph(
        [
          _line([(0, 0), (200, 0)],
              roadClass: RoadClass.primary, name: 'Outer Ring Road'),
        ],
        region: 'delhi-ncr',
      )!;
      expect(g.region, 'delhi-ncr');
      final e = g.edges.single;
      expect(e.roadClass, RoadClass.primary);
      expect(e.name, 'Outer Ring Road');
      expect(e.allows(VehicleAccess.cars), isTrue);
      expect(e.allows(VehicleAccess.twoWheelers), isTrue);

      final hits = g.nearby(_latOf(5), _lonOf(100), radiusM: 20);
      expect(hits, hasLength(1));
      expect(hits.single.perpendicularM, closeTo(5, 0.5));
      expect(g.nearby(_latOf(300), _lonOf(100), radiusM: 20), isEmpty);
    });

    test('a closed loop still builds', () {
      final g = buildRoadGraph([
        _line([(0, 0), (100, 0), (100, 100), (0, 100), (0, 0)]),
      ])!;
      expect(g.edgeCount, 1);
      final e = g.edges.single;
      expect(e.fromNode, e.toNode);
    });
  });

  // ---------------------------------------------------------------- real data
  group('the real Delhi archive', () {
    final file = File('assets/maps/packs/delhi-ncr.pmtiles');
    final present = file.existsSync();
    late PmTilesVectorTileProvider provider;

    setUpAll(() async {
      if (!present) return;
      // ignore: invalid_use_of_visible_for_testing_member
      final archive = await PmTilesArchive.fromReadAt(OffsetFileAt(file));
      provider = PmTilesVectorTileProvider.fromArchive(archive);
    });

    Future<Uint8List> bytesOf(int x, int y) =>
        provider.provide(TileIdentity(_tileZ, x, y));

    test('one tile decodes to plausible roads within its buffer', () async {
      final lines = decodeRoadTile(
          await bytesOf(_tileX, _tileY), _tileZ, _tileX, _tileY);
      expect(lines, isNotEmpty);

      const pad = 65 / 4096; // buffer plus rounding
      final west = _lonAt(_tileZ, _tileX - pad);
      final east = _lonAt(_tileZ, _tileX + 1 + pad);
      final north = _latAt(_tileZ, _tileY - pad);
      final south = _latAt(_tileZ, _tileY + 1 + pad);
      for (final l in lines) {
        expect(l.latLon.length, greaterThanOrEqualTo(4));
        expect(l.latLon.length.isEven, isTrue);
        for (var i = 0; i < l.latLon.length; i += 2) {
          expect(l.latLon[i], inInclusiveRange(south, north));
          expect(l.latLon[i + 1], inInclusiveRange(west, east));
        }
      }

      // The tile also holds footways and the metro; those must be gone. Its
      // `roads` layer has 23 features, some of them multi-part.
      final classes = lines.map((l) => l.roadClass).toSet();
      expect(classes, contains(RoadClass.residential));
      expect(
        classes.intersection({
          RoadClass.primary,
          RoadClass.secondary,
          RoadClass.tertiary,
          RoadClass.trunk,
        }),
        isNotEmpty,
      );
    });

    test('a 5x5 block has one-way roads and every class of street', () async {
      final all = <TileRoadLine>[];
      for (var dx = -2; dx <= 2; dx++) {
        for (var dy = -2; dy <= 2; dy++) {
          all.addAll(decodeRoadTile(await bytesOf(_tileX + dx, _tileY + dy),
              _tileZ, _tileX + dx, _tileY + dy));
        }
      }
      expect(all.length, greaterThan(300));
      expect(all.where((l) => l.oneWay), isNotEmpty);
      expect(all.where((l) => l.bridge), isNotEmpty);
      expect(all.map((l) => l.roadClass).toSet(),
          containsAll([RoadClass.residential, RoadClass.tertiary]));
    });

    test('a 3x3 block builds a graph with a road under the start point',
        () async {
      final all = <TileRoadLine>[];
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          all.addAll(decodeRoadTile(await bytesOf(_tileX + dx, _tileY + dy),
              _tileZ, _tileX + dx, _tileY + dy));
        }
      }
      final sw = Stopwatch()..start();
      final g = buildRoadGraph(all, region: 'delhi-ncr')!;
      sw.stop();
      // ignore: avoid_print
      print('3x3 block: ${all.length} lines -> ${g.edgeCount} edges, '
          '${g.nodeCount} nodes in ${sw.elapsedMilliseconds} ms');
      expect(g.edgeCount, greaterThan(100));
      expect(g.nearby(28.639, 77.0661, radiusM: 150), isNotEmpty);
    });

    Future<RoadGraph> clippedGraph(int radius) async {
      final all = <TileRoadLine>[];
      for (var dx = -radius; dx <= radius; dx++) {
        for (var dy = -radius; dy <= radius; dy++) {
          all.addAll(decodeRoadTile(await bytesOf(_tileX + dx, _tileY + dy),
              _tileZ, _tileX + dx, _tileY + dy,
              clipToTile: true));
        }
      }
      return buildRoadGraph(all)!;
    }

    test('one-way roads run the way the tile says (left-hand traffic)',
        () async {
      // India drives on the left, so the opposite carriageway of a divided
      // road lies to the RIGHT of each one-way line's direction of travel. A
      // tile whose line direction did not follow the road's would flip this.
      final g = await clippedGraph(2);
      var right = 0, left = 0;
      for (final e in g.edges.where((e) => e.oneWay && e.lengthM > 30)) {
        final lat = e.latAt(e.pointCount ~/ 2), lon = e.lonAt(e.pointCount ~/ 2);
        final here = g.project(e.id, lat, lon)!;
        for (final o in g.nearby(lat, lon, radiusM: 45, limit: 12)) {
          if (o.edgeId == e.id || !g.edge(o.edgeId)!.oneWay) continue;
          var apart = (o.headingRad - here.headingRad).abs() % (2 * math.pi);
          if (apart > math.pi) apart = 2 * math.pi - apart;
          if (apart < math.pi - 0.35 || o.perpendicularM < 4) continue;
          final bearing = math.atan2(
            (o.lon - lon) * math.cos(lat * math.pi / 180),
            o.lat - lat,
          );
          var rel = bearing - here.headingRad;
          while (rel > math.pi) {
            rel -= 2 * math.pi;
          }
          while (rel < -math.pi) {
            rel += 2 * math.pi;
          }
          rel > 0 ? right++ : left++;
          break;
        }
      }
      expect(right + left, greaterThan(50));
      expect(right, greaterThan(left * 10), reason: '$right right, $left left');
    });

    test('a road that ends on another road is joined to it', () async {
      // Tiles drop a straight road's junction vertex, so most side streets end
      // a few centimetres off a bare segment. After noding, a dead end that
      // sits on another road should be the rare exception.
      final g = await clippedGraph(1);
      final touching = <int, List<int>>{};
      for (final e in g.edges) {
        (touching[e.fromNode] ??= []).add(e.id);
        (touching[e.toNode] ??= []).add(e.id);
      }
      final nw = tileCorner(_tileZ, _tileX - 1, _tileY - 1);
      final se = tileCorner(_tileZ, _tileX + 2, _tileY + 2);
      var dead = 0, onARoad = 0;
      for (final entry in touching.entries) {
        if (entry.value.length != 1) continue;
        final n = g.node(entry.key)!;
        // Roads are cut off at the edge of the block: not dead ends.
        if (n.lat > nw.lat - 0.0005 || n.lat < se.lat + 0.0005) continue;
        if (n.lon < nw.lon + 0.0005 || n.lon > se.lon - 0.0005) continue;
        dead++;
        if (g.nearby(n.lat, n.lon, radiusM: 3, limit: 5)
            .any((p) => p.edgeId != entry.value.single)) {
          onARoad++;
        }
      }
      expect(dead, greaterThan(100));
      expect(onARoad / dead, lessThan(0.03), reason: '$onARoad of $dead');
    });

    test('clipped tiles join up across their shared border', () async {
      // Two tiles side by side: a road that crosses their border must come out
      // as one road, an edge on each side of a shared node, not two dead ends.
      final clipped = <TileRoadLine>[
        ...decodeRoadTile(await bytesOf(_tileX, _tileY), _tileZ, _tileX, _tileY,
            clipToTile: true),
        ...decodeRoadTile(
            await bytesOf(_tileX + 1, _tileY), _tileZ, _tileX + 1, _tileY,
            clipToTile: true),
      ];
      final border = _lonAt(_tileZ, _tileX + 1.0);
      final g = buildRoadGraph(clipped)!;
      final touching = <int, int>{};
      for (final e in g.edges) {
        touching[e.fromNode] = (touching[e.fromNode] ?? 0) + 1;
        touching[e.toNode] = (touching[e.toNode] ?? 0) + 1;
      }
      var crossing = 0, joined = 0;
      for (final entry in touching.entries) {
        final node = g.node(entry.key)!;
        if ((node.lon - border).abs() * 97800 > 2) continue; // metres
        crossing++;
        if (entry.value >= 2) joined++;
      }
      expect(crossing, greaterThan(0));
      expect(joined / crossing, greaterThan(0.9),
          reason: '$joined of $crossing border nodes joined');
    });
  }, skip: File('assets/maps/packs/delhi-ncr.pmtiles').existsSync()
      ? false
      : 'delhi-ncr.pmtiles not on this machine');
}
