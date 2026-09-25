import 'package:flutter/foundation.dart';

import '../../../core/nav/gnss/gnss_health.dart';
import '../../../core/nav/model/nav_snapshot.dart' show NavIntegrity;
import '../../../core/nav/sensors/sensor_health.dart';

/// One readiness row's traffic-light state. Icon + text in the UI, never
/// colour alone (root CLAUDE.md accessibility note).
enum ReadinessStatus { ok, warn, notReady }

/// Overall read of a [DrReadinessReport].
enum DrReadinessLevel { ready, partiallyReady, notReady }

extension DrReadinessLevelLabel on DrReadinessLevel {
  String get label => switch (this) {
        DrReadinessLevel.ready => 'Dead reckoning ready',
        DrReadinessLevel.partiallyReady => 'Partially ready',
        DrReadinessLevel.notReady => 'Not ready',
      };
}

/// One line of the "GNSS Loss Preparation" checklist.
@immutable
class ReadinessRow {
  const ReadinessRow(
      {required this.label, required this.status, required this.reason});

  final String label;
  final ReadinessStatus status;

  /// Short driver-facing reason, always present (never a bare icon).
  final String reason;
}

/// Everything [evaluateDrReadiness] needs, gathered from the controller.
/// Immutable so the classification can be unit-tested without one running.
@immutable
class DrReadinessInput {
  const DrReadinessInput({
    required this.alignmentConverged,
    required this.recalibratingMount,
    required this.hardwareCheck,
    required this.roadAvailable,
    required this.gnssHealth,
    required this.engineLeading,
    required this.integrity,
    this.gnssSpeedStdMps,
    this.speedKnown = false,
    this.gnssAccuracyM,
  });

  final bool alignmentConverged;
  final bool recalibratingMount;

  /// The Navigation Hardware Check report; only its accel/gyro/sampling rows
  /// are read here (mount stability and magnetic interference belong to
  /// alignment and are not re-litigated here).
  final SensorHealthReport hardwareCheck;

  /// Whether a road within the lock radius is available on the installed map
  /// (`RoadConstraint` would find a candidate right now).
  final bool roadAvailable;

  final GnssHealthAssessment gnssHealth;
  final bool engineLeading;
  final NavIntegrity integrity;

  /// GNSS speed standard deviation over the last ~5 s, or null with too few
  /// samples to say.
  final double? gnssSpeedStdMps;
  final bool speedKnown;

  /// The receiver's last reported horizontal accuracy (m), or null.
  final double? gnssAccuracyM;
}

/// The full checklist plus the overall verdict.
@immutable
class DrReadinessReport {
  const DrReadinessReport({
    required this.alignment,
    required this.imu,
    required this.roadLock,
    required this.velocity,
    required this.gnssQuality,
    required this.overall,
  });

  final ReadinessRow alignment;
  final ReadinessRow imu;
  final ReadinessRow roadLock;
  final ReadinessRow velocity;
  final ReadinessRow gnssQuality;
  final DrReadinessLevel overall;

  List<ReadinessRow> get rows => [alignment, imu, roadLock, velocity, gnssQuality];
}

/// Thresholds for the readiness checklist, named and justified — mirrors
/// `NavSafetyThresholds` in `navigation_safety.dart`, which lives in this
/// same domain layer rather than `NavConfig` for the same reason (it reads
/// both the heuristic pipeline and the core's snapshot).
class DrReadinessThresholds {
  const DrReadinessThresholds._();

  /// GNSS accuracy (m) at or below which "GNSS quality" reads OK.
  static const double goodAccuracyM = 15.0;

  /// GNSS accuracy (m) at or below which "GNSS quality" reads WARN rather
  /// than NOT READY. Matches `GnssConfig.degradedAccuracy`.
  static const double degradedAccuracyM = 50.0;

  /// Speed standard deviation (m/s) at or below which "Velocity stable"
  /// reads OK.
  static const double stableSpeedStdMps = 1.0;

  /// Speed standard deviation (m/s) at or below which "Velocity stable"
  /// reads WARN rather than NOT READY.
  static const double settlingSpeedStdMps = 2.5;
}

const _imuCheckNames = {'Sampling rate', 'Timestamp jitter', 'Gyro bias stability'};

ReadinessRow _alignmentRow(DrReadinessInput i) {
  if (i.alignmentConverged) {
    return const ReadinessRow(
        label: 'Alignment',
        status: ReadinessStatus.ok,
        reason: 'Phone-to-vehicle mount converged');
  }
  if (i.recalibratingMount) {
    return const ReadinessRow(
        label: 'Alignment',
        status: ReadinessStatus.warn,
        reason: 'Mount recalibrating');
  }
  return const ReadinessRow(
      label: 'Alignment',
      status: ReadinessStatus.notReady,
      reason: 'Mount alignment has not converged yet');
}

ReadinessRow _imuRow(DrReadinessInput i) {
  final checks = i.hardwareCheck.checks
      .where((c) => _imuCheckNames.contains(c.name))
      .toList();
  if (checks.isEmpty || checks.any((c) => c.verdict == HealthVerdict.pending)) {
    return const ReadinessRow(
        label: 'IMU healthy',
        status: ReadinessStatus.notReady,
        reason: 'Sensor health not measured yet');
  }
  if (checks.any((c) => c.verdict == HealthVerdict.fail)) {
    final reason = checks.firstWhere((c) => c.verdict == HealthVerdict.fail).reason;
    return ReadinessRow(
        label: 'IMU healthy',
        status: ReadinessStatus.notReady,
        reason: reason ?? 'Accel/gyro check failing');
  }
  if (checks.any((c) => c.verdict == HealthVerdict.degraded)) {
    final reason =
        checks.firstWhere((c) => c.verdict == HealthVerdict.degraded).reason;
    return ReadinessRow(
        label: 'IMU healthy',
        status: ReadinessStatus.warn,
        reason: reason ?? 'Accel/gyro degraded');
  }
  return const ReadinessRow(
      label: 'IMU healthy', status: ReadinessStatus.ok, reason: 'Accel/gyro nominal');
}

ReadinessRow _roadLockRow(DrReadinessInput i) => i.roadAvailable
    ? const ReadinessRow(
        label: 'Road lock available',
        status: ReadinessStatus.ok,
        reason: 'A mapped road is within lock range')
    : const ReadinessRow(
        label: 'Road lock available',
        status: ReadinessStatus.notReady,
        reason: 'No mapped road nearby');

ReadinessRow _velocityRow(DrReadinessInput i) {
  if (!i.speedKnown) {
    return const ReadinessRow(
        label: 'Velocity stable',
        status: ReadinessStatus.notReady,
        reason: 'Speed not known yet');
  }
  final std = i.gnssSpeedStdMps;
  if (std == null) {
    return const ReadinessRow(
        label: 'Velocity stable',
        status: ReadinessStatus.warn,
        reason: 'Not enough recent fixes to judge');
  }
  if (std <= DrReadinessThresholds.stableSpeedStdMps) {
    return ReadinessRow(
        label: 'Velocity stable',
        status: ReadinessStatus.ok,
        reason: 'Speed steady (±${std.toStringAsFixed(1)} m/s)');
  }
  if (std <= DrReadinessThresholds.settlingSpeedStdMps) {
    return ReadinessRow(
        label: 'Velocity stable',
        status: ReadinessStatus.warn,
        reason: 'Speed still settling (±${std.toStringAsFixed(1)} m/s)');
  }
  return ReadinessRow(
      label: 'Velocity stable',
      status: ReadinessStatus.notReady,
      reason: 'Speed changing fast (±${std.toStringAsFixed(1)} m/s)');
}

ReadinessRow _gnssQualityRow(DrReadinessInput i) {
  final state = i.gnssHealth.state;
  if (state == GnssHealthState.waiting || state == GnssHealthState.outage) {
    return const ReadinessRow(
        label: 'GNSS quality',
        status: ReadinessStatus.notReady,
        reason: 'No live GNSS fix');
  }
  if (state == GnssHealthState.multipathSuspected ||
      state == GnssHealthState.interferenceSuspected) {
    return ReadinessRow(
        label: 'GNSS quality',
        status: ReadinessStatus.notReady,
        reason: state.label);
  }
  final acc = i.gnssAccuracyM;
  if (state == GnssHealthState.normal &&
      (acc == null || acc <= DrReadinessThresholds.goodAccuracyM)) {
    return ReadinessRow(
        label: 'GNSS quality',
        status: ReadinessStatus.ok,
        reason: acc == null ? 'Normal' : 'Accuracy ±${acc.round()} m');
  }
  if (acc != null && acc > DrReadinessThresholds.degradedAccuracyM) {
    return ReadinessRow(
        label: 'GNSS quality',
        status: ReadinessStatus.notReady,
        reason: 'Accuracy ±${acc.round()} m');
  }
  return ReadinessRow(
      label: 'GNSS quality',
      status: ReadinessStatus.warn,
      reason: acc == null ? state.label : 'Accuracy ±${acc.round()} m');
}

DrReadinessLevel _overallOf(List<ReadinessRow> rows, DrReadinessInput i) {
  if (i.integrity == NavIntegrity.invalid) return DrReadinessLevel.notReady;
  final notReady = rows.where((r) => r.status == ReadinessStatus.notReady).length;
  final warn = rows.where((r) => r.status == ReadinessStatus.warn).length;
  if (notReady == 0 && warn == 0) return DrReadinessLevel.ready;
  if (notReady == 0) return DrReadinessLevel.partiallyReady;
  return DrReadinessLevel.notReady;
}

/// Pure classification, no state — see `GnssLossPreparation` for the
/// stateful Preparation Mode this feeds.
DrReadinessReport evaluateDrReadiness(DrReadinessInput i) {
  final alignment = _alignmentRow(i);
  final imu = _imuRow(i);
  final roadLock = _roadLockRow(i);
  final velocity = _velocityRow(i);
  final gnssQuality = _gnssQualityRow(i);
  return DrReadinessReport(
    alignment: alignment,
    imu: imu,
    roadLock: roadLock,
    velocity: velocity,
    gnssQuality: gnssQuality,
    overall: _overallOf([alignment, imu, roadLock, velocity, gnssQuality], i),
  );
}
