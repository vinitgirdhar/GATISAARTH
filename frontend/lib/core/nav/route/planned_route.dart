import 'package:flutter/foundation.dart';

import '../math/nav_math.dart';

/// What the driver does at a point on the route.
enum ManeuverKind {
  depart,
  continueOn,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
  arrive,
}

/// One instruction on a [PlannedRoute], at [atM] metres from its start.
@immutable
class RouteManeuver {
  const RouteManeuver({
    required this.kind,
    required this.atM,
    required this.lat,
    required this.lon,
    this.roadName,
  });

  final ManeuverKind kind;

  /// Metres along the route from its start.
  final double atM;
  final double lat;
  final double lon;

  /// The road driven after this maneuver, when the map names it.
  final String? roadName;

  /// Short driver-facing text, e.g. "Turn left onto Hill Road".
  String get instruction {
    final onto = roadName == null || roadName!.trim().isEmpty
        ? ''
        : ' onto ${roadName!.trim()}';
    return switch (kind) {
      ManeuverKind.depart => roadName == null || roadName!.trim().isEmpty
          ? 'Head out'
          : 'Head out on ${roadName!.trim()}',
      ManeuverKind.continueOn => 'Continue$onto',
      ManeuverKind.slightLeft => 'Keep left$onto',
      ManeuverKind.left => 'Turn left$onto',
      ManeuverKind.sharpLeft => 'Sharp left$onto',
      ManeuverKind.slightRight => 'Keep right$onto',
      ManeuverKind.right => 'Turn right$onto',
      ManeuverKind.sharpRight => 'Sharp right$onto',
      ManeuverKind.uTurn => 'Make a U-turn$onto',
      ManeuverKind.arrive => 'Arrive at destination',
    };
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'atM': atM,
        'lat': lat,
        'lon': lon,
        if (roadName != null) 'road': roadName,
      };

  static RouteManeuver fromJson(Map<String, dynamic> json) => RouteManeuver(
        kind: ManeuverKind.values.byName(json['kind'] as String),
        atM: (json['atM'] as num).toDouble(),
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        roadName: json['road'] as String?,
      );
}

/// A stretch of the route, e.g. a tunnel, in metres from the start.
@immutable
class RouteSpan {
  const RouteSpan(this.fromM, this.toM);

  final double fromM;
  final double toM;

  Map<String, dynamic> toJson() => {'from': fromM, 'to': toM};

  static RouteSpan fromJson(Map<String, dynamic> json) => RouteSpan(
        (json['from'] as num).toDouble(),
        (json['to'] as num).toDouble(),
      );
}

/// A route computed on the phone from the offline road graph.
///
/// Everything navigation needs once the journey has started lives here, so
/// the drive carries on with no network and no map lookups: the geometry,
/// the turn list and the tunnels. Serialisable, so a journey survives the app
/// being killed.
class PlannedRoute {
  PlannedRoute({
    required List<double> polyline,
    required this.maneuvers,
    required this.durationS,
    this.tunnels = const [],
  })  : assert(polyline.length >= 4 && polyline.length.isEven),
        polyline = List.unmodifiable(polyline),
        cumM = _cumulative(polyline);

  /// Flat `[lat0, lon0, lat1, lon1, ...]` from start to destination.
  final List<double> polyline;

  /// Metres from the start to each vertex; `cumM.last` is [lengthM]. Same
  /// per-segment formula as `RoadEdge.lengthM`.
  final Float64List cumM;

  /// First is [ManeuverKind.depart], last is [ManeuverKind.arrive].
  final List<RouteManeuver> maneuvers;

  /// Estimated driving time for the whole route (s).
  final double durationS;

  final List<RouteSpan> tunnels;

  double get lengthM => cumM.last;
  int get pointCount => polyline.length ~/ 2;
  double latAt(int i) => polyline[i * 2];
  double lonAt(int i) => polyline[i * 2 + 1];

  Map<String, dynamic> toJson() => {
        'v': 1,
        'polyline': polyline,
        'maneuvers': [for (final m in maneuvers) m.toJson()],
        'durationS': durationS,
        'tunnels': [for (final t in tunnels) t.toJson()],
      };

  /// Null on anything malformed: a half-read route is worse than none.
  static PlannedRoute? fromJson(Map<String, dynamic> json) {
    try {
      final polyline = [
        for (final v in json['polyline'] as List<dynamic>) (v as num).toDouble()
      ];
      if (polyline.length < 4 ||
          polyline.length.isOdd ||
          polyline.any((v) => !v.isFinite)) {
        return null;
      }
      return PlannedRoute(
        polyline: polyline,
        maneuvers: [
          for (final m in json['maneuvers'] as List<dynamic>)
            RouteManeuver.fromJson(m as Map<String, dynamic>)
        ],
        durationS: (json['durationS'] as num).toDouble(),
        tunnels: [
          for (final t in (json['tunnels'] as List<dynamic>? ?? const []))
            RouteSpan.fromJson(t as Map<String, dynamic>)
        ],
      );
    } catch (_) {
      return null;
    }
  }

  static Float64List _cumulative(List<double> p) {
    final n = p.length ~/ 2;
    final cum = Float64List(n);
    for (var i = 1; i < n; i++) {
      cum[i] = cum[i - 1] +
          NavMath.horizontalDistance(
            lat0: p[(i - 1) * 2],
            lon0: p[(i - 1) * 2 + 1],
            lat1: p[i * 2],
            lon1: p[i * 2 + 1],
          );
    }
    return cum;
  }
}
