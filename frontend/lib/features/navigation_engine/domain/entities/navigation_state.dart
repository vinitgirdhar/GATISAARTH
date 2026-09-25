import '../../../../core/platform/gnss/gnss_telemetry.dart';

/// Where the position on screen comes from right now.
enum FusionMode {
  gnssLocked('GNSS locked', 'GNSS_LOCKED'),
  gnssDegraded('GNSS degraded', 'GNSS_DEGRADED'),
  deadReckoning('Dead reckoning', 'DEAD_RECKONING'),
  reacquiring('Reacquiring GNSS', 'REACQUIRING');

  const FusionMode(this.label, this.nameString);

  /// Short readable name, for the map and status pills.
  final String label;

  /// Stable upper-case code for logs and telemetry.
  final String nameString;
}

/// The position the UI draws, with the mode that produced it.
class NavigationStateModel {
  const NavigationStateModel({
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.speed,
    required this.confidence,
    required this.fusionMode,
  });

  final double latitude, longitude;

  /// Degrees clockwise from north.
  final double heading;

  /// m/s.
  final double speed;

  /// 0..1.
  final double confidence;
  final FusionMode fusionMode;
}

/// One ranked road geometry that remains plausible during an outage.
///
/// Multiple entries are intentionally allowed: a fork stays visibly
/// ambiguous until sensor or GNSS evidence separates the hypotheses.
class RoadCorridorModel {
  const RoadCorridorModel({
    required this.polyline,
    required this.probability,
    this.roadName,
  });

  /// Flat `[lat0, lon0, lat1, lon1, …]`.
  final List<double> polyline;
  final double probability;
  final String? roadName;
}

/// Whether each sensor is delivering usable data.
class SensorHealthModel {
  const SensorHealthModel({
    required this.accelerometer,
    required this.gyroscope,
    required this.magnetometer,
    required this.gnss,
    this.barometer = false,
  });

  final bool accelerometer, gyroscope, magnetometer, gnss, barometer;
}

/// Satellites of one constellation and their mean signal (C/N0, dB-Hz).
class SatelliteInfoModel {
  const SatelliteInfoModel({required this.count, required this.signalStrength});

  final int count;
  final double signalStrength;
}

/// The four constellations the Sensors tab lists.
class SatelliteBreakdownModel {
  const SatelliteBreakdownModel({
    required this.navIC,
    required this.gps,
    required this.galileo,
    required this.glonass,
  });

  /// Per-constellation counts and mean C/N0 from the phone's own GNSS status;
  /// all zero before the first status arrives.
  factory SatelliteBreakdownModel.fromTelemetry(GnssTelemetrySnapshot? t) {
    SatelliteInfoModel of(GnssConstellation c) => SatelliteInfoModel(
          count: t?.countFor(c) ?? 0,
          signalStrength: t?.meanCn0For(c) ?? 0,
        );
    return SatelliteBreakdownModel(
      navIC: of(GnssConstellation.navic),
      gps: of(GnssConstellation.gps),
      galileo: of(GnssConstellation.galileo),
      glonass: of(GnssConstellation.glonass),
    );
  }

  final SatelliteInfoModel navIC, gps, galileo, glonass;
}

/// What the AI panel shows about the speed model.
class InferenceStatsModel {
  const InferenceStatsModel({
    required this.latencyMs,
    required this.modelVersion,
    required this.confidence,
    required this.estimatedSpeed,
  });

  /// Null until the neural model has actually run.
  final int? latencyMs;
  final String modelVersion;
  final double? confidence;
  final double? estimatedSpeed;
}

/// A bump or pothole the vibration detector flagged.
class AnomalyEventModel {
  const AnomalyEventModel({
    required this.type,
    required this.timestamp,
    required this.confidence,
  });

  /// `pothole` or `speed_breaker`.
  final String type;

  /// Epoch milliseconds.
  final int timestamp;
  final double confidence;
}
