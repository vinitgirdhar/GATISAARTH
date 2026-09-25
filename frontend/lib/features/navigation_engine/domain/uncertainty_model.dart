import 'dart:math';

/// A position-uncertainty margin (metres) and the 0..1 confidence derived
/// from it. This is what the driver-facing confidence ring shows.
class UncertaintyEstimate {
  const UncertaintyEstimate({
    required this.marginMeters,
    required this.confidence,
  });

  final double marginMeters;
  final double confidence;
}

/// Modelled position uncertainty.
///
/// While GNSS is live the margin is simply the receiver's reported accuracy.
/// During an outage it grows with distance travelled and elapsed time. The
/// growth rates below are conservative *model parameters*, not measured
/// results: they are chosen so the modelled drift stays inside the 10 %-of-
/// distance acceptance bar of the problem statement (5 % of distance plus a
/// small time term for unobserved heading/bias error).
class UncertaintyModel {
  const UncertaintyModel._();

  static const double driftPerMetre = 0.05;
  static const double driftPerSecond = 0.15;

  /// Share of the unexplained travel (see [deadReckoning]) added to the
  /// margin. 1: the variance-only stationary gate cannot tell a real stop
  /// from a smooth cruise, so the margin must cover both.
  static const double unexplainedTravelFraction = 1.0;

  /// Margin (m) at which confidence bottoms out.
  static const double confidenceScaleMeters = 150;
  static const double minConfidence = 0.30;
  static const double maxConfidence = 0.99;

  /// A phone GNSS fix is never trustworthy below a few metres.
  static const double minMarginMeters = 3;

  static UncertaintyEstimate fromMargin(double marginMeters) {
    final margin = max(marginMeters, minMarginMeters);
    final confidence = (1 - margin / confidenceScaleMeters)
        .clamp(minConfidence, maxConfidence)
        .toDouble();
    return UncertaintyEstimate(marginMeters: margin, confidence: confidence);
  }

  /// GNSS is live. [degradeFactor] > 1 models multipath (e.g. urban canyon).
  static UncertaintyEstimate live({
    required double gnssAccuracyMeters,
    double degradeFactor = 1,
  }) =>
      fromMargin(gnssAccuracyMeters * degradeFactor);

  static UncertaintyEstimate deadReckoning({
    required double accuracyAtLossMeters,
    required double distanceSinceLossMeters,
    required Duration sinceLoss,
    double speedAtLossMps = 0,
  }) {
    final base = max(accuracyAtLossMeters, minMarginMeters);
    final seconds = max(sinceLoss.inMilliseconds / 1000, 0);
    final distance = max(distanceSinceLossMeters, 0);
    // Travel the last GNSS speed implies but dead reckoning did not
    // integrate: a real stop, or a cruise the IMU took for one. Either could
    // be true, so the margin covers it rather than trusting the stop.
    final unexplained = max(max(speedAtLossMps, 0) * seconds - distance, 0);
    return fromMargin(
      base +
          driftPerMetre * distance +
          driftPerSecond * seconds +
          unexplainedTravelFraction * unexplained,
    );
  }
}

/// Tracks the current GNSS outage: when it began, how accurate the last fix
/// was, and how far the vehicle has dead-reckoned since.
class OutageTracker {
  DateTime? _startedAt;
  double _accuracyAtLoss = 0;
  double _distanceMeters = 0;
  double _speedAtLoss = 0;

  bool get isActive => _startedAt != null;
  double get distanceMeters => _distanceMeters;
  double get accuracyAtLossMeters => _accuracyAtLoss;

  Duration elapsed(DateTime now) =>
      _startedAt == null ? Duration.zero : now.difference(_startedAt!);

  /// Call every tick with the current outage condition; safe to repeat.
  ///
  /// [alreadyElapsed] backdates the start: an outage is only *noticed* some
  /// time after the last real fix, and that unobserved time still counts
  /// towards the drift margin.
  void update({
    required bool outage,
    required DateTime now,
    required double accuracyMeters,
    Duration alreadyElapsed = Duration.zero,
    double speedMps = 0,
  }) {
    if (outage && _startedAt == null) {
      _startedAt = now.subtract(alreadyElapsed);
      _accuracyAtLoss = accuracyMeters;
      _distanceMeters = 0;
      _speedAtLoss = speedMps.isFinite ? speedMps : 0;
    } else if (!outage && _startedAt != null) {
      reset();
    }
  }

  void addDistance(double meters) {
    if (isActive && meters > 0) _distanceMeters += meters;
  }

  void reset() {
    _startedAt = null;
    _accuracyAtLoss = 0;
    _distanceMeters = 0;
    _speedAtLoss = 0;
  }

  UncertaintyEstimate estimate(DateTime now) => UncertaintyModel.deadReckoning(
        accuracyAtLossMeters: _accuracyAtLoss,
        distanceSinceLossMeters: _distanceMeters,
        sinceLoss: elapsed(now),
        speedAtLossMps: _speedAtLoss,
      );
}
