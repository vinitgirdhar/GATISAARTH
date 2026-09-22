import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';
import '../nav_config.dart';
import 'road_graph.dart';

/// One road the vehicle might be on, with how likely it is (§21).
@immutable
class MapMatchCandidate {
  const MapMatchCandidate({
    required this.edgeId,
    required this.lat,
    required this.lon,
    required this.roadHeadingRad,
    required this.perpendicularM,
    required this.alongM,
    required this.posterior,
    required this.corridorPolyline,
    this.roadName,
    this.tunnel = false,
  });

  final int edgeId;
  final double lat;
  final double lon;

  /// Direction of travel along the road at the matched point, already flipped
  /// to whichever way the vehicle is actually going on a two-way road.
  final double roadHeadingRad;

  final double perpendicularM;
  final double alongM;

  /// Normalised over the candidates of this step. This is a *relative*
  /// likelihood among the roads considered, not a probability that the
  /// vehicle is on a road at all.
  final double posterior;

  /// Full geometry of this candidate road, as flat latitude/longitude pairs.
  /// The UI draws the leading candidates as separate uncertainty corridors
  /// instead of collapsing an ambiguous fork into one authoritative line.
  final List<double> corridorPolyline;

  final String? roadName;
  final bool tunnel;

  double get roadHeadingDeg =>
      NavMath.wrap360(roadHeadingRad * NavMath.radToDeg);
}

/// Result of one match step.
@immutable
class MapMatchResult {
  const MapMatchResult({
    required this.candidates,
    required this.snapped,
    this.matchedLat,
    this.matchedLon,
    this.matchedHeadingRad,
    this.confidence = 0,
    this.reason = '',
  });

  /// Best first, at most `MapMatchConfig.maxCandidates`.
  final List<MapMatchCandidate> candidates;

  /// True only when the matcher is confident enough to move the position
  /// onto a road (§19).
  final bool snapped;

  final double? matchedLat;
  final double? matchedLon;
  final double? matchedHeadingRad;

  /// Posterior of the leading candidate.
  final double confidence;

  /// Why it did or did not snap — shown in diagnostics rather than leaving a
  /// driver wondering.
  final String reason;

  MapMatchCandidate? get best => candidates.isEmpty ? null : candidates.first;
}

class _Hypothesis {
  _Hypothesis({
    required this.projection,
    required this.logProb,
    required this.age,
  });

  final EdgeProjection projection;
  double logProb;
  int age;
}

/// Hidden-Markov-model map matching, Newson-Krumm style (§19, §20, §21).
///
/// Emission: how far the estimate is from the road, scaled by the *filter's
/// own* uncertainty rather than a fixed constant — a 40 m sigma should not
/// rule out a road 30 m away, and a 3 m sigma should.
///
/// Transition: how far the vehicle would have had to drive along the network
/// versus how far it actually moved. A jump to a parallel carriageway needs a
/// long detour through a junction, which is what separates it from the road
/// the vehicle is really on.
///
/// It refuses to snap unless the leading candidate both clears an absolute
/// threshold and beats the runner-up by a margin. Parallel roads, flyovers and
/// service roads are exactly where a single confident-looking candidate is
/// wrong, and a wrong snap is worse than none.
class MapMatcher {
  MapMatcher({
    required this.graph,
    NavConfig config = NavConfig.defaults,
    this.vehicle = VehicleAccess.cars,
  }) : _config = config.mapMatch;

  RoadGraph graph;
  final MapMatchConfig _config;
  VehicleAccess vehicle;

  List<_Hypothesis> _hypotheses = [];
  double? _lastLat;
  double? _lastLon;
  MapMatchResult? _last;

  MapMatchResult? get last => _last;

  /// True when this matcher can say anything at all. With no road graph it
  /// reports unavailable rather than guessing (§83).
  bool get isAvailable => !graph.isEmpty;

  /// Swaps the road network the matcher works on (roads are read from the
  /// installed map as the vehicle moves). The hypotheses belonged to the old
  /// graph's edge ids, so they are dropped; matching restarts from the next
  /// position.
  void useGraph(RoadGraph next) {
    if (identical(next, graph)) return;
    graph = next;
    reset();
  }

  void reset() {
    _hypotheses = [];
    _lastLat = null;
    _lastLon = null;
    _last = null;
  }

  /// Matches one fused position.
  ///
  /// [sigmaM] is the filter's horizontal uncertainty; [headingRad] the
  /// direction of travel, or null when the vehicle is too slow for heading to
  /// mean anything.
  MapMatchResult? update({
    required double lat,
    required double lon,
    required double sigmaM,
    double? headingRad,
    double? speedMps,
  }) {
    if (!isAvailable) return null;
    if (!lat.isFinite || !lon.isFinite) return null;

    // Search wider when the estimate is vaguer, but never unboundedly.
    final radius = (_config.searchRadius + 2 * sigmaM)
        .clamp(_config.searchRadius, _config.searchRadius * 5);
    final projections = graph.nearby(
      lat,
      lon,
      radiusM: radius,
      limit: _config.maxCandidates,
      vehicle: vehicle,
    );

    if (projections.isEmpty) {
      _hypotheses = [];
      _lastLat = lat;
      _lastLon = lon;
      _last = const MapMatchResult(
        candidates: [],
        snapped: false,
        reason: 'No road within the search radius',
      );
      return _last;
    }

    final straightMoved = (_lastLat == null || _lastLon == null)
        ? null
        : NavMath.horizontalDistance(
            lat0: _lastLat!,
            lon0: _lastLon!,
            lat1: lat,
            lon1: lon,
          );

    final next = <_Hypothesis>[];
    for (final projection in projections) {
      final emission = _emissionLogProb(
        projection: projection,
        sigmaM: sigmaM,
        headingRad: headingRad,
        speedMps: speedMps,
      );
      if (emission == null) continue;

      double bestPrior = 0;
      var age = 1;
      if (_hypotheses.isNotEmpty && straightMoved != null) {
        bestPrior = double.negativeInfinity;
        for (final previous in _hypotheses) {
          final transition = _transitionLogProb(
            from: previous.projection,
            to: projection,
            straightMoved: straightMoved,
          );
          if (transition == null) continue;
          final total = previous.logProb + transition;
          if (total > bestPrior) {
            bestPrior = total;
            age = previous.age + 1;
          }
        }
        // Every transition was implausible: the vehicle cannot have got here
        // from any road it was on. Restart this candidate rather than
        // propagate a contradiction.
        if (!bestPrior.isFinite) {
          bestPrior = _config.transitionBeta * -1;
          age = 1;
        }
      }
      next.add(_Hypothesis(
        projection: projection,
        logProb: bestPrior + emission,
        age: age,
      ));
    }

    if (next.isEmpty) {
      _hypotheses = [];
      _lastLat = lat;
      _lastLon = lon;
      _last = const MapMatchResult(
        candidates: [],
        snapped: false,
        reason: 'No candidate road was compatible with the heading',
      );
      return _last;
    }

    next.sort((a, b) => b.logProb.compareTo(a.logProb));
    // Keep the window bounded, and stop log-probabilities running away.
    final kept = next.length <= _config.maxCandidates
        ? next
        : next.sublist(0, _config.maxCandidates);
    final top = kept.first.logProb;
    for (final h in kept) {
      h.logProb -= top;
      if (h.age > _config.windowSize) h.age = _config.windowSize;
    }
    _hypotheses = kept;
    _lastLat = lat;
    _lastLon = lon;

    final posteriors = _softmax(kept.map((h) => h.logProb).toList());
    final candidates = <MapMatchCandidate>[];
    for (var i = 0; i < kept.length; i++) {
      final p = kept[i].projection;
      final edge = graph.edge(p.edgeId)!;
      candidates.add(MapMatchCandidate(
        edgeId: p.edgeId,
        lat: p.lat,
        lon: p.lon,
        roadHeadingRad: _travelHeading(p, edge, headingRad),
        perpendicularM: p.perpendicularM,
        alongM: p.alongM,
        posterior: posteriors[i],
        corridorPolyline: List<double>.unmodifiable(edge.polyline),
        roadName: edge.name,
        tunnel: edge.tunnel,
      ));
    }

    _last = _decide(candidates, kept.first.age, sigmaM);
    return _last;
  }

  MapMatchResult _decide(
      List<MapMatchCandidate> candidates, int age, double sigmaM) {
    final best = candidates.first;

    // A graph read from map tiles is cut at every junction, so one physical
    // road is a chain of edges and a position near a cut fits both sides of it
    // equally well. They are one road, not rivals: their probability is
    // pooled, and the runner-up is sought among genuinely different roads.
    var road = best.posterior;
    var runnerUp = 0.0;
    var rivals = 0;
    for (final other in candidates.skip(1)) {
      if (_continues(best, other)) {
        road += other.posterior;
      } else {
        rivals++;
        runnerUp = math.max(runnerUp, other.posterior);
      }
    }
    final margin = road - runnerUp;

    // Ambiguity is checked before strength, because "two roads, cannot
    // tell them apart" is the more useful thing to say when it is true.
    if (rivals > 0 && margin < _config.runnerUpMargin) {
      return MapMatchResult(
        candidates: candidates,
        snapped: false,
        confidence: road,
        reason: 'Two roads are too close to call '
            '(${(margin * 100).round()} % apart)',
      );
    }
    if (road < _config.snapThreshold) {
      return MapMatchResult(
        candidates: candidates,
        snapped: false,
        confidence: road,
        reason: 'Leading road only ${(road * 100).round()} % likely',
      );
    }
    // The posterior is a softmax over the roads considered, so one lone
    // road always scores 1.0 however far away it is. Whether the vehicle is
    // plausibly on a road at all is a separate question, and this is it.
    final distanceLimit = _config.maxSnapDistanceSigma * math.max(sigmaM, 3.0);
    if (best.perpendicularM > distanceLimit) {
      return MapMatchResult(
        candidates: candidates,
        snapped: false,
        confidence: road,
        reason: '${best.perpendicularM.toStringAsFixed(0)} m from the '
            'nearest road, beyond the estimate\'s own uncertainty',
      );
    }
    if (age < 2) {
      return MapMatchResult(
        candidates: candidates,
        snapped: false,
        confidence: road,
        reason: 'Waiting for a second consistent fix',
      );
    }
    return MapMatchResult(
      candidates: candidates,
      snapped: true,
      matchedLat: best.lat,
      matchedLon: best.lon,
      matchedHeadingRad: best.roadHeadingRad,
      confidence: road,
      reason: best.roadName == null ? 'Matched' : 'Matched to ${best.roadName}',
    );
  }

  /// Whether [other] is the same physical road as [best]: the same edge, or a
  /// neighbour that shares a node and carries on in nearly the same direction.
  /// A side street at a junction points elsewhere and stays a rival.
  bool _continues(MapMatchCandidate best, MapMatchCandidate other) {
    if (best.edgeId == other.edgeId) return true;
    final a = graph.edge(best.edgeId);
    final b = graph.edge(other.edgeId);
    if (a == null || b == null) return false;
    final joined = a.fromNode == b.fromNode ||
        a.fromNode == b.toNode ||
        a.toNode == b.fromNode ||
        a.toNode == b.toNode;
    if (!joined) return false;
    final turn = NavMath.wrapPi(best.roadHeadingRad - other.roadHeadingRad);
    return turn.abs() < _config.continuationDeg * NavMath.degToRad;
  }

  /// `log P(position | road)`, or null when the road is incompatible.
  double? _emissionLogProb({
    required EdgeProjection projection,
    required double sigmaM,
    double? headingRad,
    double? speedMps,
  }) {
    final edge = graph.edge(projection.edgeId);
    if (edge == null) return null;

    // Distance term, scaled by what the filter actually believes.
    final sigma = math.max(sigmaM, 3.0);
    final z = projection.perpendicularM / sigma;
    var logProb = -0.5 * z * z;

    // Heading term. Only meaningful once the vehicle is genuinely moving; a
    // parked car's heading is noise.
    if (headingRad != null && (speedMps ?? 0) > 2) {
      final delta = _headingDelta(projection, edge, headingRad);
      final tolerance = _config.headingToleranceDeg * NavMath.degToRad;
      // Perpendicular or worse is not travel along this road at all.
      if (delta > math.pi / 2 - 1e-6) return null;
      logProb += -0.5 * (delta / tolerance) * (delta / tolerance);
    }

    // Speed term: a residential street is not where 30 m/s happens. Only
    // applied when the source data actually stated a limit.
    final limit = edge.maxSpeedMps;
    if (limit != null && speedMps != null && speedMps > limit * 1.6) {
      logProb += -1.0;
    }
    return logProb;
  }

  /// `log P(road_k | road_{k-1})`, or null when no route exists.
  double? _transitionLogProb({
    required EdgeProjection from,
    required EdgeProjection to,
    required double straightMoved,
  }) {
    if (from.edgeId == to.edgeId) {
      final along = (to.alongM - from.alongM).abs();
      return -(along - straightMoved).abs() / _config.transitionBeta;
    }
    final route = graph.routeDistance(
      from,
      to,
      capM: math.max(200, straightMoved * 4 + 200),
      vehicle: vehicle,
    );
    if (route == null) return null;
    return -(route - straightMoved).abs() / _config.transitionBeta;
  }

  /// Smallest angle between the vehicle's heading and the road's direction,
  /// allowing either direction of travel on a two-way road.
  double _headingDelta(
      EdgeProjection projection, RoadEdge edge, double headingRad) {
    final forward = NavMath.wrapPi(headingRad - projection.headingRad).abs();
    if (edge.oneWay) return forward;
    final backward =
        NavMath.wrapPi(headingRad - (projection.headingRad + math.pi)).abs();
    return math.min(forward, backward);
  }

  /// The road's direction of travel, flipped to match the vehicle on a
  /// two-way road.
  double _travelHeading(
      EdgeProjection projection, RoadEdge edge, double? headingRad) {
    if (edge.oneWay || headingRad == null) return projection.headingRad;
    final forward = NavMath.wrapPi(headingRad - projection.headingRad).abs();
    final backward =
        NavMath.wrapPi(headingRad - (projection.headingRad + math.pi)).abs();
    return backward < forward
        ? NavMath.wrapPi(projection.headingRad + math.pi)
        : projection.headingRad;
  }

  static List<double> _softmax(List<double> logProbs) {
    final maxLog = logProbs.reduce(math.max);
    final exps = logProbs.map((v) => math.exp(v - maxLog)).toList();
    final total = exps.reduce((a, b) => a + b);
    if (total <= 0 || !total.isFinite) {
      return List<double>.filled(logProbs.length, 1 / logProbs.length);
    }
    return exps.map((v) => v / total).toList();
  }
}
