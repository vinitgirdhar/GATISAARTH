import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';
import '../nav_config.dart';
import 'road_graph.dart';

/// A tunnel on the road ahead (or the one the vehicle is in).
@immutable
class TunnelAhead {
  const TunnelAhead({
    required this.distanceM,
    required this.lengthM,
    required this.remainingM,
    required this.inside,
    required this.exitLat,
    required this.exitLon,
    this.name,
  });

  /// Straight-line distance to the entry portal; 0 once inside.
  final double distanceM;

  /// Portal to portal along the road.
  final double lengthM;

  /// Tunnel still to drive: [lengthM] before entry, less once inside.
  final double remainingM;
  final bool inside;

  /// The portal the vehicle will come out of.
  final double exitLat;
  final double exitLon;
  final String? name;
}

/// Finds tunnels on the road ahead in the phone's own road graph (the
/// `is_tunnel` flag the offline map packs carry).
///
/// Consecutive tunnel edges that touch end to end are one tunnel. A tunnel is
/// "ahead" when its nearer portal lies within [TunnelConfig.lookaheadM], in
/// front of the vehicle, and the tunnel runs the way the vehicle is heading.
/// Pure geometry: it never moves the position.
class TunnelLookahead {
  TunnelLookahead({NavConfig config = NavConfig.defaults}) : _c = config.tunnel;

  final TunnelConfig _c;
  RoadGraph? _indexed;
  List<_Tunnel> _tunnels = const [];

  TunnelAhead? find(
    RoadGraph graph, {
    required double lat,
    required double lon,
    required double headingDeg,
  }) {
    if (!identical(graph, _indexed)) {
      _indexed = graph;
      _tunnels = _collect(graph);
    }
    TunnelAhead? best;
    for (final t in _tunnels) {
      final hit = _check(t, lat, lon, headingDeg);
      if (hit != null && (best == null || hit.distanceM < best.distanceM)) {
        best = hit;
      }
    }
    return best;
  }

  TunnelAhead? _check(_Tunnel t, double lat, double lon, double headingDeg) {
    // Inside: within the corridor of one of its edges.
    for (final e in t.edges) {
      final p = _project(e, lat, lon);
      if (p.perpendicularM > _c.insideCorridorM) continue;
      final along = t.offsetM[e.id]! + p.alongM;
      // Which way through: compare the heading with the tunnel direction here.
      final forward =
          NavMath.angleDiffDeg(headingDeg, p.headingDeg).abs() <= 90;
      return TunnelAhead(
        distanceM: 0,
        lengthM: t.lengthM,
        remainingM: forward ? t.lengthM - along : along,
        inside: true,
        exitLat: forward ? t.endLat : t.startLat,
        exitLon: forward ? t.endLon : t.startLon,
        name: t.name,
      );
    }
    TunnelAhead? best;
    for (final entryAtStart in [true, false]) {
      final pLat = entryAtStart ? t.startLat : t.endLat;
      final pLon = entryAtStart ? t.startLon : t.endLon;
      final d = NavMath.nedBetween(
          lat0: lat, lon0: lon, alt0: 0, lat1: pLat, lon1: pLon, alt1: 0);
      final distance = math.sqrt(d.x * d.x + d.y * d.y);
      if (distance > _c.lookaheadM) continue;
      final bearing = math.atan2(d.y, d.x) * NavMath.radToDeg;
      if (NavMath.angleDiffDeg(bearing, headingDeg).abs() >
          _c.bearingToleranceDeg) {
        continue;
      }
      final into = entryAtStart ? t.startHeadingDeg : t.endHeadingDeg + 180;
      if (NavMath.angleDiffDeg(into, headingDeg).abs() > _c.alignToleranceDeg) {
        continue;
      }
      if (best == null || distance < best.distanceM) {
        best = TunnelAhead(
          distanceM: distance,
          lengthM: t.lengthM,
          remainingM: t.lengthM,
          inside: false,
          exitLat: entryAtStart ? t.endLat : t.startLat,
          exitLon: entryAtStart ? t.endLon : t.startLon,
          name: t.name,
        );
      }
    }
    return best;
  }

  /// Chains touching tunnel edges into tunnels, oriented along the chain.
  List<_Tunnel> _collect(RoadGraph graph) {
    final pieces = [
      for (final e in graph.edges)
        if (e.tunnel) e
    ];
    final used = <int>{};
    final tunnels = <_Tunnel>[];
    for (final seed in pieces) {
      if (used.contains(seed.id)) continue;
      used.add(seed.id);
      // Segments as (edge, reversed?) in driving order.
      final chain = <({RoadEdge e, bool rev})>[(e: seed, rev: false)];
      bool extend(bool atEnd) {
        final tip = atEnd ? chain.last : chain.first;
        final tipLat = atEnd ? _endLat(tip) : _startLat(tip);
        final tipLon = atEnd ? _endLon(tip) : _startLon(tip);
        for (final e in pieces) {
          if (used.contains(e.id)) continue;
          for (final rev in [false, true]) {
            final seg = (e: e, rev: rev);
            final jLat = atEnd ? _startLat(seg) : _endLat(seg);
            final jLon = atEnd ? _startLon(seg) : _endLon(seg);
            if (NavMath.horizontalDistance(
                    lat0: tipLat, lon0: tipLon, lat1: jLat, lon1: jLon) <=
                _c.joinM) {
              used.add(e.id);
              atEnd ? chain.add(seg) : chain.insert(0, seg);
              return true;
            }
          }
        }
        return false;
      }

      while (extend(true)) {}
      while (extend(false)) {}
      final length = chain.fold<double>(0, (s, c) => s + c.e.lengthM);
      if (length < _c.minLengthM) continue;
      final offsets = <int, double>{};
      var run = 0.0;
      for (final c in chain) {
        // Offsets are measured from the chain start in the edge's own
        // direction; a reversed piece is entered from its far end.
        offsets[c.e.id] = c.rev ? run + c.e.lengthM : run;
        run += c.e.lengthM;
      }
      tunnels.add(_Tunnel(
        edges: [for (final c in chain) c.e],
        reversed: {for (final c in chain) c.e.id: c.rev},
        offsetM: offsets,
        lengthM: length,
        startLat: _startLat(chain.first),
        startLon: _startLon(chain.first),
        endLat: _endLat(chain.last),
        endLon: _endLon(chain.last),
        startHeadingDeg: _segmentHeading(chain.first, atStart: true),
        endHeadingDeg: _segmentHeading(chain.last, atStart: false),
        name: chain.map((c) => c.e.name).whereType<String>().firstOrNull,
      ));
    }
    return tunnels;
  }

  static double _startLat(({RoadEdge e, bool rev}) s) =>
      s.rev ? s.e.latAt(s.e.pointCount - 1) : s.e.latAt(0);
  static double _startLon(({RoadEdge e, bool rev}) s) =>
      s.rev ? s.e.lonAt(s.e.pointCount - 1) : s.e.lonAt(0);
  static double _endLat(({RoadEdge e, bool rev}) s) =>
      s.rev ? s.e.latAt(0) : s.e.latAt(s.e.pointCount - 1);
  static double _endLon(({RoadEdge e, bool rev}) s) =>
      s.rev ? s.e.lonAt(0) : s.e.lonAt(s.e.pointCount - 1);

  /// Driving direction (deg, clockwise from north) at the chain's start or end.
  static double _segmentHeading(({RoadEdge e, bool rev}) s,
      {required bool atStart}) {
    final e = s.e;
    final last = e.pointCount - 1;
    // First or last vertex pair of the edge in its stored direction.
    final useHead = atStart != s.rev;
    final i0 = useHead ? 0 : last - 1, i1 = useHead ? 1 : last;
    final d = NavMath.nedBetween(
        lat0: e.latAt(i0),
        lon0: e.lonAt(i0),
        alt0: 0,
        lat1: e.latAt(i1),
        lon1: e.lonAt(i1),
        alt1: 0);
    final h = math.atan2(d.y, d.x) * NavMath.radToDeg;
    return s.rev ? h + 180 : h;
  }

  /// Perpendicular distance, distance along (in the chain's direction for
  /// this edge) and the chain's heading at the projection.
  ({double perpendicularM, double alongM, double headingDeg}) _project(
      RoadEdge e, double lat, double lon) {
    final t = _tunnels.firstWhere((t) => t.offsetM.containsKey(e.id));
    final rev = t.reversed[e.id]!;
    var bestPerp = double.infinity, bestAlong = 0.0, bestHeading = 0.0;
    var run = 0.0;
    for (var i = 0; i + 1 < e.pointCount; i++) {
      final a = NavMath.nedBetween(
          lat0: e.latAt(i), lon0: e.lonAt(i), alt0: 0, lat1: lat, lon1: lon, alt1: 0);
      final b = NavMath.nedBetween(
          lat0: e.latAt(i),
          lon0: e.lonAt(i),
          alt0: 0,
          lat1: e.latAt(i + 1),
          lon1: e.lonAt(i + 1),
          alt1: 0);
      final len2 = b.x * b.x + b.y * b.y;
      final len = math.sqrt(len2);
      final u = len2 == 0 ? 0.0 : ((a.x * b.x + a.y * b.y) / len2).clamp(0.0, 1.0);
      final px = a.x - u * b.x, py = a.y - u * b.y;
      final perp = math.sqrt(px * px + py * py);
      if (perp < bestPerp) {
        bestPerp = perp;
        bestAlong = run + u * len;
        bestHeading = math.atan2(b.y, b.x) * NavMath.radToDeg;
      }
      run += len;
    }
    return (
      perpendicularM: bestPerp,
      alongM: rev ? -bestAlong : bestAlong,
      headingDeg: rev ? bestHeading + 180 : bestHeading,
    );
  }
}

class _Tunnel {
  const _Tunnel({
    required this.edges,
    required this.reversed,
    required this.offsetM,
    required this.lengthM,
    required this.startLat,
    required this.startLon,
    required this.endLat,
    required this.endLon,
    required this.startHeadingDeg,
    required this.endHeadingDeg,
    this.name,
  });

  final List<RoadEdge> edges;
  final Map<int, bool> reversed;

  /// Chain distance at which each edge's own polyline starts (for a reversed
  /// edge: where its stored end sits), so offset + along = distance into the
  /// tunnel.
  final Map<int, double> offsetM;
  final double lengthM;
  final double startLat, startLon, endLat, endLon;
  final double startHeadingDeg, endHeadingDeg;
  final String? name;
}
