import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:pool/pool.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../nav/map/road_graph.dart';
import '../../nav/map/tile_roads.dart';
import 'offline_map_service.dart';

/// Where the navigation core gets a road network from.
abstract class RoadGraphSource {
  /// Roads around a point, or null when no installed map has roads there or
  /// reading them failed. Never throws.
  Future<RoadCoverage?> roadsAround(double lat, double lon);
}

/// A road graph and the part of it that can be trusted to be complete.
@immutable
class RoadCoverage {
  const RoadCoverage({
    required this.graph,
    required this.safeSouth,
    required this.safeWest,
    required this.safeNorth,
    required this.safeEast,
  });

  final RoadGraph graph;

  /// Degrees. The graph is complete out to well beyond this box; the caller
  /// asks again once the vehicle leaves it.
  final double safeSouth, safeWest, safeNorth, safeEast;

  bool containsSafe(double lat, double lon) =>
      lat >= safeSouth && lat <= safeNorth && lon >= safeWest && lon <= safeEast;
}

/// Decodes one tile's roads; replaceable so tests need no isolates.
typedef TileRoadDecoder = Future<List<TileRoadLine>> Function(
  Uint8List bytes,
  int z,
  int x,
  int y,
);

/// How long to wait for the archives to be opened before giving up on them.
const Duration _packsOpenTimeout = Duration(seconds: 15);

/// Below this zoom a pack has left the minor streets out.
const int _minPackZoom = 13;

/// Tiles are read at the pack's own zoom but no deeper than this: past 15 the
/// vector data is the same, drawn bigger.
const int _maxTileZoom = 15;

/// Preferred zoom for a corridor read ([linesInBox]): a box can span many
/// tiles, so it defaults one zoom lower than a point read's [_maxTileZoom].
const int _corridorZoom = 14;

/// At most this many tiles decode in background isolates at once; a fresh
/// block of 25 must not start 25 isolates.
const int _decodeConcurrency = 3;

/// Builds the road network from the map archives already on the phone.
///
/// The roads are the ones the map draws, so a vehicle held to them follows
/// what is on screen, at any place an installed pack covers. A block of
/// `(2 * tileRadius + 1)^2` tiles around the point is read, decoded (off the
/// UI thread) and joined into one graph; decoded tiles are kept in a small LRU
/// so moving one tile costs one new row or column, not a whole block.
class PackRoadGraphSource implements RoadGraphSource {
  PackRoadGraphSource(
    this.maps, {
    this.tileRadius = 2,
    this.maxCachedTiles = 64,
    TileRoadDecoder? decoder,
    bool? useIsolates,
  })  : assert(tileRadius >= 1),
        _decoder = decoder ?? _decodeInIsolate,
        _useIsolates = useIsolates ?? decoder == null;

  final OfflineMapService maps;

  /// Tiles read each way from the centre tile.
  final int tileRadius;
  final int maxCachedTiles;

  final TileRoadDecoder _decoder;

  /// Whether the graph is built in a background isolate too. Off when a test
  /// injects its own decoder.
  final bool _useIsolates;

  final Pool _decodePool = Pool(_decodeConcurrency);

  /// Least recently used first. Failures are kept as null, so a hole in a pack
  /// is read (and logged) once, not on every call.
  final Map<String, Future<List<TileRoadLine>?>> _tiles = {};

  /// Forgets every decoded tile.
  void clearCache() => _tiles.clear();

  @override
  Future<RoadCoverage?> roadsAround(double lat, double lon) async {
    await _untilPacksOpen();
    try {
      for (final pack in _packsAt(lat, lon)) {
        final coverage = await _coverageFrom(pack, lat, lon);
        if (coverage != null) return coverage;
      }
    } catch (e) {
      debugPrint('[RoadGraph] roads around $lat, $lon unavailable: $e');
    }
    return null;
  }

  /// All drivable lines inside a lat/lon box, from the best installed pack
  /// (maxZoom >= 13) whose own bounding box contains the whole thing - most
  /// detailed first. Used for a journey corridor, not for the live position:
  /// reads go straight through the decode pool and never touch [_tiles], so a
  /// one-off route read (which can ask for far more tiles than the live LRU
  /// holds) never evicts the tiles [roadsAround] is using this second.
  ///
  /// Reads at `min(pack maxZoom, 14)`, dropping to 13 (still >= 13, so a pack
  /// with no lower zoom is skipped) when that would need more than [maxTiles]
  /// tiles. Null when no installed pack covers the box, or nothing in it could
  /// be read.
  Future<({List<TileRoadLine> lines, String packId})?> linesInBox({
    required double south,
    required double west,
    required double north,
    required double east,
    int maxTiles = 250,
  }) async {
    await _untilPacksOpen();
    try {
      for (final pack in _packsCoveringBox(south, west, north, east)) {
        final lines =
            await _linesInBoxFrom(pack, south, west, north, east, maxTiles);
        if (lines != null) return (lines: lines, packId: pack.pack.id);
      }
    } catch (e) {
      debugPrint('[RoadGraph] lines in $south,$west,$north,$east unavailable: $e');
    }
    return null;
  }

  /// Installed packs whose own box contains the whole [south]/[west]/[north]/
  /// [east] box and hold minor streets, most detailed first.
  List<InstalledPack> _packsCoveringBox(
    double south,
    double west,
    double north,
    double east,
  ) {
    final sw = LatLng(south, west);
    final ne = LatLng(north, east);
    final packs = [
      for (final p in maps.installed)
        if (p.pack.contains(sw) &&
            p.pack.contains(ne) &&
            p.provider.maximumZoom >= _minPackZoom)
          p,
    ];
    packs.sort((a, b) {
      final byZoom = b.provider.maximumZoom.compareTo(a.provider.maximumZoom);
      return byZoom != 0 ? byZoom : a.pack.id.compareTo(b.pack.id);
    });
    return packs;
  }

  Future<List<TileRoadLine>?> _linesInBoxFrom(
    InstalledPack pack,
    double south,
    double west,
    double north,
    double east,
    int maxTiles,
  ) async {
    var z = math.min(_corridorZoom, pack.provider.maximumZoom);
    var tiles = _tilesInBox(south, west, north, east, z);
    if (tiles.length > maxTiles && z > _minPackZoom) {
      z = _minPackZoom;
      tiles = _tilesInBox(south, west, north, east, z);
    }
    final block = await Future.wait([
      for (final t in tiles) _readTile(pack, z, t.x, t.y),
    ]);
    if (block.every((lines) => lines == null)) return null;
    return [for (final l in block) ...?l];
  }

  /// Tile coordinates at zoom [z] covering the box, clamped to the world.
  List<({int x, int y})> _tilesInBox(
    double south,
    double west,
    double north,
    double east,
    int z,
  ) {
    final limit = 1 << z;
    final nw = tileOf(north, west, z);
    final se = tileOf(south, east, z);
    return [
      for (var y = nw.y; y <= se.y; y++)
        for (var x = nw.x; x <= se.x; x++)
          if (x >= 0 && x < limit && y >= 0 && y < limit) (x: x, y: y),
    ];
  }

  /// The app asks for roads a moment after it starts, before the archives are
  /// open; "no packs yet" must not be read as "no roads here".
  Future<void> _untilPacksOpen() async {
    if (maps.isLoaded) return;
    final opened = Completer<void>();
    void check() {
      if (maps.isLoaded && !opened.isCompleted) opened.complete();
    }

    maps.addListener(check);
    try {
      await opened.future.timeout(_packsOpenTimeout);
    } on TimeoutException {
      debugPrint('[RoadGraph] map packs not open after $_packsOpenTimeout');
    } finally {
      maps.removeListener(check);
    }
  }

  /// Installed packs over the point that hold minor streets, most detailed
  /// first.
  List<InstalledPack> _packsAt(double lat, double lon) {
    final here = LatLng(lat, lon);
    final packs = [
      for (final p in maps.installed)
        if (p.pack.contains(here) && p.provider.maximumZoom >= _minPackZoom) p,
    ];
    packs.sort((a, b) {
      final byZoom = b.provider.maximumZoom.compareTo(a.provider.maximumZoom);
      return byZoom != 0 ? byZoom : a.pack.id.compareTo(b.pack.id);
    });
    return packs;
  }

  Future<RoadCoverage?> _coverageFrom(
    InstalledPack pack,
    double lat,
    double lon,
  ) async {
    final z = math.min(_maxTileZoom, pack.provider.maximumZoom);
    final centre = tileOf(lat, lon, z);
    final limit = 1 << z;
    final block = await Future.wait([
      for (var dy = -tileRadius; dy <= tileRadius; dy++)
        for (var dx = -tileRadius; dx <= tileRadius; dx++)
          if (centre.x + dx >= 0 &&
              centre.x + dx < limit &&
              centre.y + dy >= 0 &&
              centre.y + dy < limit)
            _tileLines(pack, z, centre.x + dx, centre.y + dy),
    ]);
    // A tile with no roads is normal; only a block nothing could be read
    // from is a failure.
    if (block.every((lines) => lines == null)) return null;

    final lines = [for (final l in block) ...?l];
    final graph = await _build(lines, pack.pack.id);
    if (graph == null) return null;

    final margin = tileRadius - 1;
    final northWest = tileCorner(z, centre.x - margin, centre.y - margin);
    final southEast =
        tileCorner(z, centre.x + margin + 1, centre.y + margin + 1);
    return RoadCoverage(
      graph: graph,
      safeNorth: northWest.lat,
      safeWest: northWest.lon,
      safeSouth: southEast.lat,
      safeEast: southEast.lon,
    );
  }

  /// One tile's lines, from the cache when it is there. Keyed by the file's
  /// size too, so a pack replaced by a newer download is not read from old
  /// tiles.
  Future<List<TileRoadLine>?> _tileLines(
    InstalledPack pack,
    int z,
    int x,
    int y,
  ) {
    final key = '${pack.pack.id}:${pack.bytes}:$z:$x:$y';
    final cached = _tiles.remove(key);
    final future = cached ?? _readTile(pack, z, x, y);
    _tiles[key] = future; // most recently used goes last
    while (_tiles.length > maxCachedTiles) {
      _tiles.remove(_tiles.keys.first);
    }
    return future;
  }

  Future<List<TileRoadLine>?> _readTile(
    InstalledPack pack,
    int z,
    int x,
    int y,
  ) async {
    final where = '${pack.pack.id} $z/$x/$y';
    try {
      final bytes = await pack.provider.provide(TileIdentity(z, x, y));
      return await _decodePool.withResource(() => _decoder(bytes, z, x, y));
    } on ProviderException catch (e) {
      debugPrint('[RoadGraph] $where is not in the pack: ${e.message}');
    } catch (e) {
      debugPrint('[RoadGraph] $where skipped: $e');
    }
    return null;
  }

  Future<RoadGraph?> _build(List<TileRoadLine> lines, String region) async {
    if (!_useIsolates) return buildRoadGraph(lines, region: region);
    return compute(_buildInIsolate, (lines: lines, region: region));
  }
}

Future<List<TileRoadLine>> _decodeInIsolate(
  Uint8List bytes,
  int z,
  int x,
  int y,
) =>
    compute(_decodeMessage, (bytes: bytes, z: z, x: x, y: y));

// Cut at the tile edge: neighbouring tiles then meet in one shared point
// instead of overlapping through their buffers, so a road across the border is
// one chain in the merged graph.
List<TileRoadLine> _decodeMessage(
        ({Uint8List bytes, int z, int x, int y}) m) =>
    decodeRoadTile(m.bytes, m.z, m.x, m.y, clipToTile: true);

RoadGraph? _buildInIsolate(({List<TileRoadLine> lines, String region}) m) =>
    buildRoadGraph(m.lines, region: m.region);
