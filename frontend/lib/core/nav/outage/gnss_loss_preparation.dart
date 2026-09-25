import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../nav_config.dart';

/// A GNSS reading trustworthy enough to seed dead reckoning at outage start,
/// captured while Preparation Mode is armed and GNSS is still healthy — so a
/// fix already degrading at the tunnel mouth is never the seed. Never used to
/// move the live marker: live GNSS is never snapped (root CLAUDE.md).
@immutable
class PreLockState {
  const PreLockState({
    required this.speedMps,
    required this.headingDeg,
    required this.lat,
    required this.lon,
    required this.capturedAt,
    this.courseDeg,
  });

  final double speedMps;
  final double? courseDeg;
  final double headingDeg;
  final double lat;
  final double lon;
  final DateTime capturedAt;

  bool isFreshAt(DateTime now, Duration maxAge) =>
      !now.isBefore(capturedAt) && now.difference(capturedAt) <= maxAge;
}

/// Tracks GNSS speed samples over a short trailing window and reports their
/// spread, for the "velocity stable" readiness check.
class SpeedStdWindow {
  SpeedStdWindow({this.windowMax = const Duration(seconds: 5)});

  final Duration windowMax;
  final List<({DateTime at, double speed})> _samples = [];

  void add(DateTime now, double speedMps) {
    if (!speedMps.isFinite) return;
    _samples.add((at: now, speed: speedMps));
    final cutoff = now.subtract(windowMax);
    _samples.removeWhere((s) => s.at.isBefore(cutoff));
  }

  /// Sample standard deviation, or null with fewer than two samples in the
  /// window (nothing to say about stability yet).
  double? get stdMps {
    if (_samples.length < 2) return null;
    final mean =
        _samples.map((s) => s.speed).reduce((a, b) => a + b) / _samples.length;
    final variance = _samples
            .map((s) => (s.speed - mean) * (s.speed - mean))
            .reduce((a, b) => a + b) /
        _samples.length;
    return variance <= 0 ? 0 : math.sqrt(variance);
  }
}

/// "GNSS Loss Preparation Mode": armed when a tunnel from the offline map is
/// within [GnssLossPreparationConfig.prepareDistanceM] ahead and not yet
/// entered. While armed the controller keeps [capture]ing the latest known-
/// good GNSS reading here, so a tunnel-mouth outage seeds dead reckoning from
/// a trustworthy speed/course instead of whatever fix arrived last, and pre-
/// selects the road corridor (see `RoadConstraint.lock`) ahead of the outage.
/// Left the moment the tunnel is passed/exited or the route diverges.
class GnssLossPreparation {
  GnssLossPreparation({NavConfig config = NavConfig.defaults})
      : _c = config.gnssLossPreparation;

  final GnssLossPreparationConfig _c;

  bool _active = false;
  PreLockState? _preLock;

  bool get isActive => _active;
  PreLockState? get preLockState => _preLock;
  Duration get maxSeedAge => _c.maxSeedAge;
  double get prepareDistanceM => _c.prepareDistanceM;

  /// Feed once per tunnel-lookahead update. [distanceM]/[inside] null/false
  /// when there is no tunnel ahead at all.
  void updateTunnel({required double? distanceM, required bool inside}) {
    final withinRange =
        distanceM != null && !inside && distanceM <= _c.prepareDistanceM;
    if (withinRange) {
      _active = true;
      return;
    }
    // Tunnel entered (the outage takes over) or passed/diverged: done.
    if (_active) {
      _active = false;
      _preLock = null;
    }
  }

  /// Records the latest known-good reading while armed. The caller only
  /// invokes this for a fix it already trusts (good GNSS health); a degraded
  /// one is simply not passed, so the snapshot keeps the last good value.
  void capture({
    required double speedMps,
    required double headingDeg,
    required double lat,
    required double lon,
    required DateTime now,
    double? courseDeg,
  }) {
    if (!_active) return;
    _preLock = PreLockState(
      speedMps: speedMps,
      courseDeg: courseDeg,
      headingDeg: headingDeg,
      lat: lat,
      lon: lon,
      capturedAt: now,
    );
  }

  /// The pre-lock state to seed dead reckoning with at outage start, or null
  /// when there is none or it is too old.
  PreLockState? seedAt(DateTime now) {
    final s = _preLock;
    if (s == null || !s.isFreshAt(now, _c.maxSeedAge)) return null;
    return s;
  }
}
