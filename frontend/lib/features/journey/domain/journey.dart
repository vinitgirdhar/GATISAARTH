import 'package:flutter/foundation.dart';

import '../../../core/nav/route/planned_route.dart';

/// A start or destination the driver chose.
@immutable
class JourneyPlace {
  const JourneyPlace({
    required this.name,
    required this.lat,
    required this.lon,
    this.isCurrentLocation = false,
  });

  final String name;
  final double lat;
  final double lon;

  /// "Your location": resolved from the live session when the route is
  /// planned, not stored as a fixed point.
  final bool isCurrentLocation;

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lon': lon,
        if (isCurrentLocation) 'current': true,
      };

  static JourneyPlace fromJson(Map<String, dynamic> json) => JourneyPlace(
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        isCurrentLocation: json['current'] == true,
      );
}

/// The box a downloaded journey corridor pack covers, so [Journey.fromJson]
/// can hand it straight to `OfflineMapService.addPacks` on [restore] without
/// re-deriving it from the route.
@immutable
class CorridorBox {
  const CorridorBox({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.maxZoom,
  });

  final double south, west, north, east;
  final int maxZoom;

  Map<String, dynamic> toJson() => {
        'south': south,
        'west': west,
        'north': north,
        'east': east,
        'maxZoom': maxZoom,
      };

  static CorridorBox fromJson(Map<String, dynamic> json) => CorridorBox(
        south: (json['south'] as num).toDouble(),
        west: (json['west'] as num).toDouble(),
        north: (json['north'] as num).toDouble(),
        east: (json['east'] as num).toDouble(),
        maxZoom: (json['maxZoom'] as num).toInt(),
      );
}

/// A planned journey and everything cached for it.
@immutable
class Journey {
  const Journey({
    required this.from,
    required this.to,
    required this.route,
    required this.createdAt,
    this.corridorPackId,
    this.corridorPackBox,
  });

  final JourneyPlace from;
  final JourneyPlace to;
  final PlannedRoute route;
  final DateTime createdAt;

  /// Id of the map pack downloaded just for this journey, when no installed
  /// pack covered it.
  final String? corridorPackId;

  /// That pack's own box, so it can be re-registered with the map service on
  /// restart. Set whenever [corridorPackId] is.
  final CorridorBox? corridorPackBox;

  Journey copyWith({PlannedRoute? route}) => Journey(
        from: from,
        to: to,
        route: route ?? this.route,
        createdAt: createdAt,
        corridorPackId: corridorPackId,
        corridorPackBox: corridorPackBox,
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'from': from.toJson(),
        'to': to.toJson(),
        'route': route.toJson(),
        'createdAt': createdAt.toIso8601String(),
        if (corridorPackId != null) 'corridorPack': corridorPackId,
        if (corridorPackBox != null) 'corridorBox': corridorPackBox!.toJson(),
      };

  /// Null on anything malformed.
  static Journey? fromJson(Map<String, dynamic> json) {
    try {
      final route =
          PlannedRoute.fromJson(json['route'] as Map<String, dynamic>);
      if (route == null) return null;
      return Journey(
        from: JourneyPlace.fromJson(json['from'] as Map<String, dynamic>),
        to: JourneyPlace.fromJson(json['to'] as Map<String, dynamic>),
        route: route,
        createdAt: DateTime.parse(json['createdAt'] as String),
        corridorPackId: json['corridorPack'] as String?,
        corridorPackBox: json['corridorBox'] != null
            ? CorridorBox.fromJson(json['corridorBox'] as Map<String, dynamic>)
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}
