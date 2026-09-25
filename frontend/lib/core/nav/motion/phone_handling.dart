import 'dart:math' as math;

import '../math/nav_math.dart';
import '../nav_config.dart';

/// Orientation-invariant motion cues for a phone that is not mounted: a
/// low-passed gravity direction (so a yaw rate can be read off the gyro
/// regardless of how the phone is held) and a "handling" flag for when that
/// direction is changing too fast to trust (§ hand-held mode).
///
/// Built from three real Mumbai drives (2026-09-24, see
/// `frontend/lib/core/nav/CLAUDE.md`): hand-held gyro shakes 0.4-1.4 rad/s even
/// at a standstill, and the gravity direction in the phone frame wanders
/// >14 deg for 19-40 % of seconds. Freezing heading integration while
/// [isHandling] is true, and reading yaw rate as gyro projected onto the
/// low-passed gravity direction instead of a fixed body axis, is what
/// improved a hand-held 60 s outage error from 226-242 m (hold-last-speed) to
/// 186-204 m median in that data.
class PhoneHandlingDetector {
  PhoneHandlingDetector({NavConfig config = NavConfig.defaults})
      : _config = config.handHeld;

  final HandHeldConfig _config;

  Vector3? _gravity; // low-passed specific force, phone frame
  final List<_TimedVector> _recentDirection = [];
  int? _lastUs;
  bool _handling = false;
  double _wobbleRad = 0;

  /// Low-passed gravity direction in the phone frame ("up"), or null before
  /// the first sample.
  Vector3? get gravityDirection =>
      (_gravity != null && _gravity!.length > 1e-6)
          ? _gravity!.normalized()
          : null;

  /// True when that direction has moved more than the configured threshold
  /// within the configured window: the phone is being handled (picked up,
  /// turned over, gestured with) right now, not just riding quietly.
  bool get isHandling => _handling;

  /// How far the low-passed gravity direction has moved over the handling
  /// window, in degrees — the same measurement [isHandling] thresholds,
  /// exposed as a number for the mount-stability check (§ hardware check).
  double get wobbleDeg => _wobbleRad * NavMath.radToDeg;

  void reset() {
    _gravity = null;
    _recentDirection.clear();
    _lastUs = null;
    _handling = false;
    _wobbleRad = 0;
  }

  /// Feeds one raw, calibrated accelerometer+gyro sample (phone frame).
  ///
  /// Returns the orientation-invariant yaw rate: the gyro's component about
  /// the low-passed true vertical, meaningful however the phone is oriented -
  /// unlike a rate read off a fixed body axis, which only means "yaw" once
  /// the phone-to-vehicle mount is known.
  double add({
    required Vector3 accelPhone,
    required Vector3 gyroPhone,
    required int monotonicUs,
  }) {
    final lastUs = _lastUs;
    _lastUs = monotonicUs;

    final previous = _gravity;
    if (previous == null) {
      _gravity = accelPhone.clone();
    } else {
      final dtUs = monotonicUs - lastUs!;
      if (dtUs > 0) {
        final dt = dtUs / 1e6;
        final alpha = math.exp(-dt / _config.gravityTauS);
        _gravity = previous * alpha + accelPhone * (1 - alpha);
      }
    }

    final direction = gravityDirection;

    if (direction != null) {
      _recentDirection.add(_TimedVector(monotonicUs, direction));
    }
    while (_recentDirection.isNotEmpty &&
        monotonicUs - _recentDirection.first.us >
            _config.handlingWindow.inMicroseconds) {
      _recentDirection.removeAt(0);
    }
    if (_recentDirection.length > 1 && direction != null) {
      final oldest = _recentDirection.first.value;
      final angle = _angleBetween(oldest, direction);
      _wobbleRad = angle;
      _handling = angle > _config.handlingThresholdRad;
    }

    if (direction == null) return 0;
    // `direction` is "up" (opposite gravity); the heading convention this
    // engine uses (0 = north, increasing clockwise through east, i.e. about
    // the *down* axis) is the negative of the rotation about "up" - see
    // `InsState.headingDeg` / `NavMath.addNed`.
    return -gyroPhone.dot(direction);
  }

  static double _angleBetween(Vector3 a, Vector3 b) {
    final cosAngle = a.dot(b).clamp(-1.0, 1.0);
    return math.acos(cosAngle);
  }
}

/// Stop detection with no vehicle frame needed: std(|a|) over a rolling
/// second, exactly the orientation-invariant part of `MotionClassifier`'s
/// stillness gate. Measured ~90 % correct hand-held vs ~99 % mounted (three
/// real Mumbai drives, 2026-09-24).
class HandHeldStopDetector {
  HandHeldStopDetector({NavConfig config = NavConfig.defaults})
      : _config = config.handHeld;

  final HandHeldConfig _config;
  final List<_TimedScalar> _window = [];
  bool _stationary = false;
  int? _quietSinceUs;
  int? _movingSinceUs;

  bool get isStationary => _stationary;

  void reset() {
    _window.clear();
    _stationary = false;
    _quietSinceUs = null;
    _movingSinceUs = null;
  }

  bool add({required double accelMagnitude, required int monotonicUs}) {
    _window.add(_TimedScalar(monotonicUs, accelMagnitude));
    while (_window.isNotEmpty &&
        monotonicUs - _window.first.us >
            const Duration(seconds: 1).inMicroseconds) {
      _window.removeAt(0);
    }
    if (_window.length < 3) return _stationary;

    var sum = 0.0;
    for (final s in _window) {
      sum += s.value;
    }
    final mean = sum / _window.length;
    var variance = 0.0;
    for (final s in _window) {
      final d = s.value - mean;
      variance += d * d;
    }
    variance /= _window.length;
    final std = math.sqrt(variance);
    final quiet = std < _config.stopAccelStd;

    if (quiet) {
      _movingSinceUs = null;
      _quietSinceUs ??= monotonicUs;
      if (!_stationary &&
          monotonicUs - _quietSinceUs! >=
              _config.stopEnterDelay.inMicroseconds) {
        _stationary = true;
      }
    } else {
      _quietSinceUs = null;
      _movingSinceUs ??= monotonicUs;
      if (_stationary &&
          monotonicUs - _movingSinceUs! >=
              _config.stopExitDelay.inMicroseconds) {
        _stationary = false;
      }
    }
    return _stationary;
  }
}

class _TimedVector {
  const _TimedVector(this.us, this.value);
  final int us;
  final Vector3 value;
}

class _TimedScalar {
  const _TimedScalar(this.us, this.value);
  final int us;
  final double value;
}
