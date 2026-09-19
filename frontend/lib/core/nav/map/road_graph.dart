import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';

/// Road classification, coarse enough to be stable across OSM tag churn.
enum RoadClass {
  motorway,
  trunk,
  primary,
  secondary,
  tertiary,
  residential,
  service,
  unclassified,
}

/// Which vehicles may use an edge (§20 vehicle restrictions).
enum VehicleAccess { cars, twoWheelers }

/// One node of the road graph.
@immutable
class RoadNode {
  const RoadNode({required this.id, required this.lat, required this.lon});

  final int id;
  final double lat;
  final double lon;
}

/// One directed-or-bidirectional road segment.
@immutable
class RoadEdge {
  RoadEdge({
    required this.id,
    required this.fromNode,
    required this.toNode,
    required this.polyline,
    this.roadClass = RoadClass.unclassified,
    this.oneWay = false,
    this.maxSpeedMps,
    this.tunnel = false,
    this.bridge = false,
    this.access = const {VehicleAccess.cars, VehicleAccess.twoWheelers},
    this.name,
  })  : assert(polyline.length >= 4 && polyline.length.isEven),
        lengthM = _polylineLength(polyline);

  final int id;
  final int fromNode;
  final int toNode;

  /// Flat `[lat0, lon0, lat1, lon1, ...]`, at least two points.
  final List<double> polyline;

  final RoadClass roadClass;
  final bool oneWay;

  /// Null when the source data did not state one — never a guessed default.
  final double? maxSpeedMps;

  final bool tunnel;
  final bool bridge;
  final Set<VehicleAccess> access;
  final String? name;

  /// Total length along the polyline (m).
  final double lengthM;

  int get pointCount => polyline.length ~/ 2;
  double latAt(int i) => polyline[i * 2];
  double lonAt(int i) => polyline[i * 2 + 1];

  bool allows(VehicleAccess vehicle) => access.contains(vehicle);

  static double _polylineLength(List<double> polyline) {
    var total = 0.0;
    for (var i = 0; i + 3 < polyline.length; i += 2) {
      total += NavMath.horizontalDistance(
        lat0: polyline[i],
        lon0: polyline[i + 1],
        lat1: polyline[i + 2],
        lon1: polyline[i + 3],
      );
    }
    return total;
  }
}

/// Where a position falls on an edge.
@immutable
class EdgeProjection {
  const EdgeProjection({
    required this.edgeId,
    required this.lat,
    required this.lon,
    required this.perpendicularM,
    required this.alongM,
    required this.headingRad,
  });

  final int edgeId;

  /// The projected point on the road.
  final double lat;
  final double lon;

  /// Perpendicular distance from the query point to the road (m).
  final double perpendicularM;

  /// Distance along the edge from its start node (m).
  final double alongM;

  /// Direction of travel along the edge at this point (rad, 0 = North).
  final double headingRad;
}

/// An offline road graph with a uniform-grid spatial index (§33).
///
/// The grid is deliberately flat and simple: nearest-road lookup happens at
/// GNSS rate, not sensor rate, so an R-tree would buy nothing a 200 m cell
/// grid does not already give, and a flat array is what a memory-mapped
/// binary format wants later.
class RoadGraph {
  RoadGraph({
    required List<RoadNode> nodes,
    required List<RoadEdge> edges,
    this.region = '',
    this.version = 0,
    double cellSizeM = 200,
  })  : _nodes = {for (final n in nodes) n.id: n},
        _edges = {for (final e in edges) e.id: e},
        _cellSizeM = cellSizeM {
    _buildIndex();
    _buildAdjacency();
  }

  /// An empty graph. Every lookup returns nothing, which is what the matcher
  /// needs in order to report `unavailable` rather than inventing a match.
  factory RoadGraph.empty() => RoadGraph(nodes: const [], edges: const []);

  final Map<int, RoadNode> _nodes;
  final Map<int, RoadEdge> _edges;
  final double _cellSizeM;
  final String region;
  final int version;

  final Map<String, List<int>> _grid = {};
  final Map<int, List<int>> _outgoing = {};
  double _latCellDeg = 0;
  double _lonCellDeg = 0;
  double _meanLat = 0;

  bool get isEmpty => _edges.isEmpty;
  int get edgeCount => _edges.length;
  int get nodeCount => _nodes.length;

  Iterable<RoadEdge> get edges => _edges.values;
  RoadEdge? edge(int id) => _edges[id];
  RoadNode? node(int id) => _nodes[id];

  void _buildIndex() {
    if (_edges.isEmpty) return;
    var sumLat = 0.0;
    var count = 0;
    for (final e in _edges.values) {
      for (var i = 0; i < e.pointCount; i++) {
        sumLat += e.latAt(i);
        count++;
      }
    }
    _meanLat = sumLat / count;
    _latCellDeg = _cellSizeM / (NavMath.meridianRadius(
              _meanLat * NavMath.degToRad,
            ) *
            NavMath.degToRad);
    final lonMetresPerDeg = NavMath.normalRadius(_meanLat * NavMath.degToRad) *
        NavMath.degToRad *
        math.cos(_meanLat * NavMath.degToRad);
    _lonCellDeg = _cellSizeM / math.max(lonMetresPerDeg, 1);

    for (final e in _edges.values) {
      // Every cell the polyline touches, sampled densely enough that a long
      // straight segment cannot skip a cell.
      for (var i = 0; i + 1 < e.pointCount; i++) {
        _indexSegment(e.id, e.latAt(i), e.lonAt(i), e.latAt(i + 1),
            e.lonAt(i + 1));
      }
    }
  }

  void _indexSegment(
      int edgeId, double lat0, double lon0, double lat1, double lon1) {
    final steps = math.max(
      1,
      math.max(
        ((lat1 - lat0).abs() / _latCellDeg).ceil(),
        ((lon1 - lon0).abs() / _lonCellDeg).ceil(),
      ),
    );
    for (var s = 0; s <= steps; s++) {
      final t = s / steps;
      _addToCell(edgeId, lat0 + (lat1 - lat0) * t, lon0 + (lon1 - lon0) * t);
    }
  }

  void _addToCell(int edgeId, double lat, double lon) {
    final key = _cellKey(lat, lon);
    final list = _grid.putIfAbsent(key, () => <int>[]);
    if (!list.contains(edgeId)) list.add(edgeId);
  }

  String _cellKey(double lat, double lon) =>
      '${(lat / _latCellDeg).floor()}:${(lon / _lonCellDeg).floor()}';

  void _buildAdjacency() {
    for (final e in _edges.values) {
      _outgoing.putIfAbsent(e.fromNode, () => <int>[]).add(e.id);
      if (!e.oneWay) {
        _outgoing.putIfAbsent(e.toNode, () => <int>[]).add(e.id);
      }
    }
  }

  /// Edges whose polyline passes within [radiusM] of the point.
  ///
  /// [vehicle] filters out roads the vehicle may not use (§20).
  List<EdgeProjection> nearby(
    double lat,
    double lon, {
    double radiusM = 60,
    int limit = 8,
    VehicleAccess? vehicle,
  }) {
    if (_edges.isEmpty) return const [];
    final cellsLat = math.max(1, (radiusM / _cellSizeM).ceil());
    final baseLat = (lat / _latCellDeg).floor();
    final baseLon = (lon / _lonCellDeg).floor();

    final seen = <int>{};
    final results = <EdgeProjection>[];
    for (var dLat = -cellsLat; dLat <= cellsLat; dLat++) {
      for (var dLon = -cellsLat; dLon <= cellsLat; dLon++) {
        final ids = _grid['${baseLat + dLat}:${baseLon + dLon}'];
        if (ids == null) continue;
        for (final id in ids) {
          if (!seen.add(id)) continue;
          final e = _edges[id]!;
          if (vehicle != null && !e.allows(vehicle)) continue;
          final projection = project(id, lat, lon);
          if (projection != null && projection.perpendicularM <= radiusM) {
            results.add(projection);
          }
        }
      }
    }
    results.sort((a, b) => a.perpendicularM.compareTo(b.perpendicularM));
    return results.length <= limit ? results : results.sublist(0, limit);
  }

  /// Projects a point onto an edge's polyline.
  EdgeProjection? project(int edgeId, double lat, double lon) {
    final e = _edges[edgeId];
    if (e == null) return null;

    var bestPerp = double.infinity;
    var bestAlong = 0.0;
    var bestLat = e.latAt(0);
    var bestLon = e.lonAt(0);
    var bestHeading = 0.0;
    var travelled = 0.0;

    for (var i = 0; i + 1 < e.pointCount; i++) {
      final aLat = e.latAt(i), aLon = e.lonAt(i);
      final bLat = e.latAt(i + 1), bLon = e.lonAt(i + 1);

      // Local planar frame anchored at the segment start; exact enough over
      // the tens of metres a road segment spans.
      final ab = NavMath.nedBetween(
          lat0: aLat, lon0: aLon, alt0: 0, lat1: bLat, lon1: bLon, alt1: 0);
      final ap = NavMath.nedBetween(
          lat0: aLat, lon0: aLon, alt0: 0, lat1: lat, lon1: lon, alt1: 0);
      final segLength2 = ab.x * ab.x + ab.y * ab.y;
      final segLength = math.sqrt(segLength2);

      double t;
      if (segLength2 < 1e-9) {
        t = 0;
      } else {
        t = ((ap.x * ab.x + ap.y * ab.y) / segLength2).clamp(0.0, 1.0);
      }
      final closestN = ab.x * t;
      final closestE = ab.y * t;
      final dN = ap.x - closestN;
      final dE = ap.y - closestE;
      final perp = math.sqrt(dN * dN + dE * dE);

      if (perp < bestPerp) {
        bestPerp = perp;
        bestAlong = travelled + segLength * t;
        final moved = NavMath.addNed(
          latDeg: aLat,
          lonDeg: aLon,
          altM: 0,
          north: closestN,
          east: closestE,
          down: 0,
        );
        bestLat = moved[0];
        bestLon = moved[1];
        bestHeading = math.atan2(ab.y, ab.x);
      }
      travelled += segLength;
    }

    if (!bestPerp.isFinite) return null;
    return EdgeProjection(
      edgeId: edgeId,
      lat: bestLat,
      lon: bestLon,
      perpendicularM: bestPerp,
      alongM: bestAlong,
      headingRad: bestHeading,
    );
  }

  /// Shortest driving distance between two projections (m), or null when no
  /// route shorter than [capM] exists.
  ///
  /// Bounded on purpose: the matcher only needs to know whether a transition
  /// is plausible, and an unbounded search across a city graph to answer "no"
  /// would cost more than the whole match.
  double? routeDistance(
    EdgeProjection from,
    EdgeProjection to, {
    double capM = 2000,
    VehicleAccess? vehicle,
  }) {
    final fromEdge = _edges[from.edgeId];
    final toEdge = _edges[to.edgeId];
    if (fromEdge == null || toEdge == null) return null;

    if (from.edgeId == to.edgeId) {
      final delta = to.alongM - from.alongM;
      // Going backwards along a one-way is not a route.
      if (fromEdge.oneWay && delta < -1) return null;
      return delta.abs();
    }

    // Seed the search at whichever ends of the starting edge are reachable.
    final best = HashMap<int, double>();
    final queue = <_QueueEntry>[];
    void seed(int nodeId, double cost) {
      if (cost > capM) return;
      final existing = best[nodeId];
      if (existing != null && existing <= cost) return;
      best[nodeId] = cost;
      queue.add(_QueueEntry(nodeId, cost));
    }

    seed(fromEdge.toNode, fromEdge.lengthM - from.alongM);
    if (!fromEdge.oneWay) seed(fromEdge.fromNode, from.alongM);

    var result = double.infinity;
    while (queue.isNotEmpty) {
      queue.sort((a, b) => a.cost.compareTo(b.cost));
      final current = queue.removeAt(0);
      if (current.cost > capM || current.cost >= result) continue;
      if ((best[current.nodeId] ?? double.infinity) < current.cost) continue;

      // Arriving at the target edge finishes the route.
      if (current.nodeId == toEdge.fromNode) {
        result = math.min(result, current.cost + to.alongM);
      }
      if (!toEdge.oneWay && current.nodeId == toEdge.toNode) {
        result = math.min(result, current.cost + (toEdge.lengthM - to.alongM));
      }

      for (final edgeId in _outgoing[current.nodeId] ?? const <int>[]) {
        final e = _edges[edgeId]!;
        if (vehicle != null && !e.allows(vehicle)) continue;
        final next = e.fromNode == current.nodeId ? e.toNode : e.fromNode;
        if (e.oneWay && e.fromNode != current.nodeId) continue;
        seed(next, current.cost + e.lengthM);
      }
    }
    return result.isFinite ? result : null;
  }

  // ------------------------------------------------------------------ JSON

  /// Loads a graph from the format `maps/tools/graph_builder.py` emits.
  ///
  /// Returns null on anything malformed rather than a partial graph: matching
  /// against half a road network is worse than not matching at all.
  static RoadGraph? fromJson(Map<String, dynamic> json) {
    try {
      final rawNodes = json['nodes'];
      final rawEdges = json['edges'];
      if (rawNodes is! List || rawEdges is! List) return null;

      final nodes = <RoadNode>[];
      for (final raw in rawNodes) {
        if (raw is! Map) return null;
        final id = (raw['id'] as num?)?.toInt();
        final lat = (raw['lat'] as num?)?.toDouble();
        final lon = (raw['lon'] as num?)?.toDouble();
        if (id == null || lat == null || lon == null) return null;
        if (!lat.isFinite || !lon.isFinite) return null;
        nodes.add(RoadNode(id: id, lat: lat, lon: lon));
      }

      final edges = <RoadEdge>[];
      for (final raw in rawEdges) {
        if (raw is! Map) return null;
        final id = (raw['id'] as num?)?.toInt();
        final from = (raw['from'] as num?)?.toInt();
        final to = (raw['to'] as num?)?.toInt();
        final polyline = (raw['polyline'] as List?)
            ?.whereType<num>()
            .map((n) => n.toDouble())
            .toList();
        if (id == null || from == null || to == null) return null;
        if (polyline == null ||
            polyline.length < 4 ||
            polyline.length.isOdd ||
            polyline.any((v) => !v.isFinite)) {
          return null;
        }
        final accessRaw = (raw['access'] as List?)?.whereType<String>();
        edges.add(RoadEdge(
          id: id,
          fromNode: from,
          toNode: to,
          polyline: polyline,
          roadClass: RoadClass.values.firstWhere(
            (c) => c.name == raw['class'],
            orElse: () => RoadClass.unclassified,
          ),
          oneWay: raw['oneWay'] == true,
          maxSpeedMps: (raw['maxSpeedMps'] as num?)?.toDouble(),
          tunnel: raw['tunnel'] == true,
          bridge: raw['bridge'] == true,
          access: accessRaw == null
              ? const {VehicleAccess.cars, VehicleAccess.twoWheelers}
              : {
                  for (final a in accessRaw)
                    ...VehicleAccess.values.where((v) => v.name == a),
                },
          name: raw['name'] as String?,
        ));
      }
      if (edges.isEmpty) return null;

      return RoadGraph(
        nodes: nodes,
        edges: edges,
        region: json['region'] as String? ?? '',
        version: (json['version'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class _QueueEntry {
  const _QueueEntry(this.nodeId, this.cost);
  final int nodeId;
  final double cost;
}
