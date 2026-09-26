import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/tile_roads.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_reader.dart';
import 'package:gatisaarth/core/platform/maps/pack_road_source.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import 'support/fake_map_packs.dart';
import 'support/synthetic_road_tile.dart';

// Delhi, tile 15/23398/13661.
const _lat = 28.639, _lon = 77.0661;
const _cx = 23398, _cy = 13661;

/// Independent of the code under test.
double _lonAt(int z, num x) => x / (1 << z) * 360 - 180;
double _latAt(int z, num y) {
  final n = math.pi * (1 - 2 * y / (1 << z));
  return math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
}

/// One east-west road through the middle of a tile, so a row of tiles is one
/// long road and the graph over a block has exactly one edge per tile.
Uint8List _roadTile() => syntheticRoadTile([
      SynthRoad([
        [(0, 2048), (4096, 2048)]
      ], {'kind': 'minor_road', 'kind_detail': 'residential'}),
    ]);

/// Tiles from memory. Counts what it is asked for.
class _FakeTiles extends VectorTileProvider {
  _FakeTiles({this.maxZoom = 15, this.fails});

  final int maxZoom;
  final bool Function(TileIdentity)? fails;
  final List<TileIdentity> requested = [];

  @override
  int get maximumZoom => maxZoom;

  @override
  int get minimumZoom => 0;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    requested.add(tile);
    if (fails?.call(tile) ?? false) {
      throw ProviderException(
        message: 'Tile not found: $tile',
        retryable: Retryable.none,
        statusCode: 404,
      );
    }
    return _roadTile();
  }
}

OfflinePack _pack(String id) => OfflinePack(
      id: id,
      name: id,
      south: 28.38,
      west: 76.83,
      north: 28.90,
      east: 77.45,
      maxZoom: 15,
      approxBytes: 1,
    );

Future<OfflineMapService> _service(Map<String, VectorTileProvider> providers,
    {List<OfflinePack>? catalog}) async {
  final service = OfflineMapService(
    locator: FakeMapPackLocator({
      for (final id in providers.keys) '$id.pmtiles': fakeLocation(1000),
    }),
    opener: (l, p) async => providers[p.id]!,
    catalog: catalog ?? [for (final id in providers.keys) _pack(id)],
  );
  await service.load();
  return service;
}

/// Decoding in the test's own isolate, cutting at tile edges as the real one.
Future<List<TileRoadLine>> _decode(Uint8List b, int z, int x, int y) async =>
    decodeRoadTile(b, z, x, y, clipToTile: true);

PackRoadGraphSource _source(OfflineMapService s,
        {int radius = 2, int cache = 64}) =>
    PackRoadGraphSource(s,
        tileRadius: radius, maxCachedTiles: cache, decoder: _decode);

Set<TileIdentity> _block(int z, int cx, int cy, int r) => {
      for (var dx = -r; dx <= r; dx++)
        for (var dy = -r; dy <= r; dy++) TileIdentity(z, cx + dx, cy + dy),
    };

void main() {
  group('PackRoadGraphSource', () {
    test('reads a 5x5 block of tiles around the point and builds one graph',
        () async {
      final tiles = _FakeTiles();
      final source = _source(await _service({'a': tiles}));
      final coverage = await source.roadsAround(_lat, _lon);

      expect(coverage, isNotNull);
      expect(tiles.requested.toSet(), _block(15, _cx, _cy, 2));
      expect(tiles.requested, hasLength(25));
      expect(coverage!.graph.edgeCount, 25);
      expect(coverage.graph.region, 'a');
      expect(coverage.graph.nearby(_lat, _lon, radiusM: 400), isNotEmpty);
    });

    test('tileRadius sets the block size', () async {
      final tiles = _FakeTiles();
      final coverage =
          await _source(await _service({'a': tiles}), radius: 1)
              .roadsAround(_lat, _lon);
      expect(tiles.requested.toSet(), _block(15, _cx, _cy, 1));
      expect(coverage!.graph.edgeCount, 9);
    });

    test('the safe box is the centre tile plus one tile each way, and '
        'containsSafe agrees', () async {
      final coverage = (await _source(await _service({'a': _FakeTiles()}))
          .roadsAround(_lat, _lon))!;

      expect(coverage.safeNorth, closeTo(_latAt(15, _cy - 1), 1e-9));
      expect(coverage.safeSouth, closeTo(_latAt(15, _cy + 2), 1e-9));
      expect(coverage.safeWest, closeTo(_lonAt(15, _cx - 1), 1e-9));
      expect(coverage.safeEast, closeTo(_lonAt(15, _cx + 2), 1e-9));

      expect(coverage.containsSafe(_lat, _lon), isTrue);
      // The middle of the tile two east of the centre one is outside.
      expect(coverage.containsSafe(_lat, _lonAt(15, _cx + 2.5)), isFalse);
      // And of the one just inside the box.
      expect(coverage.containsSafe(_lat, _lonAt(15, _cx + 1.5)), isTrue);
      const eps = 1e-6;
      expect(coverage.containsSafe(_lat, coverage.safeEast - eps), isTrue);
      expect(coverage.containsSafe(_lat, coverage.safeEast + eps), isFalse);
      expect(coverage.containsSafe(coverage.safeNorth + eps, _lon), isFalse);
      expect(coverage.containsSafe(coverage.safeSouth - eps, _lon), isFalse);
      expect(coverage.containsSafe(_lat, coverage.safeWest - eps), isFalse);
    });

    test('one tile east reads only the five new tiles', () async {
      final tiles = _FakeTiles();
      final source = _source(await _service({'a': tiles}));
      await source.roadsAround(_lat, _lon);
      expect(tiles.requested, hasLength(25));

      final coverage =
          await source.roadsAround(_lat, _lonAt(15, _cx + 1.5));
      expect(tiles.requested, hasLength(30));
      expect(
        tiles.requested.skip(25).toSet(),
        {for (var dy = -2; dy <= 2; dy++) TileIdentity(15, _cx + 3, _cy + dy)},
      );
      expect(coverage!.graph.edgeCount, 25);

      // Standing still costs nothing.
      await source.roadsAround(_lat, _lonAt(15, _cx + 1.5));
      expect(tiles.requested, hasLength(30));

      // A diagonal step reads the L-shaped edge: 5 + 4.
      await source.roadsAround(_latAt(15, _cy + 1.5), _lonAt(15, _cx + 2.5));
      expect(tiles.requested, hasLength(39));
    });

    test('tiles that fall out of the cache are read again', () async {
      final tiles = _FakeTiles();
      final source = _source(await _service({'a': tiles}), radius: 1, cache: 9);
      await source.roadsAround(_lat, _lon);
      expect(tiles.requested, hasLength(9));
      await source.roadsAround(_lat, _lonAt(15, _cx + 10.5));
      expect(tiles.requested, hasLength(18));
      await source.roadsAround(_lat, _lon);
      expect(tiles.requested, hasLength(27));
    });

    test('clearCache makes the next call read everything again', () async {
      final tiles = _FakeTiles();
      final source = _source(await _service({'a': tiles}));
      await source.roadsAround(_lat, _lon);
      source.clearCache();
      await source.roadsAround(_lat, _lon);
      expect(tiles.requested, hasLength(50));
    });

    test('two calls at once share the reads', () async {
      final tiles = _FakeTiles();
      final source = _source(await _service({'a': tiles}));
      final both = await Future.wait([
        source.roadsAround(_lat, _lon),
        source.roadsAround(_lat, _lon),
      ]);
      expect(both.every((c) => c != null), isTrue);
      expect(tiles.requested, hasLength(25));
    });

    test('a tile the pack does not have is skipped, not fatal', () async {
      final tiles = _FakeTiles(
          fails: (t) => t == TileIdentity(15, _cx + 1, _cy)); // a hole
      final coverage = await _source(await _service({'a': tiles}))
          .roadsAround(_lat, _lon);
      expect(coverage, isNotNull);
      expect(coverage!.graph.edgeCount, 24);
      expect(coverage.containsSafe(_lat, _lon), isTrue);
    });

    test('a tile that throws something else is skipped too', () async {
      final tiles = _ThrowingTiles();
      final coverage = await _source(await _service({'a': tiles}))
          .roadsAround(_lat, _lon);
      expect(coverage, isNotNull);
      expect(coverage!.graph.edgeCount, 24);
    });

    test('a tile whose bytes are junk is skipped', () async {
      final tiles = _JunkTiles(junkAt: TileIdentity(15, _cx, _cy));
      final coverage = await _source(await _service({'a': tiles}))
          .roadsAround(_lat, _lon);
      expect(coverage!.graph.edgeCount, 24);
    });

    test('when every tile fails there is no answer', () async {
      final tiles = _FakeTiles(fails: (_) => true);
      final source = _source(await _service({'a': tiles}));
      expect(await source.roadsAround(_lat, _lon), isNull);
      expect(tiles.requested, hasLength(25));
    });

    test('a pack whose tiles have no roads gives no answer', () async {
      final tiles = _EmptyTiles();
      expect(
          await _source(await _service({'a': tiles})).roadsAround(_lat, _lon),
          isNull);
    });

    test('no pack over the point, or none installed, gives no answer',
        () async {
      final tiles = _FakeTiles();
      final source = _source(await _service({'a': tiles}));
      expect(await source.roadsAround(12.97, 77.59), isNull); // Bengaluru
      expect(tiles.requested, isEmpty);

      final none = _source(await noPacksInstalled());
      expect(await none.roadsAround(_lat, _lon), isNull);
    });

    test('a pack that stops at zoom 12 is too coarse and is ignored',
        () async {
      final low = _FakeTiles(maxZoom: 12);
      final source = _source(await _service({'low': low}));
      expect(await source.roadsAround(_lat, _lon), isNull);
      expect(low.requested, isEmpty);

      final edge = _FakeTiles(maxZoom: 13);
      final ok = await _source(await _service({'edge': edge}))
          .roadsAround(_lat, _lon);
      expect(ok, isNotNull);
      expect(edge.requested.every((t) => t.z == 13), isTrue);
    });

    test('of two packs over the point the more detailed one is used',
        () async {
      final coarse = _FakeTiles(maxZoom: 14);
      final fine = _FakeTiles(maxZoom: 15);
      final coverage = await _source(await _service({
        'coarse': coarse,
        'fine': fine,
      })).roadsAround(_lat, _lon);
      expect(coverage!.graph.region, 'fine');
      expect(fine.requested, hasLength(25));
      expect(coarse.requested, isEmpty);
    });

    test('tiles are read at zoom 15 even from a deeper pack, and at the '
        'pack\'s own zoom from a shallower one', () async {
      final deep = _FakeTiles(maxZoom: 16);
      await _source(await _service({'a': deep})).roadsAround(_lat, _lon);
      expect(deep.requested.every((t) => t.z == 15), isTrue);

      final shallow = _FakeTiles(maxZoom: 14);
      final c = await _source(await _service({'a': shallow}))
          .roadsAround(_lat, _lon);
      expect(shallow.requested.every((t) => t.z == 14), isTrue);
      // The safe box is measured in that zoom's tiles.
      expect(c!.safeEast - c.safeWest, closeTo(3 * 360 / (1 << 14), 1e-9));
    });

    test('falls back to the next pack when the best one has nothing readable',
        () async {
      final broken = _FakeTiles(maxZoom: 15, fails: (_) => true);
      final backup = _FakeTiles(maxZoom: 14);
      final coverage = await _source(await _service({
        'broken': broken,
        'backup': backup,
      })).roadsAround(_lat, _lon);
      expect(coverage!.graph.region, 'backup');
    });

    test('a pack swapped for a new file is not answered from the old tiles',
        () async {
      final tiles = _FakeTiles();
      final found = <String, PackLocation>{
        'a.pmtiles': fakeLocation(1000),
      };
      final service = OfflineMapService(
        locator: FakeMapPackLocator(found),
        opener: (l, p) async => tiles,
        catalog: [_pack('a')],
      );
      await service.load();
      final source = _source(service);
      await source.roadsAround(_lat, _lon);
      expect(tiles.requested, hasLength(25));

      found['a.pmtiles'] = fakeLocation(2222); // re-downloaded, different size
      await service.load();
      await source.roadsAround(_lat, _lon);
      expect(tiles.requested, hasLength(50));
    });

    test('a corner of the world does not read tiles that do not exist',
        () async {
      final tiles = _FakeTiles();
      final catalog = [
        const OfflinePack(
          id: 'world',
          name: 'world',
          south: -90,
          west: -180,
          north: 90,
          east: 180,
          maxZoom: 15,
          approxBytes: 1,
        ),
      ];
      final source =
          _source(await _service({'world': tiles}, catalog: catalog));
      await source.roadsAround(0, -179.9999);
      expect(tiles.requested.every((t) => t.x >= 0 && t.y >= 0), isTrue);
      expect(tiles.requested, hasLength(15)); // two columns fall off the world
    });
  });

  group('PackRoadGraphSource.linesInBox', () {
    // A 2x2 block of z14 tiles around the Delhi point.
    final _x0 = _cx >> 1, _y0 = _cy >> 1;
    // Bounds strictly inside tile x0/y0 and tile (x0+1)/(y0+1): a point
    // exactly on a tile edge can float-round into the next tile, so a box
    // built from tile *centres* is the only reliable way to ask for exactly
    // a 2x2 block.
    final _boxWest = _lonAt(14, _x0 + 0.5), _boxEast = _lonAt(14, _x0 + 1.5);
    final _boxNorth = _latAt(14, _y0 + 0.5), _boxSouth = _latAt(14, _y0 + 1.5);

    test('reads the box at zoom min(pack maxZoom, 14)', () async {
      final tiles = _FakeTiles();
      final source = _source(await _service({'a': tiles}));

      final result = await source.linesInBox(
        south: _boxSouth,
        west: _boxWest,
        north: _boxNorth,
        east: _boxEast,
      );

      expect(result, isNotNull);
      expect(result!.packId, 'a');
      expect(
        tiles.requested.toSet(),
        {
          for (var dx = 0; dx < 2; dx++)
            for (var dy = 0; dy < 2; dy++) TileIdentity(14, _x0 + dx, _y0 + dy),
        },
      );
      expect(result.lines, hasLength(4)); // one road per tile
    });

    test('drops to zoom 13 when the box needs more than maxTiles', () async {
      final tiles = _FakeTiles();
      final source = _source(await _service({'a': tiles}));

      final result = await source.linesInBox(
        south: _boxSouth,
        west: _boxWest,
        north: _boxNorth,
        east: _boxEast,
        maxTiles: 2, // the z14 box needs 4
      );

      expect(result, isNotNull);
      expect(tiles.requested, isNotEmpty);
      expect(tiles.requested.every((t) => t.z == 13), isTrue);
    });

    test('no pack covering the whole box gives no answer', () async {
      final tiles = _FakeTiles();
      final source = _source(await _service({'a': tiles}));

      // Bengaluru: outside `_pack('a')`'s box (28.38-28.90, 76.83-77.45).
      final result = await source.linesInBox(
        south: 12.90,
        west: 77.50,
        north: 13.00,
        east: 77.60,
      );

      expect(result, isNull);
      expect(tiles.requested, isEmpty);
    });

    test('does not touch the small roadsAround tile cache', () async {
      final tiles = _FakeTiles();
      final source = _source(await _service({'a': tiles}), radius: 1, cache: 9);
      await source.roadsAround(_lat, _lon);
      expect(tiles.requested, hasLength(9));

      final result = await source.linesInBox(
        south: _boxSouth,
        west: _boxWest,
        north: _boxNorth,
        east: _boxEast,
      );
      expect(result, isNotNull);

      // The point's 9 tiles are still cached: nothing new is read for them.
      await source.roadsAround(_lat, _lon);
      expect(tiles.requested, hasLength(9 + 4));
    });

    test('a pack that stops below zoom 13 is ignored', () async {
      final low = _FakeTiles(maxZoom: 12);
      final source = _source(await _service({'low': low}));

      final result = await source.linesInBox(
        south: _boxSouth,
        west: _boxWest,
        north: _boxNorth,
        east: _boxEast,
      );

      expect(result, isNull);
      expect(low.requested, isEmpty);
    });
  });

  // ---------------------------------------------------------------- real pack
  group('the real Delhi archive', () {
    final file = File('assets/maps/packs/delhi-ncr.pmtiles');
    final present = file.existsSync();

    test('answers with a road graph, and one tile east reads only new tiles',
        () async {
      // ignore: invalid_use_of_visible_for_testing_member
      final archive = await PmTilesArchive.fromReadAt(OffsetFileAt(file));
      final counting = _Counting(PmTilesVectorTileProvider.fromArchive(archive));
      final service = await _service({'delhi-ncr': counting},
          catalog: [OfflineCatalog.delhiNcr]);
      // The default decoder: tiles are decoded in background isolates.
      final source = PackRoadGraphSource(service);

      final sw = Stopwatch()..start();
      final first = await source.roadsAround(_lat, _lon);
      sw.stop();
      expect(first, isNotNull);
      final g = first!.graph;
      // ignore: avoid_print
      print('real 5x5 block: ${g.edgeCount} edges, ${g.nodeCount} nodes, '
          '${counting.count} tiles read, ${sw.elapsedMilliseconds} ms '
          '(isolates included)');
      expect(counting.count, 25);
      expect(g.edgeCount, greaterThan(500));
      expect(g.nearby(_lat, _lon, radiusM: 150), isNotEmpty);
      expect(first.containsSafe(_lat, _lon), isTrue);
      expect(g.region, 'delhi-ncr');

      sw
        ..reset()
        ..start();
      final next = await source.roadsAround(_lat, _lonAt(15, _cx + 1.5));
      // ignore: avoid_print
      print('one tile east: ${counting.count - 25} new tiles, '
          '${sw.elapsedMilliseconds} ms');
      expect(next, isNotNull);
      expect(counting.count, 30, reason: 'only the new column is read');
      expect(next!.graph.nearby(_lat, _lonAt(15, _cx + 1.5), radiusM: 150),
          isNotEmpty);
    }, skip: present ? false : 'delhi-ncr.pmtiles not on this machine');
  });
}

class _ThrowingTiles extends _FakeTiles {
  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    if (tile == TileIdentity(15, _cx, _cy + 1)) {
      requested.add(tile);
      throw const FileSystemException('disk went away');
    }
    return super.provide(tile);
  }
}

class _JunkTiles extends _FakeTiles {
  _JunkTiles({required this.junkAt});

  final TileIdentity junkAt;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    if (tile == junkAt) {
      requested.add(tile);
      return Uint8List.fromList(List.generate(200, (i) => (i * 31) % 253));
    }
    return super.provide(tile);
  }
}

class _EmptyTiles extends _FakeTiles {
  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    requested.add(tile);
    return Uint8List(0);
  }
}

class _Counting extends VectorTileProvider {
  _Counting(this.inner);

  final VectorTileProvider inner;
  int count = 0;

  @override
  int get maximumZoom => inner.maximumZoom;

  @override
  int get minimumZoom => inner.minimumZoom;

  @override
  Future<Uint8List> provide(TileIdentity tile) {
    count++;
    return inner.provide(tile);
  }
}
