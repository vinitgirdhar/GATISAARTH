import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/map/tile_roads.dart';

import 'road_follower_fixtures.dart' show pointAt;

export 'road_follower_fixtures.dart' show pointAt, originLat, originLon;

/// A `TileRoadLine` through `[north, east]` metre points from the shared test
/// origin — real graphs are built through `buildRoadGraph`/`nodeRoads` so
/// junction sharing is genuine, unlike the raw-edge fixtures in
/// `road_follower_fixtures.dart` (which don't need it, since `RoadFollower` is
/// geometry-only and never reads a node id).
TileRoadLine tileRoad(
  List<List<double>> pts, {
  RoadClass roadClass = RoadClass.residential,
  bool oneWay = false,
  bool tunnel = false,
  String? name,
}) =>
    TileRoadLine(
      latLon: [for (final p in pts) ...pointAt(p[0], p[1])],
      roadClass: roadClass,
      oneWay: oneWay,
      tunnel: tunnel,
      name: name,
    );

RoadGraph routeGraph(List<TileRoadLine> lines) => buildRoadGraph(lines)!;
