import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/nav/map/road_follower.dart';
import '../../../../core/nav/map/road_graph.dart' show RoadGraph;
import '../../../../core/platform/maps/pack_road_source.dart';

/// How far from the road a position may be and still be put on it.
///
/// A GNSS fix is good to a few metres; more than this away the vehicle is
/// probably on a road the map does not have, and pinning it to the nearest
/// one would be worse than leaving it alone.
const double _lockRadiusM = 40;

/// After a load found no roads, how long before asking again. Short: the map
/// packs are opened a moment after the app starts, and a pack can be downloaded
/// at any time.
const Duration _retryAfterEmpty = Duration(seconds: 10);

/// Keeps the dead-reckoned position on the roads of the installed offline map.
///
/// Dead reckoning knows how far the vehicle went and roughly which way, and
/// nothing about streets, so left alone the marker drifts across buildings.
/// This puts it on the road the vehicle was last seen on and advances it along
/// that road by the distance travelled; the roads come from the same offline
/// vector tiles that draw the map, so the marker follows exactly the drawn
/// streets, anywhere a map pack is installed.
///
/// Everything is optional: with no source, no roads there, or no road near the
/// vehicle, [advance] returns null and the caller falls back to plain heading
/// integration - the app is never worse off than without this.
class RoadConstraint {
  RoadConstraint({
    RoadGraphSource? source,
    RoadFollower? follower,
    DateTime Function()? clock,
  })  : _source = source,
        _follower = follower ?? RoadFollower(),
        _clock = clock ?? DateTime.now;

  final RoadGraphSource? _source;
  final RoadFollower _follower;
  final DateTime Function() _clock;

  /// Called after new roads arrive, so a session already in an outage can lock
  /// onto them instead of waiting for the next one.
  VoidCallback? onRoadsChanged;

  RoadCoverage? _coverage;
  bool _loading = false;
  bool _disposed = false;
  DateTime? _retryAt;
  double _yawDeg = 0;

  bool get isLocked => _follower.isLocked;

  /// The roads around the vehicle, or null while none are loaded.
  RoadGraph? get graph => _follower.graph;
  RoadPosition? get position => _follower.position;

  /// Loads the roads around a position when they are not loaded already. Cheap
  /// to call on every tick: it only does work once the vehicle leaves the
  /// covered area, and never runs two loads at once.
  void watch(double lat, double lon) {
    final source = _source;
    if (source == null || _loading || _disposed) return;
    final retryAt = _retryAt;
    if (retryAt != null && _clock().isBefore(retryAt)) return;
    if (_coverage?.containsSafe(lat, lon) ?? false) return;
    _loading = true;
    unawaited(_load(source, lat, lon));
  }

  Future<void> _load(RoadGraphSource source, double lat, double lon) async {
    try {
      final coverage = await source.roadsAround(lat, lon);
      if (_disposed) return;
      _coverage = coverage;
      _retryAt = coverage == null ? _clock().add(_retryAfterEmpty) : null;
      // Rebinding keeps the follower on the same road (new edge ids).
      _follower.graph = coverage?.graph;
      onRoadsChanged?.call();
    } catch (e) {
      debugPrint('[RoadConstraint] roads not loaded: $e');
      _retryAt = _clock().add(_retryAfterEmpty);
    } finally {
      _loading = false;
    }
  }

  /// Puts the vehicle on the road nearest to a position, facing [headingDeg]
  /// when that is known. Returns where it landed, or null when no road is
  /// close. A failed lock lets go of the road held before it, unless
  /// [keepIfFails]: that road may be the right one after all.
  RoadPosition? lock(
    double lat,
    double lon, {
    double? headingDeg,
    bool keepIfFails = false,
  }) {
    final locked = _follower.lock(
      lat: lat,
      lon: lon,
      headingDeg: headingDeg,
      maxRadiusM: _lockRadiusM,
    );
    if (locked) {
      _yawDeg = 0;
    } else if (!keepIfFails) {
      release();
    }
    return locked ? _follower.position : null;
  }

  void release() {
    _follower.release();
    _yawDeg = 0;
  }

  /// Turning since the last [advance] (compass degrees, clockwise positive).
  /// The follower uses it to choose a side street when the vehicle turned.
  void addYaw(double degrees) {
    if (_follower.isLocked && degrees.isFinite) _yawDeg += degrees;
  }

  /// Moves [meters] along the road. Null when not on one. A simulated drive
  /// ([simulated]) turns round at a dead end instead of stopping there.
  RoadPosition? advance(double meters, {bool simulated = false}) {
    if (!_follower.isLocked) return null;
    final yaw = _yawDeg;
    _yawDeg = 0;
    _follower.advance(meters, yawDeg: yaw, reverseAtDeadEnd: simulated);
    return _follower.position;
  }

  /// Nudges the along-road position toward a noisy fix. False when the fix is
  /// too far from this road to say anything about where on it the vehicle is.
  bool correct(double lat, double lon, {required double sigmaM}) =>
      _follower.correct(lat, lon, sigmaM: sigmaM);

  void dispose() => _disposed = true;
}
