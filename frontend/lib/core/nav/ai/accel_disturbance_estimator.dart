import 'dart:math' as math;

import '../math/nav_math.dart';
import '../nav_config.dart';
import 'ai_types.dart';

/// Vibration, road shocks and motion quality from the accelerometer alone
/// (P2's statistical fallback: it works today, with no model asset).
///
/// Everything is first-order recursive filtering, so a sample costs a few dozen
/// flops and no memory grows: **O(1) per sample**, whatever the sample rate.
///
/// * **Gravity** is tracked by a slow low-pass (`gravityTauS`). Its direction is
///   "up", which lets the estimator tell vertical from horizontal without
///   knowing how the phone is mounted.
/// * **Vibration** is the accelerometer minus a fast low-pass (a high-pass near
///   2 Hz, `highPassTauS`): a driver's inputs sit below that corner, road
///   texture and engine harmonics above. A second high-pass near 8 Hz
///   (`bandTauS`) isolates the upper band. The two mean-square energies, the
///   upper one weighted by `highBandWeight`, give one energy `E`, and
///   `score = E / (E + ref^2)`: 0 for a still cabin, 0.5 at `halfSaturationRms`.
/// * **Shocks** are single-sample peaks of the ~2 Hz low-pass's innovation:
///   vertical peaks against the pothole and speed-breaker thresholds
///   `MotionConfig` already defines, horizontal-dominant ones against
///   `joltAccel`, and all of them must also stand `shockRmsRatio` times above
///   the vibration already there. A shock is held for `shockHold`, and while it
///   is held the motion quality is `shockMotionQuality`. Each sample's energy is
///   clipped (`energyClipAccel`) so one pothole is a shock, not seconds of
///   "violent vibration".
/// * **Motion quality** is `1 - vibrationQualityWeight * score`, floored by the
///   shock quality while one is held.
///
/// The thresholds are engineering priors, calibrated against nothing but a
/// simulator; see the limits in `test/nav/ai_speed_replay_test.dart`.
class AccelDisturbanceEstimator {
  AccelDisturbanceEstimator({NavConfig config = NavConfig.defaults})
      : _c = config.disturbance,
        _bumpAccel = config.motion.speedBreakerNetAccel,
        _potholeAccel = config.motion.potholeNetAccel,
        _holdUs = config.disturbance.shockHold.inMicroseconds,
        _maxGapUs = config.disturbance.maxGap.inMicroseconds,
        _refEnergy = config.disturbance.halfSaturationRms *
            config.disturbance.halfSaturationRms,
        _clipEnergy = config.disturbance.energyClipAccel *
            config.disturbance.energyClipAccel;

  final DisturbanceConfig _c;
  final double _bumpAccel;
  final double _potholeAccel;
  final int _holdUs;
  final int _maxGapUs;
  final double _refEnergy;
  final double _clipEnergy;

  bool _seeded = false;
  int _lastUs = 0;

  // Slow gravity low-pass, and the two high-pass reference low-passes.
  double _gx = 0, _gy = 0, _gz = 0;
  double _l1x = 0, _l1y = 0, _l1z = 0;
  double _l2x = 0, _l2y = 0, _l2z = 0;

  // Mean-square energy of each high-passed band, (m/s^2)^2.
  double _e1 = 0, _e2 = 0;

  int _shockUntilUs = -1;
  ShockKind _shockKind = ShockKind.none;

  // The filter gains only change when the sample spacing does.
  double _cachedDt = -1;
  double _aG = 0, _a1 = 0, _a2 = 0, _aE = 0;

  DisturbanceEstimate _latest = DisturbanceEstimate.calm;

  DisturbanceEstimate get latest => _latest;

  /// RMS of the vibration above ~2 Hz (m/s^2), for diagnostics.
  double get vibrationRms => math.sqrt(_e1);

  /// Share of the vibration energy that sits above ~8 Hz, in [0, 1].
  double get highBandShare => _e1 <= 1e-12 ? 0 : math.min(1.0, _e2 / _e1);

  void reset() {
    _seeded = false;
    _lastUs = 0;
    _e1 = 0;
    _e2 = 0;
    _shockUntilUs = -1;
    _shockKind = ShockKind.none;
    _cachedDt = -1;
    _latest = DisturbanceEstimate.calm;
  }

  /// Feeds one phone-frame accelerometer sample (m/s², gravity included).
  ///
  /// Non-finite samples and timestamps that are not newer than the last are
  /// ignored and the previous estimate is returned unchanged.
  DisturbanceEstimate add(Vector3 accel, int monotonicUs) {
    final ax = accel.x, ay = accel.y, az = accel.z;
    if (!ax.isFinite || !ay.isFinite || !az.isFinite) return _latest;
    if (!_seeded) {
      _seed(ax, ay, az, monotonicUs);
      return _latest;
    }
    final dtUs = monotonicUs - _lastUs;
    if (dtUs <= 0) return _latest;
    if (dtUs > _maxGapUs) {
      // Nothing carried across a gap this long is still true: the app was
      // backgrounded, the phone was picked up. Restart, do not integrate it.
      _seed(ax, ay, az, monotonicUs);
      return _latest;
    }
    _lastUs = monotonicUs;
    _coefficients(dtUs / 1e6);

    // Shocks are read off the low-pass's *innovation* (the sample against what
    // the ~2 Hz low-pass expected), before the sample is folded in: for an
    // impulse that is the full peak at any sample rate, where the high-pass
    // that follows would show only a rate-dependent fraction of it.
    _detectShock(ax - _l1x, ay - _l1y, az - _l1z, monotonicUs);

    _gx += _aG * (ax - _gx);
    _gy += _aG * (ay - _gy);
    _gz += _aG * (az - _gz);
    _l1x += _a1 * (ax - _l1x);
    _l1y += _a1 * (ay - _l1y);
    _l1z += _a1 * (az - _l1z);
    _l2x += _a2 * (ax - _l2x);
    _l2y += _a2 * (ay - _l2y);
    _l2z += _a2 * (az - _l2z);

    final h1x = ax - _l1x, h1y = ay - _l1y, h1z = az - _l1z;
    final h2x = ax - _l2x, h2y = ay - _l2y, h2z = az - _l2z;
    final n1 = math.min(h1x * h1x + h1y * h1y + h1z * h1z, _clipEnergy);
    final n2 = math.min(h2x * h2x + h2y * h2y + h2z * h2z, _clipEnergy);
    _e1 += _aE * (n1 - _e1);
    _e2 += _aE * (n2 - _e2);

    _latest = _estimate(monotonicUs);
    return _latest;
  }

  void _seed(double ax, double ay, double az, int monotonicUs) {
    _seeded = true;
    _lastUs = monotonicUs;
    _gx = _l1x = _l2x = ax;
    _gy = _l1y = _l2y = ay;
    _gz = _l1z = _l2z = az;
  }

  void _coefficients(double dt) {
    if ((dt - _cachedDt).abs() <= 1e-9) return;
    _cachedDt = dt;
    _aG = 1 - math.exp(-dt / _c.gravityTauS);
    _a1 = 1 - math.exp(-dt / _c.highPassTauS);
    _a2 = 1 - math.exp(-dt / _c.bandTauS);
    _aE = 1 - math.exp(-dt / _c.energyTauS);
  }

  /// Splits the innovation into a component along gravity and the rest, and
  /// arms the hold when either is a transient this engine cannot trust.
  void _detectShock(double dx, double dy, double dz, int monotonicUs) {
    final normSq = dx * dx + dy * dy + dz * dz;
    final gn = math.sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
    var vertical = 0.0;
    if (gn > 1e-6) {
      vertical = (dx * _gx + dy * _gy + dz * _gz) / gn;
    }
    final horizontal = math.sqrt(math.max(0.0, normSq - vertical * vertical));
    final v = vertical.abs();
    // The vibration already there sets the bar, so texture is not a pothole.
    final floor = _c.shockRmsRatio * math.sqrt(_e1);

    var kind = ShockKind.none;
    if (v >= _potholeAccel && v >= floor) {
      kind = ShockKind.pothole;
    } else if (v >= _bumpAccel && v >= floor) {
      kind = ShockKind.bump;
    } else if (horizontal >= _c.joltAccel &&
        horizontal > v &&
        horizontal >= floor) {
      kind = ShockKind.jolt;
    }
    if (kind == ShockKind.none) return;
    // Inside a hold the most telling kind is kept: an impulse's own tail also
    // reads as a smaller hit.
    final held = monotonicUs <= _shockUntilUs;
    if (!held || _rank(kind) > _rank(_shockKind)) _shockKind = kind;
    _shockUntilUs = monotonicUs + _holdUs;
  }

  static int _rank(ShockKind kind) {
    switch (kind) {
      case ShockKind.pothole:
        return 3;
      case ShockKind.jolt:
        return 2;
      case ShockKind.bump:
        return 1;
      case ShockKind.none:
        return 0;
    }
  }

  DisturbanceEstimate _estimate(int monotonicUs) {
    final energy = _e1 + _c.highBandWeight * _e2;
    final score = energy / (energy + _refEnergy);
    final shock = monotonicUs <= _shockUntilUs ? _shockKind : ShockKind.none;
    var quality = 1 - _c.vibrationQualityWeight * score;
    if (shock != ShockKind.none) {
      quality = math.min(quality, _c.shockMotionQuality);
    }
    return DisturbanceEstimate(
      vibrationScore: score,
      vibrationClass: score < _c.lowScoreBelow
          ? DisturbanceClass.low
          : (score >= _c.highScoreAbove
              ? DisturbanceClass.high
              : DisturbanceClass.normal),
      motionQuality: quality,
      monotonicUs: monotonicUs,
      shock: shock,
      source: EstimateSource.statistical,
    );
  }
}
