import 'dart:math' as math;

import '../gnss/gnss_quality.dart';
import '../math/nav_math.dart';
import '../model/nav_snapshot.dart';
import '../motion/motion_classifier.dart' show VehicleClass;
import '../navigation_engine.dart';
import '../replay/drive_log.dart';
import 'outage_report.dart';

/// Scores GNSS-outage dead reckoning on any recorded drive (§39, §76).
///
/// **Truth is the phone's own GNSS.** For each start time the drive is replayed
/// with every fix from that moment on withheld, and what the core (and a naive
/// baseline) believed is compared with the fix that was withheld. That needs no
/// reference receiver, so it works on a log from any phone in any car, and it
/// scores the whole pipeline on data it never saw during the outage.
///
/// The floor under every number is the truth's own noise (a few metres, reported
/// in [LogProfile.medianTruthAccuracyM]); nothing smaller than that is resolved.
///
/// Two strategies are scored on identical windows:
///  * **hold velocity** - keep going at the last fix's speed and course. It is
///    what a product with no inertial filter does, so it is the bar to clear;
///  * **the navigation core** - only while it is healthy enough to lead, on the
///    same test the app uses ([NavigationSnapshot.canLeadPosition]).
class OutageBenchmark {
  const OutageBenchmark._();

  /// A marker with this label in a log says "score from here": the drive before
  /// it was set-up driving (mount calibration), not driving to be judged.
  static const startMarker = 'benchmark start';

  static OutageReport run(
    List<DriveRecord> records, {
    OutageBenchmarkConfig config = const OutageBenchmarkConfig(),
    String source = 'drive',
    void Function(double progress)? onProgress,
  }) {
    final watch = Stopwatch()..start();
    final truth = _truthFixes(records, config);
    final skipped = <SkipReason, int>{};
    final byDuration = {for (final d in config.durationsS) d: <OutageSample>[]};

    final profile = _profile(records, truth);
    final vehicleClass = profile.vehicle == 'twoWheeler'
        ? VehicleClass.twoWheeler
        : VehicleClass.car;
    final leadUs =
        truth.isEmpty ? null : _firstLeadUs(records, vehicleClass);
    var windows = 0;
    if (leadUs != null && records.isNotEmpty) {
      final markerUs = records
          .where((r) => r.type == DriveRecordType.marker && r.label == startMarker)
          .map((r) => r.monotonicUs)
          .fold<int>(leadUs, math.max);
      final starts = _startTimes(records.last.monotonicUs, leadUs, markerUs, config);
      windows = starts.length;
      for (var i = 0; i < starts.length; i++) {
        _pass(records, truth, starts[i], config, vehicleClass, byDuration,
            skipped);
        onProgress?.call((i + 1) / starts.length);
      }
    }

    return OutageReport(
      source: source,
      profile: profile,
      config: config,
      durations: [
        for (final entry in byDuration.entries)
          if (entry.value.isNotEmpty) DurationResult.of(entry.key, entry.value),
      ],
      windowsTried: windows,
      skipped: skipped,
      coreLedFromS:
          leadUs == null ? null : (leadUs - _firstSensorUs(records)) / 1e6,
      runtimeMs: watch.elapsedMilliseconds,
      vehicleClass: vehicleClass,
    );
  }

  /// Time of the first record that carries the phone's clock. A recorded log
  /// opens with a header stamped 0 while every sensor line uses the phone's own
  /// uptime (~1e15 us), so the header must not set the start of the drive.
  static int _firstSensorUs(List<DriveRecord> records) {
    for (final r in records) {
      if (r.type != DriveRecordType.meta) return r.monotonicUs;
    }
    return 0;
  }

  // ---------------------------------------------------------------- windows

  /// Start times from the moment the core could lead, spaced by the stride and
  /// widened so no more than [OutageBenchmarkConfig.maxStarts] replays run.
  static List<int> _startTimes(
      int endUs, int leadUs, int notBeforeUs, OutageBenchmarkConfig config) {
    final shortest = config.durationsS.reduce(math.min);
    final first =
        math.max(leadUs + config.settleAfterLeadS * 1000000, notBeforeUs);
    final last = endUs - shortest * 1000000;
    if (first > last) return const [];
    final stride = math.max(config.strideS * 1000000, (last - first) ~/ config.maxStarts);
    return [for (var t = first; t <= last; t += stride) t];
  }

  /// One replay: run normally to [startUs], then withhold GNSS and record what
  /// the core believed at every withheld fix, then score each duration.
  static void _pass(
    List<DriveRecord> records,
    List<_Fix> truth,
    int startUs,
    OutageBenchmarkConfig config,
    VehicleClass vehicleClass,
    Map<int, List<OutageSample>> out,
    Map<SkipReason, int> skipped,
  ) {
    // Only outage lengths that fit inside the recording are attempted; one
    // that runs past the end of the log is not a failure, just not measurable.
    final logEndUs = records.last.monotonicUs;
    final durations =
        out.keys.where((d) => startUs + d * 1000000 <= logEndUs).toList();
    if (durations.isEmpty) return;
    void skip(SkipReason reason, [int count = 1]) =>
        skipped[reason] = (skipped[reason] ?? 0) + count;

    final engine = NavigationEngine(vehicleClass: vehicleClass);
    var i = 0;
    while (i < records.length && records[i].monotonicUs < startUs) {
      _feed(engine, records[i++]);
    }
    if (!(engine.snapshot?.canLeadPosition ?? false)) {
      return skip(SkipReason.engineNotLeading, durations.length);
    }
    final originIndex = _lastAtOrBefore(truth, startUs);
    if (originIndex < 0 ||
        startUs - truth[originIndex].us > config.maxFixAgeS * 1000000) {
      return skip(SkipReason.noRecentFix, durations.length);
    }
    final origin = truth[originIndex];
    final hold = _Hold(origin, originIndex > 0 ? truth[originIndex - 1] : null);

    engine.onGnssLost(startUs);
    final marks = <_Mark>[];
    final endUs = startUs + durations.reduce(math.max) * 1000000;
    for (; i < records.length && records[i].monotonicUs <= endUs; i++) {
      final record = records[i];
      switch (record.type) {
        case DriveRecordType.imu:
          _feed(engine, record);
        case DriveRecordType.gnss:
          // Withheld from the core. Trusted fixes are kept as truth, and each
          // one keeps the core in outage the way a receiver-lost stream would.
          final fix = _asFix(record.fix!, config);
          if (fix == null) continue;
          final estimate = _estimate(engine, fix.us);
          if (estimate != null) marks.add(_Mark(fix, estimate));
          engine.onGnssLost(fix.us);
        case DriveRecordType.gnssLost:
          engine.onGnssLost(record.monotonicUs);
        default:
          break;
      }
    }

    for (final duration in durations) {
      final target = startUs + duration * 1000000;
      final k = marks.lastIndexWhere((m) => m.truth.us <= target);
      if (k < 0 || target - marks[k].truth.us > 2000000) {
        skip(SkipReason.noTruthAtEnd);
        continue;
      }
      final distance =
          _distance([origin, for (var j = 0; j <= k; j++) marks[j].truth]);
      if (distance < config.minDistanceM) {
        skip(SkipReason.tooLittleTravel);
        continue;
      }
      final m = marks[k];
      final held = hold.at(m.truth.us);
      out[duration]!.add(OutageSample(
        startUs: startUs,
        holdErrorM: _metres(held, m.truth.lat, m.truth.lon),
        engineErrorM: _metres(m.estimate.position, m.truth.lat, m.truth.lon),
        engineSigmaM: m.estimate.sigmaM,
        distanceM: distance,
      ));
    }
  }

  /// First moment the core is healthy enough to lead, replaying without any
  /// outage. Null when it never is - nothing can then be scored.
  static int? _firstLeadUs(List<DriveRecord> records, VehicleClass vehicleClass) {
    final engine = NavigationEngine(vehicleClass: vehicleClass);
    for (final record in records) {
      final snapshot = _feed(engine, record);
      if (snapshot != null && snapshot.canLeadPosition) {
        return record.monotonicUs;
      }
    }
    return null;
  }

  static NavigationSnapshot? _feed(NavigationEngine engine, DriveRecord r) {
    switch (r.type) {
      case DriveRecordType.imu:
        return engine.onImu(
          accelPhone: r.accel!,
          gyroPhone: r.gyro!,
          monotonicUs: r.monotonicUs,
          magPhone: r.mag,
          pressureHpa: r.pressureHpa,
          temperatureC: r.temperatureC,
        );
      case DriveRecordType.gnss:
        return engine.onGnss(r.fix!);
      case DriveRecordType.gnssLost:
        engine.onGnssLost(r.monotonicUs);
        return null;
      default:
        return null;
    }
  }

  // ------------------------------------------------------------------ truth

  static _Fix? _asFix(GnssObservation f, OutageBenchmarkConfig config) {
    if (f.isMocked || f.accuracyM > config.maxTruthAccuracyM) return null;
    return _Fix(f.monotonicUs, f.latitudeDeg, f.longitudeDeg, f.accuracyM,
        f.speedMps, f.bearingDeg);
  }

  static List<_Fix> _truthFixes(
      List<DriveRecord> records, OutageBenchmarkConfig config) {
    final fixes = <_Fix>[];
    for (final r in records) {
      if (r.type != DriveRecordType.gnss) continue;
      final fix = _asFix(r.fix!, config);
      if (fix != null) fixes.add(fix);
    }
    return fixes;
  }

  /// Index of the last fix at or before [us], or -1.
  static int _lastAtOrBefore(List<_Fix> fixes, int us) {
    var lo = 0;
    var hi = fixes.length - 1;
    var found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (fixes[mid].us <= us) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// Distance driven along [fixes]. Doppler speed where every fix has it - it
  /// is far less noisy than differencing positions, which at 1 Hz and a few
  /// metres of jitter overstates slow travel - and positions otherwise.
  static double _distance(List<_Fix> fixes) {
    final doppler = fixes.every((f) => f.speed != null);
    var total = 0.0;
    for (var i = 1; i < fixes.length; i++) {
      final a = fixes[i - 1];
      final b = fixes[i];
      total += doppler
          ? 0.5 * (a.speed! + b.speed!) * (b.us - a.us) / 1e6
          : NavMath.horizontalDistance(
              lat0: a.lat, lon0: a.lon, lat1: b.lat, lon1: b.lon);
    }
    return total;
  }

  // -------------------------------------------------------------- estimates

  /// What the core believed at [us]: its latest snapshot advanced by its own
  /// speed and heading over the (at most one UI period) since it was made.
  static _Estimate? _estimate(NavigationEngine engine, int us) {
    final s = engine.snapshot;
    if (s == null || !s.hasPosition) return null;
    var position = (s.latitude!, s.longitude!);
    final age = (us - s.monotonicUs) / 1e6;
    final speed = s.speedMps;
    final heading = s.headingDeg;
    if (age > 0 && age < 1 && speed != null && heading != null) {
      position = _advance(position, speed, heading, age);
    }
    return _Estimate(position, s.horizontalSigmaM ?? double.nan);
  }

  static (double, double) _advance(
      (double, double) from, double speed, double headingDeg, double seconds) {
    final h = headingDeg * NavMath.degToRad;
    final moved = NavMath.addNed(
      latDeg: from.$1,
      lonDeg: from.$2,
      altM: 0,
      north: speed * math.cos(h) * seconds,
      east: speed * math.sin(h) * seconds,
      down: 0,
    );
    return (moved[0], moved[1]);
  }

  static double _metres((double, double) at, double lat, double lon) =>
      NavMath.horizontalDistance(
          lat0: at.$1, lon0: at.$2, lat1: lat, lon1: lon);

  // ---------------------------------------------------------------- profile

  static LogProfile _profile(List<DriveRecord> records, List<_Fix> truth) {
    final imu = [
      for (final r in records)
        if (r.type == DriveRecordType.imu) r,
    ];
    final gnss = [
      for (final r in records)
        if (r.type == DriveRecordType.gnss) r.monotonicUs,
    ];
    final gaps = [
      for (var i = 1; i < imu.length; i++)
        (imu[i].monotonicUs - imu[i - 1].monotonicUs).toDouble(),
    ]..sort();
    final accuracy = [for (final f in truth) f.accuracyM]..sort();

    DriveMeta? meta;
    for (final r in records) {
      if (r.type == DriveRecordType.meta && r.meta != null) {
        meta = DriveMeta.fromJson(r.meta!);
        break;
      }
    }
    final spanUs =
        records.isEmpty ? 0 : records.last.monotonicUs - _firstSensorUs(records);
    return LogProfile(
      durationS: spanUs / 1e6,
      imuHz: gaps.isEmpty ? 0 : 1e6 / gaps[gaps.length ~/ 2],
      gnssHz: gnss.length < 2 ? 0 : (gnss.length - 1) * 1e6 / (gnss.last - gnss.first),
      gnssFixes: gnss.length,
      truthFixes: truth.length,
      medianTruthAccuracyM: accuracy.isEmpty ? double.nan : accuracy[accuracy.length ~/ 2],
      hasMagnetometer: imu.any((r) => r.mag != null),
      hasBarometer: imu.any((r) => r.pressureHpa != null),
      deviceModel: meta?.deviceModel,
      vehicle: meta?.vehicle,
    );
  }

}

/// A trusted fix.
class _Fix {
  const _Fix(
      this.us, this.lat, this.lon, this.accuracyM, this.speed, this.bearingDeg);

  final int us;
  final double lat;
  final double lon;
  final double accuracyM;
  final double? speed;
  final double? bearingDeg;
}

class _Estimate {
  const _Estimate(this.position, this.sigmaM);

  final (double, double) position;
  final double sigmaM;
}

/// The core's belief at the moment a fix was withheld, next to that fix.
class _Mark {
  const _Mark(this.truth, this.estimate);

  final _Fix truth;
  final _Estimate estimate;
}

/// The baseline: keep going at the last fix's speed and course.
class _Hold {
  _Hold(this.origin, _Fix? previous) {
    var speed = origin.speed;
    var bearing = origin.bearingDeg;
    final gap = previous == null ? 0 : (origin.us - previous.us) / 1e6;
    if (previous != null && gap > 0 && gap <= 3) {
      final d = NavMath.nedBetween(
        lat0: previous.lat,
        lon0: previous.lon,
        alt0: 0,
        lat1: origin.lat,
        lon1: origin.lon,
        alt1: 0,
      );
      final moved = math.sqrt(d.x * d.x + d.y * d.y);
      speed ??= moved / gap;
      if (bearing == null && moved > 3) {
        bearing = NavMath.wrap360(math.atan2(d.y, d.x) * NavMath.radToDeg);
      }
    }
    // Below walking pace a course is noise; standing still is the better bet.
    _speed = (speed ?? 0) > 1 && bearing != null ? speed! : 0;
    _bearing = bearing ?? 0;
  }

  final _Fix origin;
  late final double _speed;
  late final double _bearing;

  (double, double) at(int us) {
    final position = (origin.lat, origin.lon);
    if (_speed == 0) return position;
    return OutageBenchmark._advance(
        position, _speed, _bearing, (us - origin.us) / 1e6);
  }
}
