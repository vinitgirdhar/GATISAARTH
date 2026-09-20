import 'dart:math' as math;

import 'package:flutter/foundation.dart';

// Turns loose road lines into pieces that meet only at real junctions.
//
// A line out of a map tile is one road *way*: it runs straight through every
// junction along it, and where a road ends on another the second road has
// often lost its vertex there (tile simplification drops collinear points).
// Followed as they are, such lines never connect. Cutting them where roads
// meet is what lets a vehicle turn corners on the resulting network.

/// Metres in one degree of latitude; good to 0.5 % everywhere, which is all
/// the length and snap tests need.
const double metresPerDegree = 111320;

/// Vertices this close are one place. A junction appears in each tile that
/// touches it, rounded to that tile's own grid (0.27 m per unit at zoom 15),
/// and a tile edge cuts a road in two points a few tenths of a metre apart.
const double roadSnapM = 1.5;

/// Crossings sharper than this (sine of the angle, about 17 degrees) are one
/// road running beside another, not a junction.
const double _minCrossingSine = 0.3;

/// Grid cell size for finding the road a road ends on or crosses (m).
const double _cellM = 25;

/// Segments per line the packed (line, segment) key allows.
const int _segmentsPerLine = 1 << 20;

/// One stretch of road between two junctions or road ends.
@immutable
class RoadPiece {
  const RoadPiece({
    required this.line,
    required this.from,
    required this.to,
    required this.latLon,
  });

  /// Index of the line it was cut from.
  final int line;

  /// Ids of the places at its ends, in the line's direction of travel.
  final int from, to;

  /// Flat `[lat, lon, ...]`; the first and last points sit exactly on the
  /// places, so every piece that meets there agrees where it is.
  final List<double> latLon;
}

/// Pieces and the places they meet at.
@immutable
class NodedRoads {
  const NodedRoads({
    required this.pieces,
    required this.placeLat,
    required this.placeLon,
  });

  final List<RoadPiece> pieces;

  /// Where each place is, by id.
  final List<double> placeLat, placeLon;
}

/// Cuts [lines] (flat lat/lon each) at every junction.
///
/// * every vertex gets the id of the place it is at (vertices within
///   [roadSnapM] are one place);
/// * a road that ends on another road's bare segment, or two at-grade roads
///   that cross with no vertex on either, get a vertex put in at that point;
/// * a place is a junction where a line ends or where two lines both pass;
/// * each line is cut at its junctions.
///
/// Exact duplicates go: the same line twice, or the same stretch two
/// neighbouring tiles both carry in their buffers, which the shared junction
/// vertices cut into identical pieces. A line in [elevated] (a bridge or a
/// tunnel) is joined only where it ends or shares a vertex, never where it
/// merely crosses over or under another road. [oneWay] says which lines are
/// directed, so a road and its reverse are the same road only when it is not.
NodedRoads nodeRoads(
  List<List<double>> lines, {
  required List<bool> oneWay,
  required Set<int> elevated,
}) {
  final places = _Places(_meanLat(lines));
  final firstIds = [for (final l in lines) places.idsOf(l)];
  final keep = _distinctLines(firstIds, oneWay);
  final (latLon, ids) = _joinRoads(keep, lines, firstIds, places, elevated);

  final junctions = _junctions(keep, ids);
  final pieces = <RoadPiece>[];
  final seen = <String>{};
  for (final i in keep) {
    for (final (a, b) in _cuts(ids[i], junctions)) {
      final sequence = _collapsed(ids[i].sublist(a, b + 1));
      if (sequence.length < 2) continue; // a piece that never leaves its place
      if (!seen.add(_sequenceKey(sequence, oneWay[i]))) continue;
      pieces.add(RoadPiece(
        line: i,
        from: ids[i][a],
        to: ids[i][b],
        latLon: _pieceLine(latLon[i], ids[i], a, b, places),
      ));
    }
  }
  return NodedRoads(
    pieces: pieces,
    placeLat: places.lat,
    placeLon: places.lon,
  );
}

double _meanLat(List<List<double>> lines) =>
    lines.fold(0.0, (s, l) => s + l[0]) / lines.length;

/// Numbers the distinct places road vertices can be at.
class _Places {
  _Places(double meanLat)
      : metresPerLon = metresPerDegree * math.cos(meanLat * math.pi / 180);

  final double metresPerLon;

  /// Where each place is: where its first vertex was.
  final List<double> lat = [], lon = [];
  final Map<int, List<int>> _cells = {};

  double x(double longitude) => longitude * metresPerLon;
  double y(double latitude) => latitude * metresPerDegree;

  List<int> idsOf(List<double> latLon) => [
        for (var i = 0; i < latLon.length; i += 2)
          placeAt(latLon[i], latLon[i + 1]),
      ];

  /// The place a point belongs to: an existing one within [roadSnapM], or a
  /// new one.
  int placeAt(double la, double lo) {
    final cx = (x(lo) / roadSnapM).floor(), cy = (y(la) / roadSnapM).floor();
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final id in _cells[_cellKey(cx + dx, cy + dy)] ?? const <int>[]) {
          final ex = x(lo) - x(lon[id]), ey = y(la) - y(lat[id]);
          if (ex * ex + ey * ey <= roadSnapM * roadSnapM) return id;
        }
      }
    }
    final id = lat.length;
    lat.add(la);
    lon.add(lo);
    (_cells[_cellKey(cx, cy)] ??= <int>[]).add(id);
    return id;
  }
}

int _cellKey(int cx, int cy) => cx * 4194304 + cy;

List<int> _collapsed(List<int> ids) => [
      for (var i = 0; i < ids.length; i++)
        if (i == 0 || ids[i] != ids[i - 1]) ids[i],
    ];

/// One-way lines keep their direction in the key; two-way ones read the same
/// backwards.
String _sequenceKey(List<int> ids, bool oneWay) {
  final forward = ids.join(',');
  if (oneWay) return 'o$forward';
  final backward = ids.reversed.join(',');
  return forward.compareTo(backward) <= 0 ? forward : backward;
}

/// Indices of the lines that are not an exact copy of an earlier one.
List<int> _distinctLines(List<List<int>> ids, List<bool> oneWay) {
  final seen = <String>{};
  return [
    for (var i = 0; i < ids.length; i++)
      if (seen.add(_sequenceKey(_collapsed(ids[i]), oneWay[i]))) i,
  ];
}

/// Places where a line ends or where two different lines both pass.
Set<int> _junctions(List<int> keep, List<List<int>> ids) {
  final firstLineAt = <int, int>{};
  final junctions = <int>{};
  for (final i in keep) {
    junctions
      ..add(ids[i].first)
      ..add(ids[i].last);
    for (final place in ids[i]) {
      if (firstLineAt.putIfAbsent(place, () => i) != i) junctions.add(place);
    }
  }
  return junctions;
}

/// Vertex index ranges `(start, end)` of the pieces a line is cut into.
Iterable<(int, int)> _cuts(List<int> ids, Set<int> junctions) sync* {
  var start = 0;
  for (var i = 1; i < ids.length; i++) {
    if (i == ids.length - 1 || junctions.contains(ids[i])) {
      yield (start, i);
      start = i;
    }
  }
}

/// The piece's polyline: its ends sit exactly on their places, and any vertex
/// within snap distance of a neighbour is not a bend worth keeping.
List<double> _pieceLine(
  List<double> latLon,
  List<int> ids,
  int a,
  int b,
  _Places places,
) {
  final out = <double>[places.lat[ids[a]], places.lon[ids[a]]];
  var last = ids[a];
  for (var i = a + 1; i < b; i++) {
    if (ids[i] == last || ids[i] == ids[b]) continue;
    out
      ..add(latLon[i * 2])
      ..add(latLon[i * 2 + 1]);
    last = ids[i];
  }
  out
    ..add(places.lat[ids[b]])
    ..add(places.lon[ids[b]]);
  return out;
}

// ------------------------------------------- roads ending on / crossing roads

/// A point on a segment where another road ends or crosses it.
class _Foot {
  const _Foot(this.t, this.lat, this.lon, this.place);

  /// How far along the segment, 0 to 1 exclusive.
  final double t;
  final double lat, lon;

  /// The place of the other road there.
  final int place;
}

/// Puts a vertex into every segment another road ends on or crosses without
/// one, carrying the other road's place, so the ordinary junction logic then
/// cuts both roads there.
///
/// Returns the lines' coordinates and place ids with those vertices added.
(List<List<double>>, List<List<int>>) _joinRoads(
  List<int> keep,
  List<List<double>> latLon,
  List<List<int>> ids,
  _Places places,
  Set<int> elevated,
) {
  final index = _SegmentIndex(keep, latLon, ids, places);
  final feet = <int, List<_Foot>>{}; // packed (line, segment) -> feet
  void put(int key, _Foot foot) => (feet[key] ??= <_Foot>[]).add(foot);

  // A road passing through a place already has a vertex there.
  final passedThrough = {
    for (final i in keep) ...ids[i].sublist(1, ids[i].length - 1),
  };
  for (final i in keep) {
    for (final end in [0, ids[i].length - 1]) {
      final place = ids[i][end];
      if (passedThrough.contains(place)) continue;
      final hit = index.nearestOther(
        latLon[i][end * 2],
        latLon[i][end * 2 + 1],
        exceptLine: i,
        exceptPlace: place,
      );
      if (hit != null) put(hit.key, _Foot(hit.t, hit.lat, hit.lon, place));
    }
  }
  for (final (key, foot) in index.crossings(elevated)) {
    put(key, foot);
  }
  if (feet.isEmpty) return (latLon, ids);
  return _insertFeet(keep, latLon, ids, feet);
}

/// The lines with each foot added as a vertex in its segment, in order along
/// the segment.
(List<List<double>>, List<List<int>>) _insertFeet(
  List<int> keep,
  List<List<double>> latLon,
  List<List<int>> ids,
  Map<int, List<_Foot>> feet,
) {
  final newLatLon = [...latLon];
  final newIds = [...ids];
  for (final i in keep) {
    final outLatLon = <double>[];
    final outIds = <int>[];
    var changed = false;
    for (var k = 0; k < ids[i].length; k++) {
      outLatLon
        ..add(latLon[i][k * 2])
        ..add(latLon[i][k * 2 + 1]);
      outIds.add(ids[i][k]);
      final here = feet[i * _segmentsPerLine + k];
      if (here == null) continue;
      changed = true;
      final added = <int>{};
      for (final f in [...here]..sort((a, b) => a.t.compareTo(b.t))) {
        if (!added.add(f.place)) continue; // two roads meeting in one place
        outLatLon
          ..add(f.lat)
          ..add(f.lon);
        outIds.add(f.place);
      }
    }
    if (!changed) continue;
    newLatLon[i] = outLatLon;
    newIds[i] = outIds;
  }
  return (newLatLon, newIds);
}

typedef _Nearest = ({int key, double t, double lat, double lon});
typedef _Crossing = ({double t, double u, double lat, double lon});

/// The segments of every kept line, by grid cell. Segments are numbered
/// densely and their ends kept in flat arrays: the pair tests below run
/// millions of times on a dense block.
class _SegmentIndex {
  _SegmentIndex(
    List<int> lines,
    this._latLon,
    List<List<int>> ids,
    this._places,
  ) {
    var total = 0;
    for (final i in lines) {
      total += ids[i].length - 1;
    }
    _line = Int32List(total);
    _seg = Int32List(total);
    _ax = Float64List(total);
    _ay = Float64List(total);
    _bx = Float64List(total);
    _by = Float64List(total);
    _ids = ids;

    var s = 0;
    for (final i in lines) {
      final ll = _latLon[i];
      for (var k = 0; k + 1 < ids[i].length; k++, s++) {
        _line[s] = i;
        _seg[s] = k;
        _ax[s] = _places.x(ll[k * 2 + 1]);
        _ay[s] = _places.y(ll[k * 2]);
        _bx[s] = _places.x(ll[k * 2 + 3]);
        _by[s] = _places.y(ll[k * 2 + 2]);
        _register(s);
      }
    }
  }

  final List<List<double>> _latLon;
  final _Places _places;
  late final List<List<int>> _ids;
  late final Int32List _line, _seg;
  late final Float64List _ax, _ay, _bx, _by;
  final Map<int, List<int>> _cells = {};

  int _key(int s) => _line[s] * _segmentsPerLine + _seg[s];

  int _cell(double x, double y) =>
      _cellKey((x / _cellM).floor(), (y / _cellM).floor());

  /// Files the segment under every cell a sample every half cell along it
  /// falls in; a query looks one cell round its own, so nothing within a few
  /// metres of the segment is missed.
  void _register(int s) {
    final dx = _bx[s] - _ax[s], dy = _by[s] - _ay[s];
    final steps =
        math.max(1, (math.max(dx.abs(), dy.abs()) / (_cellM / 2)).ceil());
    for (var n = 0; n <= steps; n++) {
      final cell = _cell(_ax[s] + dx * n / steps, _ay[s] + dy * n / steps);
      final list = _cells[cell] ??= <int>[];
      if (list.isEmpty || list.last != s) list.add(s);
    }
  }

  /// The closest segment of another line that passes within [roadSnapM] of the
  /// point without being at one of its vertices, or null.
  _Nearest? nearestOther(
    double lat,
    double lon, {
    required int exceptLine,
    required int exceptPlace,
  }) {
    final px = _places.x(lon), py = _places.y(lat);
    final cx = (px / _cellM).floor(), cy = (py / _cellM).floor();
    _Nearest? best;
    var bestM = roadSnapM;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final s in _cells[_cellKey(cx + dx, cy + dy)] ?? const <int>[]) {
          final i = _line[s], k = _seg[s];
          if (i == exceptLine) continue;
          if (_ids[i][k] == exceptPlace || _ids[i][k + 1] == exceptPlace) {
            continue;
          }
          final hit = _foot(s, px, py, bestM);
          if (hit == null) continue;
          best = hit.$1;
          bestM = hit.$2;
        }
      }
    }
    return best;
  }

  /// The point on segment [s] nearest to (px, py) and its distance, when it is
  /// closer than [limitM] and strictly inside the segment.
  (_Nearest, double)? _foot(int s, double px, double py, double limitM) {
    final ex = _bx[s] - _ax[s], ey = _by[s] - _ay[s];
    final len2 = ex * ex + ey * ey;
    if (len2 < 1e-9) return null;
    final t = ((px - _ax[s]) * ex + (py - _ay[s]) * ey) / len2;
    if (t <= 0 || t >= 1) return null; // a vertex: the places already settled it
    final offX = px - (_ax[s] + t * ex), offY = py - (_ay[s] + t * ey);
    final off = math.sqrt(offX * offX + offY * offY);
    if (off > limitM) return null;
    final ll = _latLon[_line[s]], k = _seg[s];
    return (
      (
        key: _key(s),
        t: t,
        lat: ll[k * 2] + t * (ll[k * 2 + 2] - ll[k * 2]),
        lon: ll[k * 2 + 1] + t * (ll[k * 2 + 3] - ll[k * 2 + 1]),
      ),
      off,
    );
  }

  /// A foot on each of the two segments of every at-grade crossing that has no
  /// vertex on either road, keyed by packed (line, segment).
  Iterable<(int, _Foot)> crossings(Set<int> elevated) sync* {
    final done = <(int, int)>{};
    for (final cell in _cells.values) {
      for (var a = 0; a < cell.length; a++) {
        final sa = cell[a];
        if (elevated.contains(_line[sa])) continue;
        for (var b = a + 1; b < cell.length; b++) {
          final sb = cell[b];
          if (_line[sb] == _line[sa] || elevated.contains(_line[sb])) continue;
          final x = _cross(sa, sb);
          if (x == null || !done.add(sa < sb ? (sa, sb) : (sb, sa))) continue;
          final place = _places.placeAt(x.lat, x.lon);
          yield (_key(sa), _Foot(x.t, x.lat, x.lon, place));
          yield (_key(sb), _Foot(x.u, x.lat, x.lon, place));
        }
      }
    }
  }

  /// Where segments [a] and [b] cross, when it is a proper junction: not
  /// nearly parallel, and further than snap distance from all four ends
  /// (nearer than that the places and the end-on-road step already decide).
  _Crossing? _cross(int a, int b) {
    final ex = _bx[a] - _ax[a], ey = _by[a] - _ay[a];
    final fx = _bx[b] - _ax[b], fy = _by[b] - _ay[b];
    final lenA = math.sqrt(ex * ex + ey * ey);
    final lenB = math.sqrt(fx * fx + fy * fy);
    final d = ex * fy - ey * fx;
    if (lenA * lenB < 1e-9 || d.abs() < _minCrossingSine * lenA * lenB) {
      return null;
    }
    final gx = _ax[b] - _ax[a], gy = _ay[b] - _ay[a];
    final t = (gx * fy - gy * fx) / d;
    final u = (gx * ey - gy * ex) / d;
    if (t * lenA < roadSnapM || (1 - t) * lenA < roadSnapM) return null;
    if (u * lenB < roadSnapM || (1 - u) * lenB < roadSnapM) return null;
    final ll = _latLon[_line[a]], k = _seg[a];
    return (
      t: t,
      u: u,
      lat: ll[k * 2] + t * (ll[k * 2 + 2] - ll[k * 2]),
      lon: ll[k * 2 + 1] + t * (ll[k * 2 + 3] - ll[k * 2 + 1]),
    );
  }
}
