import 'dart:collection';
import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../map/road_graph.dart';
import '../math/nav_math.dart';
import '../nav_config.dart';
import 'planned_route.dart';

/// One traversal of an edge, in the edge's own along-coordinate (0 at
/// `fromNode`). `forward` says whether it was driven `fromNode` -> `toNode`;
/// [fromAlong]/[toAlong] slice the edge when the traversal is only partial
/// (the very first and last steps of a route).
typedef _RouteStep = ({
  int edgeId,
  bool forward,
  double fromAlong,
  double toAlong,
});

/// A search-graph node's predecessor: which node it was reached from and the
/// edge slice that reached it.
typedef _Predecessor = ({int from, _RouteStep step});

typedef _StepRange = ({int startVertex, int endVertex, RoadEdge edge});

typedef _Boundary = ({int atVertexIndex, int nodeId, int stepIndexBefore});

typedef _ManeuverCandidate = ({
  double atM,
  double lat,
  double lon,
  ManeuverKind kind,
  String? roadName,
  double turnAbs,
});

/// Virtual search-graph nodes for the snapped start/destination points —
/// negative so they can never collide with a real (always >= 0) node id.
const int _kStart = -1;
const int _kDest = -2;

/// Numerical slack for "is this priority-queue entry stale" / "did this
/// improve the best known cost" comparisons. Costs are seconds of travel
/// time (order 1 to a few thousand); this is far below double precision at
/// that scale, so it only ever catches genuine float noise, never masks a
/// real tie.
const double _costEps = 1e-6;

/// Plans a driving route on the offline road graph.
///
/// Snaps [fromLat]/[fromLon] and [toLat]/[toLon] to the nearest road usable
/// by [vehicle] within `config.snapRadiusM`, runs A* (travel-time cost,
/// admissible straight-line heuristic, one-way respected), and returns the
/// geometry from the snapped start to the snapped destination with its
/// maneuvers (first depart, last arrive) and tunnels. Null when either end has
/// no road nearby or no path exists. Pure, synchronous, safe to run inside an
/// isolate.
PlannedRoute? planRoute(
  RoadGraph graph, {
  required double fromLat,
  required double fromLon,
  required double toLat,
  required double toLon,
  VehicleAccess vehicle = VehicleAccess.cars,
  RouteConfig config = const RouteConfig(),
}) {
  if (graph.isEmpty) return null;
  final starts = graph.nearby(fromLat, fromLon,
      radiusM: config.snapRadiusM,
      limit: config.snapCandidates,
      vehicle: vehicle);
  final dests = graph.nearby(toLat, toLon,
      radiusM: config.snapRadiusM,
      limit: config.snapCandidates,
      vehicle: vehicle);
  if (starts.isEmpty || dests.isEmpty) return null;

  final result = _search(graph, config, vehicle,
      starts: starts, dests: dests, toLat: toLat, toLon: toLon);
  if (result == null) return null;

  return _assembleRoute(graph, config, result.steps, result.durationS);
}

// --------------------------------------------------------------- A* search

double _speedOf(RouteConfig config, RoadEdge e) =>
    e.maxSpeedMps ??
    config.classSpeedMps[e.roadClass] ??
    config.classSpeedMps[RoadClass.unclassified]!;

({List<_RouteStep> steps, double durationS})? _search(
  RoadGraph graph,
  RouteConfig config,
  VehicleAccess vehicle, {
  required List<EdgeProjection> starts,
  required List<EdgeProjection> dests,
  required double toLat,
  required double toLon,
}) {
  final fastestSpeed = config.classSpeedMps.values.reduce(math.max);
  double heuristic(double lat, double lon) =>
      NavMath.horizontalDistance(lat0: lat, lon0: lon, lat1: toLat, lon1: toLon) /
      fastestSpeed;

  final g = HashMap<int, double>();
  final cameFrom = HashMap<int, _Predecessor>();
  final open = HeapPriorityQueue<({int nodeId, double g, double f})>(
      (a, b) => a.f.compareTo(b.f));

  void relax(int from, int to, double addCost, _RouteStep step, double hTo) {
    final newG = g[from]! + addCost;
    final existing = g[to];
    if (existing != null && existing <= newG + _costEps) return;
    g[to] = newG;
    cameFrom[to] = (from: from, step: step);
    open.add((nodeId: to, g: newG, f: newG + hTo));
  }

  g[_kStart] = 0;

  // Destination candidates grouped by edge, for the same-edge direct shortcut
  // below (start and destination both project onto one road).
  final destsByEdge = <int, List<EdgeProjection>>{};
  for (final d in dests) {
    destsByEdge.putIfAbsent(d.edgeId, () => []).add(d);
  }

  for (final sp in starts) {
    final edge = graph.edge(sp.edgeId);
    if (edge == null || !edge.allows(vehicle)) continue;
    final speed = _speedOf(config, edge);

    final toNode = graph.node(edge.toNode);
    if (toNode != null) {
      relax(_kStart, edge.toNode, (edge.lengthM - sp.alongM) / speed,
          (edgeId: edge.id, forward: true, fromAlong: sp.alongM, toAlong: edge.lengthM),
          heuristic(toNode.lat, toNode.lon));
    }
    if (!edge.oneWay) {
      final fromNode = graph.node(edge.fromNode);
      if (fromNode != null) {
        relax(_kStart, edge.fromNode, sp.alongM / speed,
            (edgeId: edge.id, forward: false, fromAlong: sp.alongM, toAlong: 0),
            heuristic(fromNode.lat, fromNode.lon));
      }
    }

    // Same-edge shortcut: start and destination both fall on this edge and
    // the direct direction is legal (always, for a two-way road; only
    // forward, for a one-way). ponytail: assumes the direct slice is the
    // fastest way between two points on the same edge, which holds for any
    // sane road geometry — a graph shortcut through another road covering
    // the same stretch faster is not modelled.
    for (final dp in destsByEdge[edge.id] ?? const <EdgeProjection>[]) {
      final delta = dp.alongM - sp.alongM;
      if (edge.oneWay && delta < 0) continue;
      relax(_kStart, _kDest, delta.abs() / speed,
          (edgeId: edge.id, forward: delta >= 0, fromAlong: sp.alongM, toAlong: dp.alongM),
          0);
    }
  }

  // Which node(s) can reach each destination candidate, and at what cost.
  final arrivals = <int, List<({double cost, _RouteStep step})>>{};
  for (final dp in dests) {
    final edge = graph.edge(dp.edgeId);
    if (edge == null || !edge.allows(vehicle)) continue;
    final speed = _speedOf(config, edge);
    arrivals.putIfAbsent(edge.fromNode, () => []).add((
      cost: dp.alongM / speed,
      step: (edgeId: edge.id, forward: true, fromAlong: 0, toAlong: dp.alongM),
    ));
    if (!edge.oneWay) {
      arrivals.putIfAbsent(edge.toNode, () => []).add((
        cost: (edge.lengthM - dp.alongM) / speed,
        step: (edgeId: edge.id, forward: false, fromAlong: edge.lengthM, toAlong: dp.alongM),
      ));
    }
  }

  final visited = HashSet<int>();
  while (open.isNotEmpty) {
    final entry = open.removeFirst();
    if (visited.contains(entry.nodeId)) continue;
    final bestG = g[entry.nodeId];
    if (bestG == null || (entry.g - bestG).abs() > _costEps) continue;
    visited.add(entry.nodeId);

    if (entry.nodeId == _kDest) {
      return (steps: _reconstruct(cameFrom, entry.nodeId), durationS: bestG);
    }

    for (final a in arrivals[entry.nodeId] ?? const []) {
      relax(entry.nodeId, _kDest, a.cost, a.step, 0);
    }
    for (final edgeId in graph.outgoing(entry.nodeId)) {
      final edge = graph.edge(edgeId);
      if (edge == null || !edge.allows(vehicle)) continue;
      final forward = edge.fromNode == entry.nodeId;
      final nextId = forward ? edge.toNode : edge.fromNode;
      final nextNode = graph.node(nextId);
      if (nextNode == null) continue;
      relax(entry.nodeId, nextId, edge.lengthM / _speedOf(config, edge),
          (edgeId: edge.id, forward: forward, fromAlong: forward ? 0 : edge.lengthM,
              toAlong: forward ? edge.lengthM : 0),
          heuristic(nextNode.lat, nextNode.lon));
    }
  }
  return null;
}

List<_RouteStep> _reconstruct(Map<int, _Predecessor> cameFrom, int dest) {
  final steps = <_RouteStep>[];
  var cur = dest;
  while (true) {
    final p = cameFrom[cur];
    if (p == null) break;
    steps.add(p.step);
    cur = p.from;
  }
  return steps.reversed.toList();
}

// ------------------------------------------------------------- geometry

/// Cumulative distance (m) at each vertex of [e]'s own polyline.
List<double> _edgeCumulative(RoadEdge e) {
  final n = e.pointCount;
  final cum = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    cum[i] = cum[i - 1] +
        NavMath.horizontalDistance(
          lat0: e.latAt(i - 1),
          lon0: e.lonAt(i - 1),
          lat1: e.latAt(i),
          lon1: e.lonAt(i),
        );
  }
  return cum;
}

({double lat, double lon}) _interpOnEdge(
    RoadEdge e, List<double> cum, double along) {
  final n = e.pointCount;
  final clamped = along.clamp(0.0, cum.last);
  var lo = 0, hi = n - 1;
  while (lo < hi - 1) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] <= clamped) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final span = cum[hi] - cum[lo];
  final t = span > 1e-9 ? (clamped - cum[lo]) / span : 0.0;
  return (
    lat: e.latAt(lo) + (e.latAt(hi) - e.latAt(lo)) * t,
    lon: e.lonAt(lo) + (e.lonAt(hi) - e.lonAt(lo)) * t,
  );
}

/// Vertices of [e] between [aAlong] and [bAlong] (edge's own along
/// coordinate), always start-to-end in travel order — reversed automatically
/// when `bAlong < aAlong`. Always includes exact interpolated endpoints, and
/// never repeats an interior vertex within epsilon of an endpoint.
List<double> _sliceEdge(
    RoadEdge e, List<double> cum, double aAlong, double bAlong) {
  final forward = bAlong >= aAlong;
  final lo = forward ? aAlong : bAlong;
  final hi = forward ? bAlong : aAlong;
  final pts = <double>[];
  final start = _interpOnEdge(e, cum, lo);
  pts
    ..add(start.lat)
    ..add(start.lon);
  for (var i = 0; i < e.pointCount; i++) {
    if (cum[i] > lo + 1e-6 && cum[i] < hi - 1e-6) {
      pts
        ..add(e.latAt(i))
        ..add(e.lonAt(i));
    }
  }
  final end = _interpOnEdge(e, cum, hi);
  pts
    ..add(end.lat)
    ..add(end.lon);
  if (forward) return pts;
  final out = <double>[];
  for (var i = pts.length - 2; i >= 0; i -= 2) {
    out
      ..add(pts[i])
      ..add(pts[i + 1]);
  }
  return out;
}

/// Cumulative distance (m) at each vertex of a flat polyline — the same
/// per-segment formula `PlannedRoute` itself uses, so `atM` values computed
/// against this line up exactly with `PlannedRoute.cumM`.
List<double> _routeCumulative(List<double> polyline) {
  final n = polyline.length ~/ 2;
  final cum = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    cum[i] = cum[i - 1] +
        NavMath.horizontalDistance(
          lat0: polyline[(i - 1) * 2],
          lon0: polyline[(i - 1) * 2 + 1],
          lat1: polyline[i * 2],
          lon1: polyline[i * 2 + 1],
        );
  }
  return cum;
}

({double lat, double lon}) _pointAtM(
    List<double> polyline, List<double> cum, double atM) {
  final clamped = atM.clamp(0.0, cum.last);
  var lo = 0, hi = cum.length - 1;
  while (lo < hi - 1) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] <= clamped) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final span = cum[hi] - cum[lo];
  final t = span > 1e-9 ? (clamped - cum[lo]) / span : 0.0;
  return (
    lat: polyline[lo * 2] + (polyline[hi * 2] - polyline[lo * 2]) * t,
    lon: polyline[lo * 2 + 1] + (polyline[hi * 2 + 1] - polyline[lo * 2 + 1]) * t,
  );
}

double _bearingBetween(({double lat, double lon}) a, ({double lat, double lon}) b) {
  final d = NavMath.nedBetween(
      lat0: a.lat, lon0: a.lon, alt0: 0, lat1: b.lat, lon1: b.lon, alt1: 0);
  return NavMath.wrap360(math.atan2(d.y, d.x) * NavMath.radToDeg);
}

/// A node touched by two edges or fewer is not a decision point — it is a
/// tile-border split or a dead end (§ real-map traps in the nav CLAUDE.md) —
/// so no maneuver is ever emitted there.
Map<int, int> _nodeDegree(RoadGraph g) {
  final deg = HashMap<int, int>();
  for (final e in g.edges) {
    deg[e.fromNode] = (deg[e.fromNode] ?? 0) + 1;
    deg[e.toNode] = (deg[e.toNode] ?? 0) + 1;
  }
  return deg;
}

PlannedRoute _assembleRoute(
  RoadGraph graph,
  RouteConfig config,
  List<_RouteStep> steps,
  double durationS,
) {
  final polyline = <double>[];
  final stepRanges = <_StepRange>[];
  final boundaries = <_Boundary>[];

  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final edge = graph.edge(step.edgeId)!;
    final cum = _edgeCumulative(edge);
    final verts = _sliceEdge(edge, cum, step.fromAlong, step.toAlong);
    final startVertex = i == 0 ? 0 : (polyline.length ~/ 2) - 1;
    polyline.addAll(i == 0 ? verts : verts.sublist(2));
    final endVertex = polyline.length ~/ 2 - 1;
    stepRanges.add((startVertex: startVertex, endVertex: endVertex, edge: edge));
    if (i < steps.length - 1) {
      final nodeId = step.forward ? edge.toNode : edge.fromNode;
      boundaries.add((atVertexIndex: endVertex, nodeId: nodeId, stepIndexBefore: i));
    }
  }

  final cumM = _routeCumulative(polyline);
  final nodeDegree = boundaries.isEmpty ? const <int, int>{} : _nodeDegree(graph);

  final candidates = <_ManeuverCandidate>[];
  for (final b in boundaries) {
    if ((nodeDegree[b.nodeId] ?? 0) < 3) continue; // not a real junction
    final atM = cumM[b.atVertexIndex];
    final here = (lat: polyline[b.atVertexIndex * 2], lon: polyline[b.atVertexIndex * 2 + 1]);
    final inPt = _pointAtM(polyline, cumM, atM - config.maneuverBearingSampleM);
    final outPt = _pointAtM(polyline, cumM, atM + config.maneuverBearingSampleM);
    final incoming = _bearingBetween(inPt, here);
    final outgoing = _bearingBetween(here, outPt);
    final turn = NavMath.angleDiffDeg(outgoing, incoming);
    final turnAbs = turn.abs();
    final before = stepRanges[b.stepIndexBefore].edge;
    final after = stepRanges[b.stepIndexBefore + 1].edge;
    final nameChanged = before.name != after.name;

    ManeuverKind? kind;
    if (turnAbs < config.maneuverSlightDeg) {
      if (nameChanged) kind = ManeuverKind.continueOn;
    } else if (turnAbs < config.maneuverTurnDeg) {
      kind = turn > 0 ? ManeuverKind.slightRight : ManeuverKind.slightLeft;
    } else if (turnAbs < config.maneuverSharpDeg) {
      kind = turn > 0 ? ManeuverKind.right : ManeuverKind.left;
    } else if (turnAbs < config.maneuverUTurnDeg) {
      kind = turn > 0 ? ManeuverKind.sharpRight : ManeuverKind.sharpLeft;
    } else {
      kind = ManeuverKind.uTurn;
    }
    if (kind == null) continue;
    candidates.add((
      atM: atM,
      lat: here.lat,
      lon: here.lon,
      kind: kind,
      roadName: after.name,
      turnAbs: turnAbs,
    ));
  }

  final merged = <_ManeuverCandidate>[];
  for (final c in candidates) {
    if (merged.isNotEmpty && (c.atM - merged.last.atM) < config.maneuverMergeM) {
      if (c.turnAbs > merged.last.turnAbs) merged[merged.length - 1] = c;
    } else {
      merged.add(c);
    }
  }

  final maneuvers = <RouteManeuver>[
    RouteManeuver(
      kind: ManeuverKind.depart,
      atM: 0,
      lat: polyline[0],
      lon: polyline[1],
      roadName: stepRanges.first.edge.name,
    ),
    for (final m in merged)
      RouteManeuver(kind: m.kind, atM: m.atM, lat: m.lat, lon: m.lon, roadName: m.roadName),
    RouteManeuver(
      kind: ManeuverKind.arrive,
      atM: cumM.last,
      lat: polyline[polyline.length - 2],
      lon: polyline[polyline.length - 1],
    ),
  ];

  final tunnels = <RouteSpan>[];
  for (final s in stepRanges) {
    if (!s.edge.tunnel) continue;
    final fromM = cumM[s.startVertex];
    final toM = cumM[s.endVertex];
    if (tunnels.isNotEmpty && (fromM - tunnels.last.toM).abs() < 1e-6) {
      tunnels[tunnels.length - 1] = RouteSpan(tunnels.last.fromM, toM);
    } else {
      tunnels.add(RouteSpan(fromM, toM));
    }
  }

  return PlannedRoute(
    polyline: polyline,
    maneuvers: maneuvers,
    durationS: durationS,
    tunnels: tunnels,
  );
}
