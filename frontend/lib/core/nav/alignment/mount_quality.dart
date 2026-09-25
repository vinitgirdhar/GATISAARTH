import 'package:flutter/foundation.dart';

import '../nav_config.dart';

/// Overall read of [MountQuality.overall] (§ Dynamic Mount Quality Score).
enum MountQualityLabel { excellent, good, fair, poor }

extension MountQualityLabelText on MountQualityLabel {
  String get text {
    switch (this) {
      case MountQualityLabel.excellent:
        return 'EXCELLENT';
      case MountQualityLabel.good:
        return 'GOOD';
      case MountQualityLabel.fair:
        return 'FAIR';
      case MountQualityLabel.poor:
        return 'POOR';
    }
  }
}

/// A single 0-100 mount-quality score built from four sub-scores.
@immutable
class MountQuality {
  const MountQuality({
    required this.stability,
    required this.vibration,
    required this.magnetic,
    required this.alignment,
    required this.overall,
    required this.label,
    required this.unstable,
    this.message,
  });

  /// Before anything has been measured yet.
  static const MountQuality unknown = MountQuality(
    stability: 0,
    vibration: 0,
    magnetic: 0,
    alignment: 0,
    overall: 0,
    label: MountQualityLabel.poor,
    unstable: false,
  );

  /// 0-100 each: how still the phone sits in its mount, how much road/engine
  /// vibration reaches it, how clean the magnetic field around it is, and how
  /// converged the phone-to-vehicle transform is.
  final double stability;
  final double vibration;
  final double magnetic;
  final double alignment;

  /// Average of the four, 0-100.
  final double overall;
  final MountQualityLabel label;

  /// True while the phone is being handled or wobbling in its mount —
  /// dead-reckoning accuracy degrades regardless of how the other three
  /// sub-scores read.
  final bool unstable;

  final String? message;
}

/// Turns four signals that are already computed elsewhere for other reasons
/// into one score a driver can read at a glance. Nothing here measures
/// anything new: stability comes from `PhoneHandlingDetector`'s wobble (via
/// `SensorHealthMonitor`), vibration from `AccelDisturbanceEstimator`'s
/// `vibrationScore` (read only — never relabelled as this team's own signal),
/// magnetic from the fault detector's field magnitude, and alignment from
/// `MountAlignmentEstimator`'s own confidence.
class MountQualityEstimator {
  MountQualityEstimator({NavConfig config = NavConfig.defaults})
      : _config = config.mountQuality,
        _field = config.sensorFault;

  final MountQualityConfig _config;
  final SensorFaultConfig _field;

  MountQuality evaluate({
    double? orientationWobbleDeg,
    bool handling = false,
    double? vibrationScore,
    double? magneticFieldMicroTesla,
    double? alignmentConfidence,
  }) {
    final stability = _stabilityScore(orientationWobbleDeg, handling);
    final vibration = vibrationScore == null
        ? 100.0
        : 100 * (1 - vibrationScore.clamp(0.0, 1.0));
    final magnetic = _magneticScore(magneticFieldMicroTesla);
    final alignment = 100 * (alignmentConfidence ?? 0).clamp(0.0, 1.0);
    final overall = (stability + vibration + magnetic + alignment) / 4;

    final unstable = handling ||
        (orientationWobbleDeg != null &&
            orientationWobbleDeg >= _config.unstableWobbleDeg);

    return MountQuality(
      stability: stability,
      vibration: vibration,
      magnetic: magnetic,
      alignment: alignment,
      overall: overall,
      // The vehicle frame is not known until alignment converges; a mount
      // cannot be better than FAIR before that, however steady it sits.
      label: alignment < _config.alignmentKnownScore &&
              _label(overall).index < MountQualityLabel.fair.index
          ? MountQualityLabel.fair
          : _label(overall),
      unstable: unstable,
      message: unstable
          ? 'Mount unstable — dead-reckoning accuracy may degrade'
          : null,
    );
  }

  double _stabilityScore(double? wobbleDeg, bool handling) {
    if (handling) return 20;
    if (wobbleDeg == null) return 100;
    final ratio = (wobbleDeg / _config.unstableWobbleDeg).clamp(0.0, 2.0);
    return (100 * (1 - ratio / 2)).clamp(0.0, 100.0);
  }

  double _magneticScore(double? uT) {
    // Unknown yet: neutral, not a penalty — nothing has said it is bad.
    if (uT == null) return 70;
    final min = _field.minFieldMicroTesla;
    final max = _field.maxFieldMicroTesla;
    if (uT < min || uT > max) return 0;
    final center = (min + max) / 2;
    final halfSpan = (max - min) / 2;
    final distance = (uT - center).abs() / halfSpan;
    return (100 * (1 - distance)).clamp(0.0, 100.0);
  }

  MountQualityLabel _label(double overall) {
    if (overall >= _config.excellentScore) return MountQualityLabel.excellent;
    if (overall >= _config.goodScore) return MountQualityLabel.good;
    if (overall >= _config.fairScore) return MountQualityLabel.fair;
    return MountQualityLabel.poor;
  }
}
