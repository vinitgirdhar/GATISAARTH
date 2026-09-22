import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../calibration/sensor_calibration.dart';
import '../map/road_graph.dart';
import '../math/nav_math.dart';
import '../model/nav_snapshot.dart';
import '../motion/motion_classifier.dart';
import '../nav_config.dart';
import '../navigation_engine.dart';
import 'ai_record_feed.dart';
import 'drive_log.dart';

/// One step of a replay: what was fed in and what came out.
@immutable
class ReplayStep {
  const ReplayStep({
    required this.record,
    required this.index,
    this.snapshot,
    this.truthLat,
    this.truthLon,
    this.errorM,
  });

  final DriveRecord record;
  final int index;

  /// Null when this record did not produce a new snapshot.
  final NavigationSnapshot? snapshot;

  final double? truthLat;
  final double? truthLon;

  /// Distance from the estimate to ground truth, when the log has truth.
  final double? errorM;
}

/// Summary of a whole replay, scored against ground truth where the log has it.
@immutable
class ReplaySummary {
  const ReplaySummary({
    required this.records,
    required this.snapshots,
    required this.duration,
    required this.markers,
    required this.modeTransitions,
    this.finalSnapshot,
    this.finalErrorM,
    this.maxErrorM,
    this.meanErrorM,
    this.p95ErrorM,
    this.truthSamples = 0,
  });

  final int records;
  final int snapshots;
  final Duration duration;

  /// Labelled events from the log, in order.
  final List<DriveRecord> markers;

  final List<ModeTransition> modeTransitions;
  final NavigationSnapshot? finalSnapshot;

  /// Null when the log carries no ground truth — most real drives will not.
  final double? finalErrorM;
  final double? maxErrorM;
  final double? meanErrorM;
  final double? p95ErrorM;
  final int truthSamples;

  bool get hasGroundTruth => truthSamples > 0;
}

/// Replays a drive log through the navigation engine (§37).
///
/// Deterministic by construction: the engine has no clock, no timers and no
/// randomness, and the log stores every sensor value at full double precision.
/// The same log therefore produces byte-identical output every time, and the
/// output of a replay matches the live run that recorded it. That is what
/// makes a drift regression attributable to a code change rather than to the
/// weather on the day.
///
/// Playback *speed* is not here. This class steps through records as fast as
/// it is asked to; a player that wants 0.5x or 10x drives it from a timer, and
/// pause is simply not calling [stepOnce]. Keeping the timing outside is what
/// lets a test replay an hour of driving in a second.
class ReplayEngine {
  ReplayEngine({
    required List<DriveRecord> records,
    NavConfig config = NavConfig.defaults,
    SensorCalibration? calibration,
    VehicleClass vehicleClass = VehicleClass.car,
    RoadGraph? roadGraph,
  })  : _records = records,
        engine = NavigationEngine(
          config: config,
          calibration: calibration,
          vehicleClass: vehicleClass,
          roadGraph: roadGraph,
        ) {
    for (final record in records) {
      if (record.type == DriveRecordType.meta && record.meta != null) {
        meta = DriveMeta.fromJson(record.meta!);
        break;
      }
    }
  }

  /// Parses a whole log. Unreadable lines are skipped and counted rather than
  /// aborting: a drive that ended when the battery died is still worth
  /// replaying up to that point.
  factory ReplayEngine.fromLines(
    Iterable<String> lines, {
    NavConfig config = NavConfig.defaults,
    SensorCalibration? calibration,
    VehicleClass vehicleClass = VehicleClass.car,
    RoadGraph? roadGraph,
  }) {
    final records = <DriveRecord>[];
    var skipped = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final record = DriveRecord.fromJsonLine(line);
      if (record == null) {
        skipped++;
      } else {
        records.add(record);
      }
    }
    return ReplayEngine(
      records: records,
      config: config,
      calibration: calibration,
      vehicleClass: vehicleClass,
      roadGraph: roadGraph,
    ).._skippedLines = skipped;
  }

  final List<DriveRecord> _records;

  /// The engine under replay. Inspect it freely between steps.
  final NavigationEngine engine;

  DriveMeta? meta;
  int _skippedLines = 0;
  int _index = 0;
  int _snapshots = 0;

  double? _truthLat;
  double? _truthLon;
  final List<double> _errors = [];
  final List<DriveRecord> _markers = [];

  int get skippedLines => _skippedLines;
  int get recordCount => _records.length;
  int get index => _index;
  bool get isFinished => _index >= _records.length;

  /// 0..1 through the log.
  double get progress =>
      _records.isEmpty ? 1 : (_index / _records.length).clamp(0.0, 1.0);

  int? get currentUs =>
      _index == 0 || _records.isEmpty ? null : _records[_index - 1].monotonicUs;

  /// Feeds the next record. Returns null once the log is exhausted.
  ReplayStep? stepOnce() {
    if (isFinished) return null;
    final record = _records[_index];
    final snapshot = _feed(record);
    if (snapshot != null) _snapshots++;

    final error = _errorFor(snapshot);
    if (error != null) _errors.add(error);

    final step = ReplayStep(
      record: record,
      index: _index,
      snapshot: snapshot,
      truthLat: _truthLat,
      truthLon: _truthLon,
      errorM: error,
    );
    _index++;
    return step;
  }

  /// Runs to the end and scores the result.
  ReplaySummary runToEnd() {
    while (stepOnce() != null) {}
    return summary();
  }

  /// Runs until the log reaches [monotonicUs].
  void runTo(int monotonicUs) {
    while (!isFinished && _records[_index].monotonicUs <= monotonicUs) {
      stepOnce();
    }
  }

  /// Restarts from the beginning with a fresh engine state.
  void reset() {
    engine.reset();
    _index = 0;
    _snapshots = 0;
    _truthLat = null;
    _truthLon = null;
    _errors.clear();
    _markers.clear();
  }

  /// Rewinds and replays up to [monotonicUs].
  ///
  /// A filter has no inverse, so seeking backwards means replaying forwards
  /// from the start. At an hour of log that is still well under a second.
  void seekTo(int monotonicUs) {
    reset();
    runTo(monotonicUs);
  }

  ReplaySummary summary() {
    final sorted = List<double>.from(_errors)..sort();
    // The header is stamped 0; the drive starts at the first sensor line.
    final first = _records
        .firstWhere((r) => r.type != DriveRecordType.meta,
            orElse: () => _records.isEmpty
                ? const DriveRecord(type: DriveRecordType.meta, monotonicUs: 0)
                : _records.first)
        .monotonicUs;
    final last = _records.isEmpty ? 0 : _records.last.monotonicUs;
    return ReplaySummary(
      records: _records.length,
      snapshots: _snapshots,
      duration: Duration(microseconds: math.max(0, last - first)),
      markers: List.unmodifiable(_markers),
      modeTransitions: engine.transitions,
      finalSnapshot: engine.snapshot,
      finalErrorM: _errors.isEmpty ? null : _errors.last,
      maxErrorM: sorted.isEmpty ? null : sorted.last,
      meanErrorM: sorted.isEmpty
          ? null
          : sorted.reduce((a, b) => a + b) / sorted.length,
      p95ErrorM: sorted.isEmpty
          ? null
          : sorted[math.min(sorted.length - 1, (sorted.length * 0.95).floor())],
      truthSamples: _errors.length,
    );
  }

  NavigationSnapshot? _feed(DriveRecord record) {
    switch (record.type) {
      case DriveRecordType.imu:
        return engine.onImu(
          accelPhone: record.accel!,
          gyroPhone: record.gyro!,
          monotonicUs: record.monotonicUs,
          magPhone: record.mag,
          pressureHpa: record.pressureHpa,
          temperatureC: record.temperatureC,
        );
      case DriveRecordType.gnss:
        return engine.onGnss(record.fix!);
      case DriveRecordType.gnssLost:
        engine.onGnssLost(record.monotonicUs);
        return null;
      case DriveRecordType.gnssReceiver:
        // Diagnostic evidence: the replayed navigation state is driven by the
        // recorded fixes and IMU, not by receiver presentation metadata.
        return null;
      case DriveRecordType.truth:
        _truthLat = record.latitude;
        _truthLon = record.longitude;
        return null;
      case DriveRecordType.marker:
        _markers.add(record);
        return null;
      case DriveRecordType.ai:
        feedAiRecord(engine, record);
        return null;
      case DriveRecordType.meta:
        return null;
    }
  }

  double? _errorFor(NavigationSnapshot? snapshot) {
    if (snapshot == null || !snapshot.hasPosition) return null;
    final lat = _truthLat;
    final lon = _truthLon;
    if (lat == null || lon == null) return null;
    return NavMath.horizontalDistance(
      lat0: lat,
      lon0: lon,
      lat1: snapshot.latitude!,
      lon1: snapshot.longitude!,
    );
  }
}
