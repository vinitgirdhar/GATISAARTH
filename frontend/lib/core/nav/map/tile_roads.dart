import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_tile/vector_tile.dart';

import 'road_graph.dart';
import 'road_noding.dart';

// Roads out of the map's own vector tiles (Protomaps schema v4, `roads` layer).
//
// The road network is read from the same archives that draw the map, so a
// vehicle constrained to it follows exactly the roads on screen, at any place
// an offline pack covers, with no separate graph file to ship.

/// A road shorter than this says nothing about where the vehicle can be.
const double _minLineM = 1.0;

/// `access` values that keep a car off a road. Everything else (permissive,
/// customers, destination...) is a road somebody drives on.
const Set<String> _refusedAccess = {'no', 'private', 'military'};

/// What Protomaps calls a road class when `kind_detail` says nothing clearer.
const Map<String, RoadClass> _classOfKind = {
  'highway': RoadClass.motorway,
  'major_road': RoadClass.primary,
  'medium_road': RoadClass.secondary,
  'minor_road': RoadClass.unclassified,
};

/// `kind_detail` is the OpenStreetMap `highway` value, `_link` stripped.
const Map<String, RoadClass> _classOfDetail = {
  'motorway': RoadClass.motorway,
  'trunk': RoadClass.trunk,
  'primary': RoadClass.primary,
  'secondary': RoadClass.secondary,
  'tertiary': RoadClass.tertiary,
  'residential': RoadClass.residential,
  'living_street': RoadClass.residential,
  'service': RoadClass.service,
  'driveway': RoadClass.service,
  'alley': RoadClass.service,
  'parking_aisle': RoadClass.service,
  'emergency_access': RoadClass.service,
};

/// One drivable line out of a map tile, already in lat/lon.
@immutable
class TileRoadLine {
  const TileRoadLine({
    required this.latLon,
    this.roadClass = RoadClass.unclassified,
    this.oneWay = false,
    this.bridge = false,
    this.tunnel = false,
    this.name,
  });

  /// Flat `[lat0, lon0, lat1, lon1, ...]`, at least two points, in travel order
  /// when [oneWay].
  final List<double> latLon;
  final RoadClass roadClass;
  final bool oneWay;
  final bool bridge;
  final bool tunnel;
  final String? name;
}

/// The slippy-map tile at zoom [z] that holds a point (clamped to the world).
({int x, int y}) tileOf(double lat, double lon, int z) {
  final n = 1 << z;
  final latRad = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
  final fx = (lon + 180) / 360 * n;
  final fy =
      (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n;
  return (
    x: fx.floor().clamp(0, n - 1),
    y: fy.floor().clamp(0, n - 1),
  );
}

/// North-west corner of tile [x], [y] at zoom [z]. Fractional tile numbers work
/// too, which is how a box a whole number of tiles wide is measured.
({double lat, double lon}) tileCorner(int z, num x, num y) {
  final n = (1 << z).toDouble();
  final mercator = math.pi * (1 - 2 * y / n);
  return (
    lat: (2 * math.atan(math.exp(mercator)) - math.pi / 2) * 180 / math.pi,
    lon: x / n * 360 - 180,
  );
}

// ------------------------------------------------------------------- decode

/// Drivable lines of one tile's `roads` layer, in lat/lon.
///
/// A tile carries a ~64 unit buffer past its edge, so by default lines run out
/// of the tile and the neighbour holds an overlapping copy. With [clipToTile]
/// they are cut exactly at the tile edge instead: neighbouring tiles then meet
/// at a border rather than overlap, which is what joins a road into one chain
/// when the tiles are merged.
///
/// Never throws: a tile that cannot be read gives an empty list, and a damaged
/// feature costs only itself.
List<TileRoadLine> decodeRoadTile(
  Uint8List bytes,
  int z,
  int x,
  int y, {
  bool clipToTile = false,
}) {
  try {
    final layer = _roadsLayer(VectorTile.fromBytes(bytes: bytes));
    if (layer == null) return const [];
    final frame = _TileFrame(z, x, y, layer.extent);
    final out = <TileRoadLine>[];
    var damaged = 0;
    Object? firstError;
    for (final feature in layer.features) {
      try {
        out.addAll(_featureLines(feature, frame, clipToTile));
      } catch (e) {
        damaged++;
        firstError ??= e;
      }
    }
    if (damaged > 0) {
      debugPrint('[TileRoads] $z/$x/$y: $damaged damaged road feature(s) '
          'skipped, first: $firstError');
    }
    return out;
  } catch (e) {
    debugPrint('[TileRoads] $z/$x/$y unreadable: $e');
    return const [];
  }
}

VectorTileLayer? _roadsLayer(VectorTile tile) {
  for (final layer in tile.layers) {
    if (layer.name == 'roads') return layer;
  }
  return null;
}

/// Tile units to lat/lon. Built from whole-world integer positions so the same
/// vertex in two neighbouring tiles converts to the very same coordinates.
class _TileFrame {
  _TileFrame(int z, int x, int y, this.extent)
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

enum _Travel { both, forward, reverse }

_Travel _travelOf(String? oneway) => switch (oneway) {
      'yes' || 'true' || '1' => _Travel.forward,
      '-1' || 'reverse' => _Travel.reverse,
      _ => _Travel.both, // no, reversible, alternating, absent
    };

/// The road class of a feature, or null when a car cannot use it.
RoadClass? _classOf(String? kind, String? detail) {
  if (kind == 'other') {
    return detail == 'living_street' ? RoadClass.residential : null;
  }
  final byKind = _classOfKind[kind];
  if (byKind == null) return null; // path, rail, ferry, aeroway, ...
  final base = detail != null && detail.endsWith('_link')
      ? detail.substring(0, detail.length - 5)
      : detail;
  return _classOfDetail[base] ?? byKind;
}

Iterable<TileRoadLine> _featureLines(
  VectorTileFeature feature,
  _TileFrame frame,
  bool clip,
) sync* {
  if (feature.type != VectorTileGeomType.LINESTRING) return;
  final props = feature.decodeProperties();
  final roadClass =
      _classOf(props['kind']?.stringValue, props['kind_detail']?.stringValue);
  if (roadClass == null) return;
  if (_refusedAccess.contains(props['access']?.stringValue)) return;

  final travel = _travelOf(props['oneway']?.stringValue);
  for (final part in feature.decodeLineString()) {
    final pieces = clip ? _clipToSquare(part, frame.extent) : [_flat(part)];
    for (final piece in pieces) {
      final latLon = _toLatLon(piece, frame, reverse: travel == _Travel.reverse);
      if (latLon == null) continue;
      yield TileRoadLine(
        latLon: latLon,
        roadClass: roadClass,
        oneWay: travel != _Travel.both,
        bridge: props['is_bridge']?.boolValue ?? false,
        tunnel: props['is_tunnel']?.boolValue ?? false,
        name: props['name']?.stringValue,
      );
    }
  }
}

List<double> _flat(List<List<int>> points) =>
    [for (final p in points) ...[p[0].toDouble(), p[1].toDouble()]];

/// Flat tile-unit `x, y` pairs to flat lat/lon, or null when the line is a
/// point or shorter than [_minLineM].
List<double>? _toLatLon(
  List<double> px,
  _TileFrame frame, {
  required bool reverse,
}) {
  final out = <double>[];
  for (var i = 0; i < px.length; i += 2) {
    // Two vertices on one tile unit are one vertex.
    if (i > 0 && px[i] == px[i - 2] && px[i + 1] == px[i - 1]) continue;
    out
      ..add(frame.latOf(px[i + 1]))
      ..add(frame.lonOf(px[i]));
  }
  if (out.length < 4 || _lengthM(out) < _minLineM) return null;
  return reverse ? _reversed(out) : out;
}

List<double> _reversed(List<double> latLon) => [
      for (var i = latLon.length - 2; i >= 0; i -= 2) ...[
        latLon[i],
        latLon[i + 1],
      ],
    ];

double _lengthM(List<double> latLon) {
  final cosLat = math.cos(latLon[0] * math.pi / 180);
  var total = 0.0;
  for (var i = 2; i < latLon.length; i += 2) {
    final dy = (latLon[i] - latLon[i - 2]) * metresPerDegree;
    final dx = (latLon[i + 1] - latLon[i - 1]) * metresPerDegree * cosLat;
    total += math.sqrt(dx * dx + dy * dy);
  }
  return total;
}

/// The parts of a polyline that lie inside the square `[0, extent]`, as flat
/// tile-unit pairs. A line that leaves and comes back is two parts.
List<List<double>> _clipToSquare(List<List<int>> points, int extent) {
  final pieces = <List<double>>[];
  List<double>? open;
  final hi = extent.toDouble();
  for (var i = 0; i + 1 < points.length; i++) {
    final x0 = points[i][0].toDouble(), y0 = points[i][1].toDouble();
    final dx = points[i + 1][0] - x0, dy = points[i + 1][1] - y0;
    final inside = _insideSpan(x0, y0, dx, dy, hi);
    if (inside == null) {
      open = null;
      continue;
    }
    final (t0, t1) = inside;
    if (t0 > 0 || open == null) {
      open = [x0 + t0 * dx, y0 + t0 * dy];
      pieces.add(open);
    }
    open
      ..add(x0 + t1 * dx)
      ..add(y0 + t1 * dy);
    if (t1 < 1) open = null;
  }
  return pieces;
}

/// Liang-Barsky: the span `[t0, t1]` of the segment `(x0, y0) + t * (dx, dy)`
/// that lies inside `[0, hi]` on both axes, or null when none does.
(double, double)? _insideSpan(
  double x0,
  double y0,
  double dx,
  double dy,
  double hi,
) {
  var t0 = 0.0, t1 = 1.0;
  bool narrow(double p, double q) {
    if (p == 0) return q >= 0;
    final r = q / p;
    if (p < 0) {
      if (r > t1) return false;
      if (r > t0) t0 = r;
    } else {
      if (r < t0) return false;
      if (r < t1) t1 = r;
    }
    return true;
  }

  final ok = narrow(-dx, x0) &&
      narrow(dx, hi - x0) &&
      narrow(-dy, y0) &&
      narrow(dy, hi - y0);
  return ok ? (t0, t1) : null;
}

// -------------------------------------------------------------------- graph

/// Turns lines into a routable [RoadGraph], or null when there are none.
///
/// The lines are first cut where roads meet ([nodeRoads]: a road that ends on
/// another, or crosses it at grade, is joined even where the tile left no
/// vertex), so a vehicle can follow a road round a corner; each piece between
/// two junctions is then one edge. Exact duplicates, such as the stretch two
/// neighbouring tiles both carry in their buffers, are one edge.
///
/// Known limit: a bridge or tunnel is joined to the roads it passes over or
/// under only where it ends or shares a vertex with them, which is what a
/// grade-separated crossing should do.
RoadGraph? buildRoadGraph(Iterable<TileRoadLine> lines, {String region = ''}) {
  final usable = [
    for (final l in lines)
      if (l.latLon.length >= 4 &&
          l.latLon.length.isEven &&
          l.latLon.every((v) => v.isFinite))
        l,
  ];
  if (usable.isEmpty) return null;

  final noded = nodeRoads(
    [for (final l in usable) l.latLon],
    oneWay: [for (final l in usable) l.oneWay],
    elevated: {
      for (var i = 0; i < usable.length; i++)
        if (usable[i].bridge || usable[i].tunnel) i,
    },
  );
  if (noded.pieces.isEmpty) return null;

  final edges = [
    for (final (n, piece) in noded.pieces.indexed)
      RoadEdge(
        id: n + 1,
        fromNode: piece.from,
        toNode: piece.to,
        polyline: piece.latLon,
        roadClass: usable[piece.line].roadClass,
        oneWay: usable[piece.line].oneWay,
        tunnel: usable[piece.line].tunnel,
        bridge: usable[piece.line].bridge,
        name: usable[piece.line].name,
      ),
  ];
  final used = {for (final e in edges) ...[e.fromNode, e.toNode]};
  return RoadGraph(
    nodes: [
      for (final id in used)
        RoadNode(
          id: id,
          lat: noded.placeLat[id],
          lon: noded.placeLon[id],
        ),
    ],
    edges: edges,
    region: region,
  );
}
