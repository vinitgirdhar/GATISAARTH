import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:vector_map_tiles/vector_map_tiles.dart' show TileIdentity;
import 'package:vector_tile/vector_tile.dart';

import '../../nav/map/tile_roads.dart' show tileOf;
import '../../nav/math/nav_math.dart' show NavMath;
import 'offline_map_service.dart';

/// One search hit.
@immutable
class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.kind,
    required this.lat,
    required this.lon,
    this.distanceM,
  });

  final String name;

  /// The map's own `kind` (locality, neighbourhood, hospital, station,
  /// major_road ...), for a subtitle and an icon.
  final String kind;
  final double lat;
  final double lon;

  /// From the point the search was made near, when known.
  final double? distanceM;
}

const double _metresPerDegree = 111320;

/// Zoom and radius the coarse index is built at: covers a city's worth of
/// named places and roads.
const int _wideZoom = 13;
const double _wideRadiusM = 12000;

/// A finer pass added on top for local detail (measured ~620 POIs/tile at
/// z15 around Bandra - too dense to read city-wide).
const int _fineZoom = 15;
const double _fineRadiusM = 1500;

/// Same name within this distance is one place, not two hits.
const double _dedupeRadiusM = 300;

const List<String> _wideLayers = ['places', 'pois', 'roads'];
const List<String> _fineLayers = ['pois'];

/// Offline place search over the installed map packs.
///
/// Names come from the packs' own vector tiles (`places`, `pois`, named
/// `roads` - Protomaps schema v4), so it works with no network. Built lazily
/// around the search origin, decoded off the UI thread ([compute]), and
/// cached per (pack, origin tile) so retyping a query costs no new decode.
class PlaceSearch {
  PlaceSearch(this.maps);

  final OfflineMapService maps;

  /// Keyed by `packId:bytes:z:x:y` of the origin's wide-index tile.
  final Map<String, Future<List<_NamedFeature>>> _cache = {};

  /// Case-insensitive; prefix/word-start matches rank before substring
  /// matches, then nearer before further. Never throws: returns [] on failure.
  Future<List<PlaceResult>> search(
    String query, {
    required double nearLat,
    required double nearLon,
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final pack = _bestPack(nearLat, nearLon);
      if (pack == null) return const [];
      final features = await _indexNear(pack, nearLat, nearLon);

      final hits = <(int tier, double distanceM, _NamedFeature feature)>[];
      for (final f in features) {
        final tier = _matchTier(f.name, q);
        if (tier == null) continue;
        final distanceM = NavMath.horizontalDistance(
          lat0: nearLat,
          lon0: nearLon,
          lat1: f.lat,
          lon1: f.lon,
        );
        hits.add((tier, distanceM, f));
      }
      hits.sort((a, b) {
        final byTier = a.$1.compareTo(b.$1);
        return byTier != 0 ? byTier : a.$2.compareTo(b.$2);
      });
      return [
        for (final hit in hits.take(limit))
          PlaceResult(
            name: hit.$3.name,
            kind: hit.$3.kind,
            lat: hit.$3.lat,
            lon: hit.$3.lon,
            distanceM: hit.$2,
          ),
      ];
    } catch (e) {
      debugPrint('[PlaceSearch] "$query" near $nearLat,$nearLon failed: $e');
      return const [];
    }
  }

  /// 0 = exact, 1 = prefix, 2 = a word inside the name starts with the query,
  /// 3 = the query is a substring somewhere else. Null: no match.
  int? _matchTier(String name, String query) {
    final n = name.toLowerCase();
    final q = query.toLowerCase();
    if (n == q) return 0;
    if (n.startsWith(q)) return 1;
    final words = n.split(RegExp(r'[\s,./-]+'));
    if (words.any((w) => w.startsWith(q))) return 2;
    if (n.contains(q)) return 3;
    return null;
  }

  /// The most detailed installed pack covering the search origin, or null.
  InstalledPack? _bestPack(double lat, double lon) {
    final here = LatLng(lat, lon);
    InstalledPack? best;
    for (final p in maps.installed) {
      if (!p.pack.contains(here)) continue;
      if (best == null || p.provider.maximumZoom > best.provider.maximumZoom) {
        best = p;
      }
    }
    return best;
  }

  Future<List<_NamedFeature>> _indexNear(
    InstalledPack pack,
    double lat,
    double lon,
  ) {
    final z = math.min(_wideZoom, pack.provider.maximumZoom);
    final centre = tileOf(lat, lon, z);
    final key = '${pack.pack.id}:${pack.bytes}:$z:${centre.x}:${centre.y}';
    return _cache.putIfAbsent(key, () => _buildIndex(pack, lat, lon, z));
  }

  Future<List<_NamedFeature>> _buildIndex(
    InstalledPack pack,
    double lat,
    double lon,
    int z,
  ) async {
    final wideTiles = _tilesWithin(lat, lon, z, _wideRadiusM);
    final wide = await Future.wait([
      for (final t in wideTiles) _decodeTile(pack, z, t.x, t.y, _wideLayers),
    ]);
    final features = <_NamedFeature>[for (final l in wide) ...l];

    if (pack.provider.maximumZoom >= _fineZoom) {
      final fineTiles = _tilesWithin(lat, lon, _fineZoom, _fineRadiusM);
      final fine = await Future.wait([
        for (final t in fineTiles)
          _decodeTile(pack, _fineZoom, t.x, t.y, _fineLayers),
      ]);
      for (final l in fine) {
        features.addAll(l);
      }
    }
    return _dedupe(features);
  }

  Future<List<_NamedFeature>> _decodeTile(
    InstalledPack pack,
    int z,
    int x,
    int y,
    List<String> layers,
  ) async {
    try {
      final bytes = await pack.provider.provide(TileIdentity(z, x, y));
      return await compute(
          _decodeNamedTile, (bytes: bytes, z: z, x: x, y: y, layers: layers));
    } catch (e) {
      debugPrint('[PlaceSearch] tile ${pack.pack.id} $z/$x/$y skipped: $e');
      return const [];
    }
  }

  /// Tiles at zoom [z] within [radiusM] of the point, clamped to the world.
  /// ponytail: a plain lat/lon box, not a true circle - a corner tile or two
  /// beyond the radius is harmless (it just adds a few extra candidates).
  List<({int x, int y})> _tilesWithin(
    double lat,
    double lon,
    int z,
    double radiusM,
  ) {
    final latPad = radiusM / _metresPerDegree;
    final lonPad = radiusM /
        (_metresPerDegree * math.cos(lat * math.pi / 180).abs().clamp(0.01, 1.0));
    final nw = tileOf(lat + latPad, lon - lonPad, z);
    final se = tileOf(lat - latPad, lon + lonPad, z);
    final limit = 1 << z;
    return [
      for (var y = nw.y; y <= se.y; y++)
        for (var x = nw.x; x <= se.x; x++)
          if (x >= 0 && x < limit && y >= 0 && y < limit) (x: x, y: y),
    ];
  }

  /// Same name within [_dedupeRadiusM] is one place: keeps the more
  /// important kind (places > named roads > POIs).
  /// ponytail: O(n^2) over the built index (a few hundred to low thousands of
  /// features) - move to a spatial bucket if a pack's index ever gets huge.
  List<_NamedFeature> _dedupe(List<_NamedFeature> features) {
    final kept = <_NamedFeature>[];
    for (final f in features) {
      final i = kept.indexWhere((k) =>
          k.name.toLowerCase() == f.name.toLowerCase() &&
          NavMath.horizontalDistance(
                lat0: k.lat,
                lon0: k.lon,
                lat1: f.lat,
                lon1: f.lon,
              ) <
              _dedupeRadiusM);
      if (i < 0) {
        kept.add(f);
      } else if (f.priority > kept[i].priority) {
        kept[i] = f;
      }
    }
    return kept;
  }
}

@immutable
class _NamedFeature {
  const _NamedFeature({
    required this.name,
    required this.kind,
    required this.lat,
    required this.lon,
    required this.priority,
  });

  final String name;
  final String kind;
  final double lat;
  final double lon;

  /// Higher wins a dedupe collision: places > named roads > POIs.
  final int priority;
}

int _priorityOf(String layer) => switch (layer) {
      'places' => 3,
      'roads' => 2,
      'pois' => 1,
      _ => 0,
    };

/// Tile units to lat/lon, matching `tile_roads.dart`'s own (private) frame.
class _Frame {
  _Frame(int z, int x, int y, this.extent)
      : _x0 = x * extent.toDouble(),
        _y0 = y * extent.toDouble(),
        _world = extent * (1 << z).toDouble();

  final int extent;
  final double _x0, _y0, _world;

  double lonOf(double px) => (_x0 + px) / _world * 360 - 180;

  double latOf(double py) {
    final mercator = math.pi * (1 - 2 * (_y0 + py) / _world);
    return (2 * math.atan(math.exp(mercator)) - math.pi / 2) * 180 / math.pi;
  }
}

/// The point to search-index a feature at: the point itself, or (for a road)
/// the midpoint of its longest part.
({double lat, double lon})? _representativePoint(
  VectorTileFeature feature,
  _Frame frame,
) {
  if (feature.type == VectorTileGeomType.POINT) {
    final points = feature.decodePoint();
    if (points.isEmpty) return null;
    final p = points.first;
    return (lat: frame.latOf(p[1].toDouble()), lon: frame.lonOf(p[0].toDouble()));
  }
  if (feature.type == VectorTileGeomType.LINESTRING) {
    List<int>? longest;
    var longestLen = -1.0;
    for (final part in feature.decodeLineString()) {
      if (part.length < 2) continue;
      var len = 0.0;
      for (var i = 1; i < part.length; i++) {
        final dx = (part[i][0] - part[i - 1][0]).toDouble();
        final dy = (part[i][1] - part[i - 1][1]).toDouble();
        len += math.sqrt(dx * dx + dy * dy);
      }
      if (len > longestLen) {
        longestLen = len;
        longest = part[part.length ~/ 2];
      }
    }
    if (longest == null) return null;
    return (
      lat: frame.latOf(longest[1].toDouble()),
      lon: frame.lonOf(longest[0].toDouble()),
    );
  }
  return null;
}

/// Runs in a background isolate via [compute]: decodes the named features of
/// one tile's `places`/`pois`/`roads` layers. Never throws: a damaged tile or
/// feature costs only itself.
List<_NamedFeature> _decodeNamedTile(
  ({Uint8List bytes, int z, int x, int y, List<String> layers}) req,
) {
  try {
    final tile = VectorTile.fromBytes(bytes: req.bytes);
    final out = <_NamedFeature>[];
    for (final layer in tile.layers) {
      if (!req.layers.contains(layer.name)) continue;
      final frame = _Frame(req.z, req.x, req.y, layer.extent);
      for (final feature in layer.features) {
        try {
          final props = feature.decodeProperties();
          final name = props['name']?.stringValue?.trim();
          if (name == null || name.isEmpty) continue;
          final point = _representativePoint(feature, frame);
          if (point == null) continue;
          out.add(_NamedFeature(
            name: name,
            kind: props['kind']?.stringValue ?? layer.name,
            lat: point.lat,
            lon: point.lon,
            priority: _priorityOf(layer.name),
          ));
        } catch (_) {
          // One damaged feature costs only itself.
        }
      }
    }
    return out;
  } catch (e) {
    debugPrint('[PlaceSearch] ${req.z}/${req.x}/${req.y} unreadable: $e');
    return const [];
  }
}
