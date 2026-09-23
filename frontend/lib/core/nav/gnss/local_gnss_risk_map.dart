import 'dart:math' as math;

/// A caller-supplied GNSS health observation. Coordinates are used only to
/// choose a coarse cell; this object is never retained by [LocalGnssRiskMap].
class GnssRiskSample {
  const GnssRiskSample({
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.accuracyM,
    required this.observedAt,
    required this.journeyId,
    required this.degraded,
  });

  final double latitudeDeg;
  final double longitudeDeg;
  final double accuracyM;
  final DateTime observedAt;
  final String journeyId;
  final bool degraded;
}

/// A displayable, coarse, local-only risk summary. It contains no raw fixes or
/// journey identifiers and is never suitable for turn-by-turn corrections.
class GnssRiskCell {
  const GnssRiskCell({
    required this.x,
    required this.y,
    required this.observations,
    required this.distinctJourneys,
    required this.riskFraction,
  });

  final int x;
  final int y;
  final int observations;
  final int distinctJourneys;
  final double riskFraction;
}

class _RiskObservation {
  const _RiskObservation(this.journeyId, this.degraded, this.at);

  final String journeyId;
  final bool degraded;
  final DateTime at;
}

/// Volatile Phase C foundation. No storage, network or navigation-filter link
/// exists: even opted-in samples stay on this device and vanish on restart.
/// The field-validation gate must be met before wiring any live ingestion or
/// cross-device aggregation to this class.
class LocalGnssRiskMap {
  LocalGnssRiskMap({
    this.cellSizeMeters = 250,
    this.maxLocationAccuracyM = 50,
    this.retention = const Duration(days: 7),
    this.minDistinctJourneys = 3,
    this.minObservations = 6,
  })  : assert(cellSizeMeters > 0),
        assert(maxLocationAccuracyM > 0),
        assert(retention > Duration.zero),
        assert(minDistinctJourneys > 1),
        assert(minObservations >= minDistinctJourneys);

  final double cellSizeMeters;
  final double maxLocationAccuracyM;
  final Duration retention;
  final int minDistinctJourneys;
  final int minObservations;

  final Map<(int, int), List<_RiskObservation>> _cells = {};
  bool _optedIn = false;

  bool get isOptedIn => _optedIn;

  /// Consent is never persisted. Withdrawal immediately erases every sample.
  void setOptIn(bool enabled) {
    if (!enabled) _cells.clear();
    _optedIn = enabled;
  }

  bool add(GnssRiskSample sample, {required DateTime now}) {
    if (!_optedIn || !_valid(sample, now)) return false;
    _expire(now);
    final key = _cellFor(sample.latitudeDeg, sample.longitudeDeg);
    (_cells[key] ??= []).add(_RiskObservation(
      sample.journeyId,
      sample.degraded,
      sample.observedAt,
    ));
    return true;
  }

  List<GnssRiskCell> visibleCells(DateTime now) {
    if (!_optedIn) return const [];
    _expire(now);
    final visible = <GnssRiskCell>[];
    for (final entry in _cells.entries) {
      final observations = entry.value;
      final journeys = observations.map((item) => item.journeyId).toSet();
      if (observations.length < minObservations ||
          journeys.length < minDistinctJourneys) {
        continue;
      }
      final degraded = observations.where((item) => item.degraded).length;
      visible.add(GnssRiskCell(
        x: entry.key.$1,
        y: entry.key.$2,
        observations: observations.length,
        distinctJourneys: journeys.length,
        riskFraction: degraded / observations.length,
      ));
    }
    return List.unmodifiable(visible);
  }

  bool _valid(GnssRiskSample sample, DateTime now) {
    final age = now.difference(sample.observedAt);
    return sample.latitudeDeg.isFinite &&
        sample.longitudeDeg.isFinite &&
        sample.accuracyM.isFinite &&
        sample.latitudeDeg.abs() <= 85.05112878 &&
        sample.longitudeDeg.abs() <= 180 &&
        sample.accuracyM >= 0 &&
        sample.accuracyM <= maxLocationAccuracyM &&
        sample.journeyId.trim().isNotEmpty &&
        !age.isNegative &&
        age <= retention;
  }

  void _expire(DateTime now) {
    _cells.removeWhere((_, observations) {
      observations.removeWhere((item) {
        final age = now.difference(item.at);
        return age.isNegative || age > retention;
      });
      return observations.isEmpty;
    });
  }

  (int, int) _cellFor(double latitudeDeg, double longitudeDeg) {
    const radiusM = 6378137.0;
    final latRad = latitudeDeg * math.pi / 180;
    final lonRad = longitudeDeg * math.pi / 180;
    final xMeters = radiusM * lonRad;
    final yMeters = radiusM * math.log(math.tan(math.pi / 4 + latRad / 2));
    return (
      (xMeters / cellSizeMeters).floor(),
      (yMeters / cellSizeMeters).floor(),
    );
  }
}
