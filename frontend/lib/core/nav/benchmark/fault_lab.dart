import 'dart:math' as math;

import '../gnss/gnss_quality.dart';
import '../map/road_graph.dart';
import '../math/nav_math.dart';
import '../model/nav_snapshot.dart';
import '../motion/motion_classifier.dart' show VehicleClass;
import '../nav_config.dart';
import '../replay/drive_log.dart';
import '../replay/replay_engine.dart';
import '../sensors/sensor_fault_detector.dart';
import '../sensors/sensor_sample.dart';
import 'fault_injection.dart';

/// What the lab saw a fault do to one replayed drive (§ Fault Injection Lab).
///
/// Honest by construction: [detected] is false whenever nothing in the
/// engine's own state noticed the fault, and [action] then says so rather
/// than inventing a save.
class FaultLabResult {
  const FaultLabResult({
    required this.injected,
    required this.detected,
    required this.detectionLatencyS,
    required this.mechanism,
    required this.action,
    required this.maxErrorM,
    required this.endErrorM,
    required this.keptLeading,
  });

  /// Human text for what was injected, e.g. "GNSS position offset +120 m for
  /// 20 s at t=60 s".
  final String injected;

  final bool detected;

  /// Seconds from the fault's start to the first sign of it, or null when
  /// never detected.
  final double? detectionLatencyS;

  /// Plain-language mechanism, e.g. "GNSS measurement rejected (impossible
  /// jump)", or "Not detected" when nothing fired.
  final String mechanism;

  /// What the engine did about it, in one sentence.
  final String action;

  /// Worst and final horizontal separation between the faulted run and a
  /// clean replay of the same log, metres.
  final double maxErrorM;
  final double endErrorM;

  /// Whether `canLeadPosition` stayed true through the fault and its
  /// aftermath.
  final bool keptLeading;
}

/// Replays a drive twice - once clean, once with a [FaultSpec] injected - and
/// reports whether the navigation core noticed.
class FaultLab {
  const FaultLab._();

  /// How long after the fault window ends the lab keeps watching for a
  /// delayed sign of it (the GNSS integrity monitor needs a few more strikes
  /// after a ramp stops moving before it calls anomaly).
  static const _detectionGraceS = 8.0;

  static FaultLabResult run(
    List<DriveRecord> records,
    FaultSpec spec, {
    NavConfig config = NavConfig.defaults,
    VehicleClass vehicleClass = VehicleClass.car,
    RoadGraph? roadGraph,
  }) {
    final faulted = FaultInjector.apply(records, spec);

    final clean = ReplayEngine(
        records: records,
        config: config,
        vehicleClass: vehicleClass,
        roadGraph: roadGraph);
    final cleanTrack = <int, (double, double)>{};
    while (true) {
      final step = clean.stepOnce();
      if (step == null) break;
      final snap = clean.engine.snapshot;
      if (snap != null && snap.hasPosition) {
        cleanTrack[step.record.monotonicUs] = (snap.latitude!, snap.longitude!);
      }
    }

    final firstSensorUs = _firstSensorUs(records);
    final startUs = firstSensorUs + (spec.startS * 1e6).round();
    final endUs = startUs + (spec.durationS * 1e6).round();
    final graceUs = endUs + (_detectionGraceS * 1e6).round();

    final dirty = ReplayEngine(
        records: faulted,
        config: config,
        vehicleClass: vehicleClass,
        roadGraph: roadGraph);

    String? mechanism;
    int? detectionUs;
    var leadDropped = false;
    var wasLeading = true;
    var maxErrorM = 0.0;
    var endErrorM = 0.0;

    while (true) {
      final step = dirty.stepOnce();
      if (step == null) break;
      final us = step.record.monotonicUs;
      final snap = dirty.engine.snapshot;
      if (snap == null) continue;

      final cleanPos = cleanTrack[us];
      if (cleanPos != null && snap.hasPosition && us >= startUs) {
        final err = NavMath.horizontalDistance(
          lat0: cleanPos.$1,
          lon0: cleanPos.$2,
          lat1: snap.latitude!,
          lon1: snap.longitude!,
        );
        maxErrorM = math.max(maxErrorM, err);
        endErrorM = err;
      }

      if (us < startUs || us > graceUs) continue;

      mechanism ??= _mechanismFor(snap);
      if (mechanism != null) detectionUs ??= us;

      if (wasLeading && !snap.canLeadPosition) {
        leadDropped = true;
        wasLeading = false;
        detectionUs ??= us;
        mechanism ??= 'Navigation integrity dropped below the hand-over bar';
      }
    }

    final detected = mechanism != null;
    return FaultLabResult(
      injected: spec.describe(),
      detected: detected,
      detectionLatencyS:
          detectionUs == null ? null : (detectionUs - startUs) / 1e6,
      mechanism: mechanism ?? 'Not detected',
      action: _actionFor(
        detected: detected,
        leadDropped: leadDropped,
        mechanism: mechanism,
        maxErrorM: maxErrorM,
      ),
      maxErrorM: maxErrorM,
      endErrorM: endErrorM,
      keptLeading: !leadDropped,
    );
  }

  /// What in this snapshot is evidence the fault was noticed, or null.
  static String? _mechanismFor(NavigationSnapshot snap) {
    final assessment = snap.gnss;
    if (assessment != null && !assessment.usable) {
      return 'GNSS measurement rejected (${assessment.reason.name})';
    }
    if (assessment != null && assessment.integrity == GnssIntegrity.anomaly) {
      return assessment.integrity.label; // "GNSS integrity anomaly detected"
    }
    for (final entry in snap.sensorFaults.entries) {
      if (entry.value.samples > 0 && !entry.value.usable) {
        return '${entry.key.label}: ${entry.value.fault.label}';
      }
    }
    // Read-only detectors that catch what the gates above miss (gyro/accel
    // bias, a slow GNSS drift, timestamp latency) — see `FaultMonitor`.
    if (snap.faultFlags.isNotEmpty) return snap.faultFlags.first.mechanism;
    return null;
  }

  static String _actionFor({
    required bool detected,
    required bool leadDropped,
    required String? mechanism,
    required double maxErrorM,
  }) {
    if (!detected) {
      return 'Not detected - position was pulled '
          '${maxErrorM.toStringAsFixed(0)} m';
    }
    if (mechanism != null && mechanism.contains('rejected')) {
      return 'GNSS measurement rejected, dead reckoning maintained';
    }
    if (mechanism != null && mechanism.contains('Magnetic')) {
      return 'Magnetometer excluded from heading';
    }
    if (leadDropped) {
      return 'Engine handed back to the GNSS pipeline';
    }
    if (mechanism != null && _monitorMechanisms.contains(mechanism)) {
      // FaultMonitor is read-only by construction: it can never correct the
      // filter, only flag it (§ Fault Injection Lab honesty rule).
      return 'Flagged to the driver; no correction applied '
          '(position pulled ${maxErrorM.toStringAsFixed(0)} m)';
    }
    return 'Flagged but still used - error not fully contained '
        '(${maxErrorM.toStringAsFixed(0)} m)';
  }

  /// Mechanism tags that come from `FaultMonitor` rather than an existing
  /// gate — used only to pick the honest "flagged, not corrected" wording.
  static const _monitorMechanisms = {
    'Gyro bias suspected',
    'Accelerometer bias suspected',
    'GNSS integrity anomaly detected',
    'GNSS timestamp latency suspected',
    'EKF gyro-bias estimate jump',
  };

  static int _firstSensorUs(List<DriveRecord> records) {
    for (final r in records) {
      if (r.type != DriveRecordType.meta) return r.monotonicUs;
    }
    return 0;
  }
}
