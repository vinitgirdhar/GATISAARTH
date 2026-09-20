import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';
import '../nav_config.dart';
import 'road_graph.dart';

/// Below this a segment has no direction (repeated vertex) and a bearing
/// difference is a float artefact rather than a real preference.
const double _degenerateM = 1e-9;
const double _tieDeg = 1e-6;

/// Where the follower has put the vehicle: always exactly on a road.
@immutable
class RoadPosition {
  const RoadPosition({
    required this.lat,
    required this.lon,
    required this.headingDeg,
    required this.edgeId,
    required this.alongM,
    required this.roadClass,
    this.name,
  });

  final double lat;
  final double lon;

  /// Direction of travel, compass degrees in [0, 360).
  final double headingDeg;
  final int edgeId;

  /// Metres from the start of the edge's polyline, whichever way the vehicle
  /// is driving.
  final double alongM;
  final RoadClass roadClass;
  final String? name;

  @override
  String toString() =>
      'RoadPosition(edge $edgeId @ ${alongM.toStringAsFixed(1)}'
      ' m, ${headingDeg.toStringAsFixed(0)} deg)';
}

/// An edge's polyline unrolled into cumulative distance and one bearing per
/// segment, built once so a 1 m step on a 400-vertex edge is a cursor move
/// and not a re-scan. Lengths use the same per-segment formula as
/// `RoadGraph.project`, so `alongM` means the same thing in both.
class _Geom {
  _Geom._(this.edge, this.cum, this.bearing);

  factory _Geom.of(RoadEdge edge) {
    final n = edge.pointCount;
    final cum = Float64List(n);
    final bearing = Float64List(n - 1);
    for (var i = 0; i < n - 1; i++) {
      final d = NavMath.nedBetween(
        lat0: edge.latAt(i),
        lon0: edge.lonAt(i),
        alt0: 0,
        lat1: edge.latAt(i + 1),
        lon1: edge.lonAt(i + 1),
        alt1: 0,
      );
      final len = math.sqrt(d.x * d.x + d.y * d.y);
      cum[i + 1] = cum[i] + len;
      bearing[i] = len < _degenerateM
          ? double.nan
          : NavMath.wrap360(math.atan2(d.y, d.x) * NavMath.radToDeg);
    }
    _inheritBearings(bearing);
    return _Geom._(edge, cum, bearing);
  }

  final RoadEdge edge;
  final Float64List cum;
  final Float64List bearing;

  double get length => cum.last;
  int get lastSeg => bearing.length - 1;

  /// A repeated vertex has no direction of its own; it keeps its neighbour's
  /// so the vehicle never reports a heading of 0 for no reason.
  static void _inheritBearings(Float64List b) {
    var last = double.nan;
    for (var i = 0; i < b.length; i++) {
      if (b[i].isNaN) {
        b[i] = last;
      } else {
        last = b[i];
      }
    }
    for (var i = b.length - 2; i >= 0; i--) {
      if (b[i].isNaN) b[i] = b[i + 1];
    }
    if (b[0].isNaN) b.fillRange(0, b.length, 0);
  }

  /// The segment with `cum[s] <= along < cum[s + 1]` (the last one owns the
  /// end point).
  int segmentAt(double along) {
    var lo = 0;
    var hi = lastSeg;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (along >= cum[mid + 1]) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  ({double lat, double lon}) pointAt(int seg, double along) {
    final span = cum[seg + 1] - cum[seg];
    final t = span > _degenerateM
        ? math.min(math.max((along - cum[seg]) / span, 0.0), 1.0)
        : 0.0;
    final lat = edge.latAt(seg), lon = edge.lonAt(seg);
    return (
      lat: lat + (edge.latAt(seg + 1) - lat) * t,
      lon: lon + (edge.lonAt(seg + 1) - lon) * t,
    );
  }
}

/// A place and direction on some edge that the follower could move to.
class _Pick {
  const _Pick(this.geom, this.along, this.forward, this.bearing, this.score);

  final _Geom geom;
  final double along;
  final bool forward;
  final double bearing;

  /// Lower is better: perpendicular metres plus the heading penalty for a lock
  /// or relock, the absolute angle off the desired course for a junction exit.
  final double score;

  /// Deterministic order for exact ties: edge ids are arbitrary but stable.
  bool tieBreaksBefore(_Pick o) => geom.edge.id != o.geom.edge.id
      ? geom.edge.id < o.geom.edge.id
      : forward && !o.forward;

  bool beats(_Pick? best) =>
      best == null ||
      score < best.score - _tieDeg ||
      ((score - best.score).abs() <= _tieDeg && tieBreaksBefore(best));
}

/// Keeps a dead-reckoned marker on the road network.
///
/// The road is followed by GEOMETRY only. Graphs built from vector tiles have
/// arbitrary node ids, one long edge through many crossings, and neighbouring
/// tiles that repeat the last ~15 m of a road, so `fromNode`/`toNode` say
/// nothing about what connects.
///
/// Position is (edge, direction, metres along). Heading is that edge's bearing
/// there, so the marker cannot leave the road by construction. What the road
/// cannot say is which way the driver goes at a crossing; that comes from the
/// gyroscope as [unexplainedYawDeg]: the turning the road's own curvature does
/// not account for.
class RoadFollower {
  RoadFollower({
    RoadGraph? graph,
    this.config = const RoadFollowConfig(),
    this.vehicle,
  }) : _graph = graph;

  final RoadFollowConfig config;

  /// Restricts the roads used (null = any).
  final VehicleAccess? vehicle;

  RoadGraph? _graph;
  final Map<int, _Geom> _geoms = {};
  _Geom? _geom;
  bool _forward = true;
  double _along = 0;
  int _seg = 0;
  double _unexplained = 0;

  /// Whether this `advance` call carried yaw. A caller with no gyroscope (the
  /// simulator) passes exactly 0, and road curvature must not be charged
  /// against turning it never reported: a real gyroscope never reads 0.0.
  bool _trackYaw = false;

  RoadGraph? get graph => _graph;
  bool get isLocked => _geom != null;

  /// Vehicle turning the road has not explained yet (deg, right = +).
  double get unexplainedYawDeg => _unexplained;

  /// Swaps the graph under a locked follower, e.g. when tiles load. Edge ids
  /// may mean different roads now, so re-lock on the same spot; if the road is
  /// not there any more, let go rather than teleport. The pending turn is
  /// kept: the driver is still mid-manoeuvre.
  set graph(RoadGraph? value) {
    if (identical(value, _graph)) return;
    final was = position;
    final keep = _unexplained;
    release();
    _graph = value;
    _geoms.clear();
    if (was == null) return;
    final ok = lock(
      lat: was.lat,
      lon: was.lon,
      headingDeg: was.headingDeg,
      maxRadiusM: config.rebindRadiusM,
    );
    if (ok) _unexplained = keep;
  }

  RoadPosition? get position {
    final g = _geom;
    if (g == null) return null;
    final p = g.pointAt(_seg, _along);
    return RoadPosition(
      lat: p.lat,
      lon: p.lon,
      headingDeg: _heading(),
      edgeId: g.edge.id,
      alongM: _along,
      roadClass: g.edge.roadClass,
      name: g.edge.name,
    );
  }

  void release() {
    _geom = null;
    _unexplained = 0;
  }

  /// Snaps onto the best road within [maxRadiusM].
  ///
  /// Every (edge, direction) is scored by perpendicular distance plus a
  /// heading penalty, so a driver 5 m from a road pointing the wrong way still
  /// prefers a road 20 m away pointing the right way. A one-way only offers
  /// its digitised direction; with no heading that is the direction taken.
  /// Returns false, leaving the state alone, when nothing qualifies.
  bool lock({
    required double lat,
    required double lon,
    double? headingDeg,
    double maxRadiusM = 40,
  }) {
    final g = _graph;
    if (g == null || !lat.isFinite || !lon.isFinite || !(maxRadiusM > 0)) {
      return false;
    }
    final heading =
        headingDeg != null && headingDeg.isFinite ? headingDeg : null;
    _Pick? best;
    final near = g.nearby(lat, lon,
        radiusM: maxRadiusM, limit: config.candidateLimit, vehicle: vehicle);
    for (final p in near) {
      final geom = _geomOf(p.edgeId);
      if (geom == null) continue;
      for (final forward in _legalDirections(geom)) {
        if (!forward && heading == null) continue;
        final bearing = _bearingOf(p, forward);
        final miss = heading == null
            ? 0.0
            : NavMath.angleDiffDeg(bearing, heading).abs();
        final pick = _Pick(geom, p.alongM, forward, bearing,
            p.perpendicularM + config.headingWeightMPerDeg * miss);
        if (pick.beats(best)) best = pick;
      }
    }
    if (best == null) return false;
    _enter(best);
    _unexplained = 0;
    return true;
  }

  /// Moves [meters] forward along the road and returns how far it really got:
  /// less than asked only at a dead end. [yawDeg] is how much the vehicle
  /// turned since the last call (right = +), from the gyroscope.
  ///
  /// At a dead end a real vehicle has left the map, so the follower waits there
  /// for the graph to say more. A simulated drive has no such excuse, and one
  /// that stops at the end of the first cul-de-sac looks broken: with
  /// [reverseAtDeadEnd] a two-way road is driven back the way it came.
  ///
  /// Junctions are resolved when an edge runs out, and crossings inside an
  /// edge when the accumulated unexplained turning matches a road nearby.
  double advance(double meters,
      {double yawDeg = 0, bool reverseAtDeadEnd = false}) {
    if (_geom == null) return 0;
    _trackYaw = yawDeg.isFinite && yawDeg != 0;
    if (_trackYaw) {
      _unexplained = NavMath.angleDiffDeg(_unexplained + yawDeg, 0);
    }
    if (!meters.isFinite || meters <= 0) return 0;
    final travelled = _walk(meters, reverseAtDeadEnd);
    _unexplained *= math.exp(-travelled / config.yawLeakMeters);
    _relockAfterTurn();
    return travelled;
  }

  /// Along-track pull toward a noisy fix (urban-canyon GNSS).
  ///
  /// Only the component along the road is used: across it the road already
  /// knows better. A fix further off than the road could plausibly explain is
  /// ignored, and turning is not charged for the shift: nobody steered.
  bool correct(
    double lat,
    double lon, {
    required double sigmaM,
    double gain = 0.3,
    double maxStepM = 12,
  }) {
    final g = _geom;
    final graph = _graph;
    if (g == null || graph == null) return false;
    if (![lat, lon, sigmaM, gain, maxStepM].every((v) => v.isFinite)) {
      return false;
    }
    final p = graph.project(g.edge.id, lat, lon);
    if (p == null ||
        p.perpendicularM > math.max(config.correctMinPerpM, 2 * sigmaM.abs())) {
      return false;
    }
    final toFix = _forward ? p.alongM - _along : _along - p.alongM;
    final cap = maxStepM.abs();
    final step = math.min(math.max(gain * toFix, -cap), cap);
    _seek(_forward ? _along + step : _along - step, charge: false);
    return true;
  }

  // ------------------------------------------------------------------ walk

  double _walk(double meters, bool reverseAtDeadEnd) {
    var remaining = meters;
    var travelled = 0.0;
    var hops = 0;
    while (remaining > 0) {
      final g = _geom!;
      final toEnd = _forward ? g.length - _along : _along;
      if (remaining <= toEnd) {
        _seek(_forward ? _along + remaining : _along - remaining, charge: true);
        return travelled + remaining;
      }
      _seek(_forward ? g.length : 0.0, charge: true);
      travelled += toEnd;
      remaining -= toEnd;
      if (hops++ >= config.maxHopsPerAdvance) break;
      if (_takeExit()) continue;
      if (!reverseAtDeadEnd || _geom!.edge.oneWay) break;
      _forward = !_forward;
      _unexplained = 0;
    }
    return travelled;
  }

  /// Moves the cursor to [target] metres along the edge, charging the road's
  /// own bearing changes against the vehicle's turning as vertices pass.
  void _seek(double target, {required bool charge}) {
    final g = _geom!;
    _along = math.min(math.max(target, 0.0), g.length);
    while (_seg < g.lastSeg && _along >= g.cum[_seg + 1]) {
      if (charge) {
        _charge(NavMath.angleDiffDeg(g.bearing[_seg + 1], g.bearing[_seg]));
      }
      _seg++;
    }
    while (_seg > 0 && _along < g.cum[_seg]) {
      if (charge) {
        _charge(NavMath.angleDiffDeg(g.bearing[_seg - 1], g.bearing[_seg]));
      }
      _seg--;
    }
  }

  void _charge(double roadTurnDeg) {
    if (_trackYaw) {
      _unexplained = NavMath.angleDiffDeg(_unexplained - roadTurnDeg, 0);
    }
  }

  void _enter(_Pick p) {
    _geom = p.geom;
    _forward = p.forward;
    _along = math.min(math.max(p.along, 0.0), p.geom.length);
    _seg = p.geom.segmentAt(_along);
  }

  // -------------------------------------------------------------- junctions

  /// The vehicle is at the end of its edge: pick where it goes next.
  bool _takeExit() {
    final arrival = _heading();
    final exit = _findExit(arrival);
    if (exit == null) return false;
    _enter(exit);
    _charge(NavMath.angleDiffDeg(_heading(), arrival));
    return true;
  }

  _Pick? _findExit(double arrival) {
    final g = _graph;
    final from = _geom;
    if (g == null || from == null) return null;
    final desired = arrival + _unexplained;
    final options = <_Pick>[];
    for (final p in _joinCandidates(g, from)) {
      final geom = _geomOf(p.edgeId);
      if (geom == null) continue;
      for (final forward in _legalDirections(geom)) {
        final ahead = forward ? geom.length - p.alongM : p.alongM;
        if (ahead < config.minExitLengthM) continue;
        final bearing = _lookAheadBearing(geom, p, forward);
        final dev = NavMath.angleDiffDeg(bearing, desired).abs();
        if (dev <= config.maxExitDeviationDeg) {
          options.add(_Pick(geom, p.alongM, forward, bearing, dev));
        }
      }
    }
    return _pickExit(options, from.edge.name);
  }

  /// Roads meeting the end of the current edge. Neighbour-tile copies pass
  /// THROUGH the end point mid-edge, so this is where border overlaps heal.
  List<EdgeProjection> _joinCandidates(RoadGraph g, _Geom from) {
    final e = from.edge;
    final endIdx = _forward ? e.pointCount - 1 : 0;
    final found = g
        .nearby(e.latAt(endIdx), e.lonAt(endIdx),
            radiusM: config.joinToleranceM,
            limit: config.candidateLimit,
            vehicle: vehicle)
        .where((p) => p.edgeId != e.id)
        .toList();
    final ring = _ringClosure(from);
    return ring == null ? found : [...found, ring];
  }

  /// A closed ring (roundabout, loop street) joins its own far end, which
  /// "other edges only" would otherwise dead-end at.
  EdgeProjection? _ringClosure(_Geom g) {
    final e = g.edge;
    final last = e.pointCount - 1;
    final gap = NavMath.horizontalDistance(
        lat0: e.latAt(0),
        lon0: e.lonAt(0),
        lat1: e.latAt(last),
        lon1: e.lonAt(last));
    if (gap > config.joinToleranceM) return null;
    final otherEnd = _forward ? 0 : last;
    return EdgeProjection(
      edgeId: e.id,
      lat: e.latAt(otherEnd),
      lon: e.lonAt(otherEnd),
      perpendicularM: gap,
      alongM: _forward ? 0.0 : g.length,
      headingRad: g.bearing[_forward ? 0 : g.lastSeg] * NavMath.degToRad,
    );
  }

  /// Bearing from the join to a point [RoadFollowConfig.lookAheadM] further
  /// along, clamped at the edge's end: long enough to ignore digitising
  /// jitter at the junction, short enough to be about the exit and not the bend
  /// after it.
  double _lookAheadBearing(_Geom g, EdgeProjection p, bool forward) {
    final target = forward
        ? math.min(p.alongM + config.lookAheadM, g.length)
        : math.max(p.alongM - config.lookAheadM, 0.0);
    final pt = g.pointAt(g.segmentAt(target), target);
    final d = NavMath.nedBetween(
        lat0: p.lat, lon0: p.lon, alt0: 0, lat1: pt.lat, lon1: pt.lon, alt1: 0);
    return NavMath.wrap360(math.atan2(d.y, d.x) * NavMath.radToDeg);
  }

  /// Smallest deviation wins, but exits within `straightBiasDeg` of it are
  /// ranked by same road name, then road class, then angle: at a crossing the
  /// vehicle stays on the road it is on unless the driver clearly turned.
  _Pick? _pickExit(List<_Pick> options, String? currentName) {
    if (options.isEmpty) return null;
    final best = options.map((o) => o.score).reduce(math.min);
    _Pick? chosen;
    for (final o in options) {
      if (o.score > best + config.straightBiasDeg) continue;
      if (chosen == null || _ranksBefore(o, chosen, currentName)) chosen = o;
    }
    return chosen;
  }

  bool _ranksBefore(_Pick a, _Pick b, String? name) {
    final sameA = name != null && a.geom.edge.name == name;
    final sameB = name != null && b.geom.edge.name == name;
    if (sameA != sameB) return sameA;
    final classA = a.geom.edge.roadClass.index;
    final classB = b.geom.edge.roadClass.index;
    if (classA != classB) return classA < classB;
    if ((a.score - b.score).abs() > _tieDeg) return a.score < b.score;
    return a.tieBreaksBefore(b);
  }

  // ------------------------------------------------------- mid-edge turns

  /// A real road is one long edge with crossings inside it, so there is no
  /// edge end to hand the choice to. When the driver has turned more than the
  /// road can explain, look for a crossing road that points where they are
  /// now heading and move onto it.
  void _relockAfterTurn() {
    final g = _graph;
    final from = _geom;
    if (g == null || from == null) return;
    if (_unexplained.abs() < config.turnYawThresholdDeg) return;
    final here = from.pointAt(_seg, _along);
    final heading = _heading();
    final desired = heading + _unexplained;
    _Pick? best;
    final near = g.nearby(here.lat, here.lon,
        radiusM: config.turnRelockRadiusM,
        limit: config.candidateLimit,
        vehicle: vehicle);
    for (final p in near) {
      if (p.edgeId == from.edge.id) continue;
      final geom = _geomOf(p.edgeId);
      if (geom == null) continue;
      for (final forward in _legalDirections(geom)) {
        final ahead = forward ? geom.length - p.alongM : p.alongM;
        if (ahead < config.minExitLengthM) continue;
        final bearing = _bearingOf(p, forward);
        final off = NavMath.angleDiffDeg(bearing, desired).abs();
        if (off > config.turnRelockHeadingTolDeg) continue;
        final pick = _Pick(geom, p.alongM, forward, bearing,
            p.perpendicularM + config.headingWeightMPerDeg * off);
        if (pick.beats(best)) best = pick;
      }
    }
    if (best == null) return;
    _enter(best);
    _charge(NavMath.angleDiffDeg(_heading(), heading));
  }

  // --------------------------------------------------------------- helpers

  _Geom? _geomOf(int edgeId) {
    final cached = _geoms[edgeId];
    if (cached != null) return cached;
    final edge = _graph?.edge(edgeId);
    if (edge == null) return null;
    return _geoms[edgeId] = _Geom.of(edge);
  }

  static List<bool> _legalDirections(_Geom g) =>
      g.edge.oneWay ? const [true] : const [true, false];

  static double _bearingOf(EdgeProjection p, bool forward) => NavMath.wrap360(
      p.headingRad * NavMath.radToDeg + (forward ? 0.0 : 180.0));

  double _heading() =>
      NavMath.wrap360(_geom!.bearing[_seg] + (_forward ? 0.0 : 180.0));
}
