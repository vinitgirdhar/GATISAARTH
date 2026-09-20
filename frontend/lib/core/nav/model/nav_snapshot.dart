import 'package:flutter/foundation.dart';

import '../gnss/gnss_quality.dart';
import '../map/map_matcher.dart';
import '../motion/motion_classifier.dart';
import '../sensors/barometer.dart';
import '../sensors/sensor_fault_detector.dart';
import '../sensors/sensor_sample.dart';

/// Navigation mode (§25). Every transition has an explicit condition and is
/// logged with its reason — see `NavigationEngine.transitions`.
enum NavMode {
  /// Nothing has started yet.
  boot,

  /// Sensors are running but the filter has no position to start from.
  calibrating,

  /// Waiting for a first usable fix.
  gnssSearch,

  /// A healthy fix stream is correcting the filter.
  gnssLocked,

  /// Fixes are arriving but their quality is poor; they are down-weighted.
  gnssDegraded,

  /// Fixes are arriving but the integrity monitor does not trust them.
  gnssUnreliable,

  /// No usable fix; position comes from inertial propagation.
  deadReckoning,

  /// Dead reckoning with the road graph constraining the solution.
  ///
  /// Reachable only when a road graph is actually loaded. The repository ships
  /// none (`maps/processed_graphs/road_edges.json` is `{"edges": []}`), so on a
  /// stock build this mode never occurs — which is the honest answer, not a
  /// missing feature pretending to work (§83).
  mapAssistedDeadReckoning,

  /// A fix has returned and the filter is converging back onto it.
  reacquiring,

  /// One or more sensors are unusable, but navigation continues.
  sensorDegraded,

  /// The minimum viable sensor set is gone; no position can be produced.
  sensorFailure,

  /// Reduced operation because of device temperature. Unreachable until P3.
  thermalLimit,

  /// Reduced operation because of battery. Unreachable until P3.
  lowPower,
}

extension NavModeLabel on NavMode {
  String get label {
    switch (this) {
      case NavMode.boot:
        return 'Starting';
      case NavMode.calibrating:
        return 'Calibrating';
      case NavMode.gnssSearch:
        return 'Searching';
      case NavMode.gnssLocked:
        return 'GNSS locked';
      case NavMode.gnssDegraded:
        return 'GNSS degraded';
      case NavMode.gnssUnreliable:
        return 'GNSS unreliable';
      case NavMode.deadReckoning:
        return 'Dead reckoning';
      case NavMode.mapAssistedDeadReckoning:
        return 'Map-assisted dead reckoning';
      case NavMode.reacquiring:
        return 'Reacquiring';
      case NavMode.sensorDegraded:
        return 'Sensors degraded';
      case NavMode.sensorFailure:
        return 'Sensor failure';
      case NavMode.thermalLimit:
        return 'Thermal limit';
      case NavMode.lowPower:
        return 'Low power';
    }
  }

  /// True when position is coming from inertial propagation rather than GNSS.
  bool get isDeadReckoning =>
      this == NavMode.deadReckoning ||
      this == NavMode.mapAssistedDeadReckoning;
}

/// Is the estimate *safe to use*, as opposed to how precise it claims to be
/// (§28). Confidence answers "how much do we trust it"; integrity answers
/// "should it be used at all".
enum NavIntegrity { high, medium, low, invalid }

extension NavIntegrityLabel on NavIntegrity {
  String get label {
    switch (this) {
      case NavIntegrity.high:
        return 'HIGH';
      case NavIntegrity.medium:
        return 'MEDIUM';
      case NavIntegrity.low:
        return 'LOW';
      case NavIntegrity.invalid:
        return 'INVALID';
    }
  }
}

/// How much each source is currently weighting into the estimate (§51).
///
/// These are **information weights**, not probabilities: each accepted
/// measurement contributes `1/sigma^2` to its source's bucket, the buckets
/// decay over a rolling window, and the result is normalised. It answers
/// "what is holding this position up right now", which is exactly what the
/// "Why this position?" panel claims — nothing more.
@immutable
class FusionContribution {
  const FusionContribution({
    this.gnss = 0,
    this.inertial = 0,
    this.ai = 0,
    this.map = 0,
  });

  static const FusionContribution none = FusionContribution();

  final double gnss;
  final double inertial;
  final double ai;
  final double map;

  bool get isEmpty => gnss + inertial + ai + map <= 0;

  Map<String, double> get asMap => {
        'GNSS': gnss,
        'IMU': inertial,
        'AI velocity': ai,
        'Map': map,
      };
}

/// Health of one subsystem. `available == false` means the UI shows `--`.
@immutable
class SubsystemHealth {
  const SubsystemHealth({
    required this.available,
    required this.source,
    this.score,
    this.detail,
  });

  static const SubsystemHealth unavailable = SubsystemHealth(
    available: false,
    source: DataSource.unavailable,
  );

  final bool available;
  final DataSource source;

  /// 0..1, or null when there is no basis for a number.
  final double? score;

  final String? detail;
}

/// The single immutable view of the navigation state that the UI observes
/// (§71, §72). Screens never recompute any of this.
@immutable
class NavigationSnapshot {
  const NavigationSnapshot({
    required this.sequence,
    required this.monotonicUs,
    required this.mode,
    required this.integrity,
    this.latitude,
    this.longitude,
    this.altitude,
    this.speedMps,
    this.headingDeg,
    this.horizontalSigmaM,
    this.verticalSigmaM,
    this.speedSigmaMps,
    this.headingSigmaDeg,
    this.gnss,
    this.motion = MotionSnapshot.initial,
    this.sensorStats = const {},
    this.sensorFaults = const {},
    this.barometer,
    this.alignmentConfidence,
    this.calibrationQuality,
    this.contribution = FusionContribution.none,
    this.ai = SubsystemHealth.unavailable,
    this.mapMatch = SubsystemHealth.unavailable,
    this.mapMatchResult,
    this.outageDuration = Duration.zero,
    this.outageDistanceM = 0,
    this.positionSource = DataSource.unavailable,
    this.notes = const [],
  });

  /// Monotonic counter. A consumer that sees a lower sequence than it already
  /// has must discard it — stale data never overwrites newer data (§47).
  final int sequence;

  final int monotonicUs;
  final NavMode mode;
  final NavIntegrity integrity;

  /// Null until the filter has a position. The UI shows `--`, never 0,0.
  final double? latitude;
  final double? longitude;
  final double? altitude;

  final double? speedMps;
  final double? headingDeg;

  /// Covariance-derived, not modelled from a formula (§27).
  final double? horizontalSigmaM;
  final double? verticalSigmaM;
  final double? speedSigmaMps;
  final double? headingSigmaDeg;

  final GnssAssessment? gnss;
  final MotionSnapshot motion;
  final Map<SensorType, SensorStreamStats> sensorStats;

  /// Per-sensor fault state (§29). A sensor missing from the map was never
  /// seen on this device.
  final Map<SensorType, SensorDiagnosis> sensorFaults;

  /// Barometric height, or null when the phone has no barometer (§18).
  final BarometerEstimate? barometer;

  /// Sensors present but currently unusable.
  List<SensorType> get faultedSensors => sensorFaults.entries
      .where((e) => e.value.samples > 0 && !e.value.usable)
      .map((e) => e.key)
      .toList();

  /// 0..1, or null while the phone-to-vehicle transform is unknown (§6).
  final double? alignmentConfidence;

  /// Gyro-bias calibration quality, or null if never calibrated (§5).
  final double? calibrationQuality;

  final FusionContribution contribution;
  final SubsystemHealth ai;
  final SubsystemHealth mapMatch;

  /// Full matcher output including the runner-up roads (§21), or null
  /// when there is no road graph to match against.
  final MapMatchResult? mapMatchResult;

  /// The map-matched position, or null when the matcher declined to snap.
  /// Callers draw the raw fused position in that case — never a snap the
  /// matcher itself refused to make.
  double? get matchedLatitude =>
      mapMatchResult?.snapped == true ? mapMatchResult!.matchedLat : null;
  double? get matchedLongitude =>
      mapMatchResult?.snapped == true ? mapMatchResult!.matchedLon : null;

  final Duration outageDuration;
  final double outageDistanceM;

  final DataSource positionSource;
  final List<String> notes;

  bool get hasPosition => latitude != null && longitude != null;

  /// True only when the mount transform has genuinely converged (§6).
  bool get isMountCalibrated => (alignmentConfidence ?? 0) >= 0.6;

  /// Whether this solution is healthy enough to drive the position the user
  /// sees. The app hands over to the core on exactly this test, and the outage
  /// benchmark scores the core only while it holds — so both must share it.
  bool get canLeadPosition {
    if (!hasPosition || mode == NavMode.sensorFailure) return false;
    if (integrity == NavIntegrity.invalid || !isMountCalibrated) return false;
    final sigma = horizontalSigmaM;
    return sigma != null && sigma.isFinite;
  }

  double? get speedKmh => speedMps == null ? null : speedMps! * 3.6;
}

/// One navigation-mode transition, with the reason it happened (§25).
@immutable
class ModeTransition {
  const ModeTransition({
    required this.from,
    required this.to,
    required this.reason,
    required this.monotonicUs,
  });

  final NavMode from;
  final NavMode to;
  final String reason;
  final int monotonicUs;

  @override
  String toString() =>
      '${(monotonicUs / 1e6).toStringAsFixed(2)}s ${from.name} -> ${to.name}: '
      '$reason';
}
