import 'dart:math' as math;

import '../math/nav_math.dart';
import '../nav_config.dart';

/// Estimates the bias of the orientation-invariant yaw rate
/// (`PhoneHandlingDetector.add`'s return value) while GNSS is live, from two
/// pieces of evidence (§ hand-held mode, part 1):
///
///  * **stopped** (GNSS speed below [HandHeldConfig.biasStopSpeedMps], not
///    handling): true rotation is ~0, so the mean yaw rate over the stop *is*
///    the bias, directly;
///  * **moving straight and steady** (GNSS speed above
///    [HandHeldConfig.biasMinSpeedMps]): the GNSS course rate, from position
///    displacement over ~4 s, is compared with the mean measured yaw rate
///    over the same span - the difference is a (noisier) bias sample.
///
/// Both are folded into a slow EMA. A hand-held phone's MEMS gyro is not
/// otherwise bias-corrected here (there is no ZARU, no vehicle frame to gate
/// it on), and that open-loop bias is what made the first cut of hand-held
/// mode drift far worse than simply holding the last fix - see the CLAUDE.md
/// hand-held section.
class GyroBiasEstimator {
  GyroBiasEstimator({NavConfig config = NavConfig.defaults})
      : _config = config.handHeld;

  final HandHeldConfig _config;

  double _biasRadPerS = 0;
  double get biasRadPerS => _biasRadPerS;

  final List<_YawSample> _buffer = [];
  static const _bufferSpan = Duration(seconds: 12);

  double _stopSum = 0;
  int _stopCount = 0;
  static const _stopFlushSamples = 40; // ~1 s at a typical hand-held rate

  final List<_FixSample> _fixes = [];
  static const _fixHistorySpan = Duration(seconds: 10);

  double? _lastSpanCourseRad;
  int? _lastSpanEndUs;

  void reset() {
    _biasRadPerS = 0;
    _buffer.clear();
    _stopSum = 0;
    _stopCount = 0;
    _fixes.clear();
    _lastSpanCourseRad = null;
    _lastSpanEndUs = null;
  }

  /// Feeds one IMU step's orientation-invariant yaw rate.
  void observeImu({
    required double yawRateRadPerS,
    required bool handling,
    required int monotonicUs,
  }) {
    _buffer.add(_YawSample(monotonicUs, yawRateRadPerS, handling));
    while (_buffer.isNotEmpty &&
        monotonicUs - _buffer.first.us > _bufferSpan.inMicroseconds) {
      _buffer.removeAt(0);
    }
  }

  /// Feeds the same step's GNSS-derived stationary state: true rotation is
  /// ~0 at a genuine stop, so the mean measured yaw rate there is the bias.
  void observeGnssStop({
    required bool stationary,
    required double yawRateRadPerS,
    required bool handling,
  }) {
    if (stationary && !handling) {
      _stopSum += yawRateRadPerS;
      _stopCount++;
      if (_stopCount >= _stopFlushSamples) {
        _update(_stopSum / _stopCount, _config.biasStopLearnRate);
        _stopSum = 0;
        _stopCount = 0;
      }
    } else {
      _stopSum = 0;
      _stopCount = 0;
    }
  }

  /// A trusted GNSS fix: looks for a fix ~4 s earlier to derive a course from
  /// the displacement between them, and - once two such spans have been
  /// computed back to back - a course *rate* to compare with the mean
  /// measured yaw rate over the same interval.
  void onFix({
    required double latitudeDeg,
    required double longitudeDeg,
    double? speedMps,
    required bool handling,
    required int monotonicUs,
  }) {
    _fixes.add(_FixSample(monotonicUs, latitudeDeg, longitudeDeg, speedMps));
    while (_fixes.isNotEmpty &&
        monotonicUs - _fixes.first.us > _fixHistorySpan.inMicroseconds) {
      _fixes.removeAt(0);
    }
    if ((speedMps ?? 0) < _config.biasMinSpeedMps || handling) return;

    _FixSample? old;
    for (final f in _fixes.reversed) {
      final dt = (monotonicUs - f.us) / 1e6;
      if (dt > 4.5) break;
      if (dt >= 3.5) {
        old = f;
        break;
      }
    }
    if (old == null || (old.speedMps ?? 0) < _config.biasMinSpeedMps) return;

    final d = NavMath.nedBetween(
      lat0: old.latitudeDeg,
      lon0: old.longitudeDeg,
      alt0: 0,
      lat1: latitudeDeg,
      lon1: longitudeDeg,
      alt1: 0,
    );
    final displacement = math.sqrt(d.x * d.x + d.y * d.y);
    if (displacement < 5) return; // too little travel for a bearing
    final course = math.atan2(d.y, d.x);

    final prevCourse = _lastSpanCourseRad;
    final prevEndUs = _lastSpanEndUs;
    if (prevCourse != null && prevEndUs != null) {
      final dt = (monotonicUs - prevEndUs) / 1e6;
      if (dt >= 3.0 && dt <= 5.0) {
        final courseRate = NavMath.wrapPi(course - prevCourse) / dt;
        var sum = 0.0;
        var n = 0;
        for (final s in _buffer) {
          if (s.us < prevEndUs || s.us > monotonicUs || s.handling) continue;
          sum += s.yawRate;
          n++;
        }
        // Require the buffer to actually cover most of the span before
        // trusting its mean - a gap (e.g. the app was backgrounded) must not
        // silently pass off empty coverage as a clean, steady straight.
        if (n > dt * 20) {
          _update(sum / n - courseRate, _config.biasMovingLearnRate);
        }
      }
    }
    _lastSpanCourseRad = course;
    _lastSpanEndUs = monotonicUs;
  }

  void _update(double sample, double learnRate) {
    if (!sample.isFinite) return;
    final clamped =
        sample.clamp(-_config.maxBiasRadPerS, _config.maxBiasRadPerS);
    _biasRadPerS += learnRate * (clamped - _biasRadPerS);
  }
}

class _YawSample {
  const _YawSample(this.us, this.yawRate, this.handling);
  final int us;
  final double yawRate;
  final bool handling;
}

class _FixSample {
  const _FixSample(this.us, this.latitudeDeg, this.longitudeDeg, this.speedMps);
  final int us;
  final double latitudeDeg;
  final double longitudeDeg;
  final double? speedMps;
}
