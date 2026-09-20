import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' show LatLng;

/// How a stretch of the track was obtained. The map draws the two differently:
/// a solid line where a satellite fix backed the position, a dashed one where
/// the position was dead-reckoned.
enum TrailKind { gnss, deadReckoning }

/// A run of consecutive positions of one [TrailKind].
@immutable
class TrailSegment {
  const TrailSegment(this.kind, this.points);

  final TrailKind kind;
  final List<LatLng> points;
}

/// The path the vehicle has taken since the app started (or since it was last
/// cleared), thinned to one point every [minStepMeters] and capped at
/// [maxPoints] so it can never grow without bound.
///
/// Consecutive segments share their joining point, so the line has no gap where
/// the source changes from GNSS to dead reckoning and back.
class TrackTrail extends ChangeNotifier {
  TrackTrail({this.minStepMeters = 4, this.maxPoints = 4000})
      : assert(minStepMeters > 0),
        assert(maxPoints >= 2);

  final double minStepMeters;
  final int maxPoints;

  final List<_MutableSegment> _segments = [];
  List<TrailSegment>? _snapshot;
  int _pointCount = 0;

  /// Number of points held.
  int get length => _pointCount;
  bool get isEmpty => _pointCount == 0;

  /// The segments, oldest first. Unmodifiable and stable until the trail next
  /// changes, so a widget can compare it by identity.
  List<TrailSegment> get segments => _snapshot ??= List.unmodifiable([
        for (final s in _segments)
          if (s.points.length >= 2)
            TrailSegment(s.kind, List.unmodifiable(s.points)),
      ]);

  /// Adds a position. Returns whether it was kept (it is dropped when the
  /// vehicle has not moved [minStepMeters] since the last kept point).
  bool add(double latitude, double longitude, TrailKind kind) {
    final point = LatLng(latitude, longitude);
    if (_segments.isNotEmpty) {
      final last = _segments.last.points.last;
      if (_metres(last, point) < minStepMeters) return false;
    }
    if (_segments.isEmpty || _segments.last.kind != kind) {
      // Start the new run at the previous run's last point: no visible gap.
      final seed = _segments.isEmpty ? null : _segments.last.points.last;
      _segments.add(_MutableSegment(kind, [if (seed != null) seed]));
      if (seed != null) _pointCount++;
    }
    _segments.last.points.add(point);
    _pointCount++;
    _trim();
    _snapshot = null;
    notifyListeners();
    return true;
  }

  void clear() {
    if (_segments.isEmpty) return;
    _segments.clear();
    _pointCount = 0;
    _snapshot = null;
    notifyListeners();
  }

  void _trim() {
    while (_pointCount > maxPoints && _segments.isNotEmpty) {
      final first = _segments.first;
      final excess = _pointCount - maxPoints;
      // Never leave a one-point remnant: drop it whole.
      final drop = math.min(excess, first.points.length);
      first.points.removeRange(0, drop);
      _pointCount -= drop;
      if (first.points.length < 2) {
        _pointCount -= first.points.length;
        _segments.removeAt(0);
      }
    }
  }

  static double _metres(LatLng a, LatLng b) {
    const metresPerDegree = 111320.0;
    final dLat = (b.latitude - a.latitude) * metresPerDegree;
    final dLon = (b.longitude - a.longitude) *
        metresPerDegree *
        math.cos(a.latitude * math.pi / 180);
    return math.sqrt(dLat * dLat + dLon * dLon);
  }
}

class _MutableSegment {
  _MutableSegment(this.kind, this.points);

  final TrailKind kind;
  final List<LatLng> points;
}
