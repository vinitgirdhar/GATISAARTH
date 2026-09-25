import 'dart:math' as math;

import '../motion/motion_classifier.dart' show VehicleClass;

/// How the benchmark is run. Every threshold that decides whether a window
/// counts lives here, so a result can always be traced to the rules that made it.
class OutageBenchmarkConfig {
  const OutageBenchmarkConfig({
    this.durationsS = const [10, 30, 60, 120],
    this.strideS = 20,
    this.maxStarts = 16,
    this.settleAfterLeadS = 10,
    this.maxTruthAccuracyM = 12,
    this.maxFixAgeS = 3,
    this.minDistanceM = 30,
  });

  /// Outage lengths scored. All are read from one replay per start time: the
  /// engine cannot see the future, so its state 10 s into a 120 s outage is
  /// identical to its state at the end of a 10 s one.
  final List<int> durationsS;

  /// Gap between outage start times.
  final int strideS;

  /// Upper bound on replays, so a long recording cannot run for minutes; the
  /// stride widens to fit.
  final int maxStarts;

  /// Seconds the core must already have been leading before an outage starts.
  final int settleAfterLeadS;

  /// A fix reporting worse accuracy than this is not trusted as truth.
  final double maxTruthAccuracyM;

  /// The fix the baseline extrapolates from must be at most this old.
  final double maxFixAgeS;

  /// Outages over less travel than this are not scored: a parked car has no
  /// drift to measure, and dividing by a few metres makes noise look like error.
  final double minDistanceM;
}

/// Why a window (or one duration of it) did not count. Reported, never hidden.
enum SkipReason {
  /// The core was not healthy enough to lead when the outage began.
  engineNotLeading,

  /// No trusted fix shortly before the outage to extrapolate from.
  noRecentFix,

  /// The vehicle barely moved.
  tooLittleTravel,

  /// No trusted fix near the end of the outage to score against.
  noTruthAtEnd,
}

/// One scored outage: how far each strategy ended up from the fix it was denied.
class OutageSample {
  const OutageSample({
    required this.startUs,
    required this.holdErrorM,
    required this.engineErrorM,
    required this.engineSigmaM,
    required this.distanceM,
    this.alongTrackErrorM = double.nan,
    this.crossTrackErrorM = double.nan,
    this.maxSigmaM = double.nan,
    this.recoveryJumpM,
  });

  final int startUs;
  final double holdErrorM;
  final double engineErrorM;

  /// What the core itself claimed its uncertainty was at the end.
  final double engineSigmaM;

  /// Distance travelled during the outage, from Doppler speed where the phone
  /// reports it and from positions otherwise.
  final double distanceM;

  /// The core's error at the end of the outage, decomposed against the
  /// truth's own direction of travel there: along the route and across it.
  /// A DR filter that is merely a little late along the road (along-track)
  /// is a very different failure from one that has left the lane
  /// (cross-track) - `double.nan` when no direction of travel could be read.
  final double alongTrackErrorM;
  final double crossTrackErrorM;

  /// The core's own largest reported 1-sigma over the whole window, not just
  /// at the end - a filter that is briefly far more confident than it should
  /// be mid-outage would otherwise be invisible in an end-of-window number.
  final double maxSigmaM;

  /// Distance between the core's dead-reckoned belief right before the next
  /// real fix after this window and the fused position right after it -
  /// null when the log has no such fix to replay (e.g. it is the last one).
  final double? recoveryJumpM;
}

/// Error statistics for one strategy at one outage length.
class OutageStats {
  const OutageStats({
    required this.n,
    required this.medianM,
    required this.p95M,
    required this.worstM,
    required this.medianDriftPct,
  });

  factory OutageStats.of(List<double> errorsM, List<double> distancesM) {
    if (errorsM.isEmpty) {
      return const OutageStats(
        n: 0,
        medianM: double.nan,
        p95M: double.nan,
        worstM: double.nan,
        medianDriftPct: double.nan,
      );
    }
    final drift = [
      for (var i = 0; i < errorsM.length; i++)
        100 * errorsM[i] / distancesM[i],
    ];
    final sorted = List<double>.of(errorsM)..sort();
    return OutageStats(
      n: errorsM.length,
      medianM: _median(sorted),
      p95M: sorted[math.min(sorted.length - 1, (sorted.length * 0.95).floor())],
      worstM: sorted.last,
      medianDriftPct: _median(List<double>.of(drift)..sort()),
    );
  }

  final int n;
  final double medianM;
  final double p95M;
  final double worstM;

  /// Median of error / distance travelled, in percent.
  final double medianDriftPct;

  static double _median(List<double> sorted) {
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

/// Median of the finite values in [values], or `double.nan` if none are.
double _medianFinite(Iterable<double> values) {
  final finite = values.where((v) => v.isFinite).toList()..sort();
  if (finite.isEmpty) return double.nan;
  return OutageStats._median(finite);
}

/// Both strategies at one outage length, scored on the same windows.
class DurationResult {
  const DurationResult({
    required this.durationS,
    required this.hold,
    required this.engine,
    required this.engineWins,
    required this.engineCovered,
    this.medianAlongTrackM = double.nan,
    this.medianCrossTrackM = double.nan,
    this.medianMaxSigmaM = double.nan,
    this.medianRecoveryJumpM = double.nan,
    this.medianDistanceM = double.nan,
  });

  factory DurationResult.of(int durationS, List<OutageSample> samples) {
    final distances = [for (final s in samples) s.distanceM];
    return DurationResult(
      durationS: durationS,
      hold: OutageStats.of([for (final s in samples) s.holdErrorM], distances),
      engine:
          OutageStats.of([for (final s in samples) s.engineErrorM], distances),
      engineWins: samples.where((s) => s.engineErrorM < s.holdErrorM).length,
      engineCovered: samples
          .where((s) => s.engineErrorM <= 3 * s.engineSigmaM)
          .length,
      medianAlongTrackM:
          _medianFinite(samples.map((s) => s.alongTrackErrorM.abs())),
      medianCrossTrackM:
          _medianFinite(samples.map((s) => s.crossTrackErrorM.abs())),
      medianMaxSigmaM: _medianFinite(samples.map((s) => s.maxSigmaM)),
      medianRecoveryJumpM:
          _medianFinite(samples.map((s) => s.recoveryJumpM ?? double.nan)),
      medianDistanceM: _medianFinite(distances),
    );
  }

  final int durationS;

  /// Baseline: keep going at the last fix's speed and course.
  final OutageStats hold;

  /// The navigation core.
  final OutageStats engine;

  /// Windows where the core ended closer to the truth than the baseline.
  final int engineWins;

  /// Windows where the core's own 3-sigma covered its real error. A wrong
  /// answer that knows it is wrong is usable; a wrong, confident one is not.
  final int engineCovered;

  /// Median of the core's along-track / cross-track error magnitude at the
  /// end of the outage, and of its own largest reported sigma over the
  /// window, and of the recovery jump when the log allowed measuring it.
  /// `double.nan` when no window in this bucket carried the data.
  final double medianAlongTrackM;
  final double medianCrossTrackM;
  final double medianMaxSigmaM;
  final double medianRecoveryJumpM;

  /// Median distance travelled during the windows scored at this duration.
  final double medianDistanceM;

  int get n => engine.n;

  /// SIH26168's bar: median drift below [targetPct] of distance travelled.
  bool passed(double targetPct) =>
      engine.medianDriftPct.isFinite && engine.medianDriftPct < targetPct;
}

/// What the recording says about the phone that made it. Results only mean
/// something next to these: a 10 Hz IMU or a 30 m GNSS floor changes the answer.
class LogProfile {
  const LogProfile({
    required this.durationS,
    required this.imuHz,
    required this.gnssHz,
    required this.gnssFixes,
    required this.truthFixes,
    required this.medianTruthAccuracyM,
    required this.hasMagnetometer,
    required this.hasBarometer,
    this.deviceModel,
    this.vehicle,
  });

  final double durationS;
  final double imuHz;
  final double gnssHz;
  final int gnssFixes;

  /// Fixes accurate enough to score against.
  final int truthFixes;

  /// The floor under every error figure: the truth itself is this noisy.
  final double medianTruthAccuracyM;

  final bool hasMagnetometer;
  final bool hasBarometer;
  final String? deviceModel;

  /// The vehicle the recording says it was made on, or null if it does not say.
  final String? vehicle;
}

/// The result of replaying a drive with GNSS withheld.
class OutageReport {
  const OutageReport({
    required this.source,
    required this.profile,
    required this.config,
    required this.durations,
    required this.windowsTried,
    required this.skipped,
    required this.coreLedFromS,
    required this.runtimeMs,
    this.vehicleClass = VehicleClass.car,
    this.driftTargetPct = 10,
  });

  /// The vehicle settings the core was replayed with: taken from the
  /// recording's header, and a car when the header does not say. A leaning
  /// two-wheeler needs a looser lateral constraint than a car; scoring a bike
  /// ride with car settings would blame the filter for the setting.
  final VehicleClass vehicleClass;

  /// Human label for where the drive came from ("simulated", a file name...).
  final String source;
  final LogProfile profile;
  final OutageBenchmarkConfig config;

  /// One entry per requested duration that had at least one scored window.
  final List<DurationResult> durations;

  final int windowsTried;
  final Map<SkipReason, int> skipped;

  /// Seconds into the drive at which the core first became healthy enough to
  /// lead, or null if it never did.
  final double? coreLedFromS;
  final int runtimeMs;

  /// SIH26168's dead-reckoning bar (`NavConfig.outageReport.driftTargetPct`,
  /// replayed alongside the engine config so a report always carries the
  /// target it was judged against).
  final double driftTargetPct;

  DurationResult? forDuration(int seconds) {
    for (final d in durations) {
      if (d.durationS == seconds) return d;
    }
    return null;
  }

  /// PASS when every scored duration's median drift clears the SIH target -
  /// null when nothing could be scored, so there is nothing to judge.
  bool? get passed =>
      durations.isEmpty ? null : durations.every((d) => d.passed(driftTargetPct));

  /// The one-line takeaway at the longest scored outage.
  String get headline {
    if (durations.isEmpty) {
      return coreLedFromS == null
          ? 'The core never finished aligning to the vehicle in this drive, '
              'so no outage could be scored.'
          : 'No outage in this drive could be scored.';
    }
    final d = durations.last;
    return 'After ${d.durationS} s without GNSS the core was off by '
        '${d.engine.medianM.toStringAsFixed(0)} m (median) against '
        '${d.hold.medianM.toStringAsFixed(0)} m for holding the last velocity, '
        'over ${d.n} outages.';
  }

  String toText() {
    final b = StringBuffer()
      ..writeln('Outage benchmark - $source')
      ..writeln(
          'Drive ${(profile.durationS / 60).toStringAsFixed(1)} min | '
          'IMU ${profile.imuHz.toStringAsFixed(0)} Hz | '
          '${profile.gnssFixes} GNSS fixes (${profile.truthFixes} trusted as '
          'truth, median accuracy ${profile.medianTruthAccuracyM.toStringAsFixed(1)} m) | '
          'magnetometer ${profile.hasMagnetometer ? 'yes' : 'no'}, '
          'barometer ${profile.hasBarometer ? 'yes' : 'no'}')
      ..writeln('Device: ${profile.deviceModel ?? 'unknown'} | '
          'replayed with ${switch (vehicleClass) { VehicleClass.twoWheeler => 'two-wheeler', VehicleClass.pedestrian => 'pedestrian', VehicleClass.car => 'car' }} settings')
      ..writeln(coreLedFromS == null
          ? 'The core never became healthy enough to lead.'
          : 'The core led from ${coreLedFromS!.toStringAsFixed(0)} s; '
              '$windowsTried outage starts tried.')
      ..writeln()
      ..writeln('Error at the end of the outage, metres. drift = error / distance.')
      ..writeln('outage  n   hold median  p95   drift%   core median  p95   drift%   core closer  3-sigma ok');
    for (final d in durations) {
      b.writeln('${'${d.durationS} s'.padRight(7)}'
          '${'${d.n}'.padRight(4)}'
          '${d.hold.medianM.toStringAsFixed(1).padLeft(10)}'
          '${d.hold.p95M.toStringAsFixed(1).padLeft(7)}'
          '${d.hold.medianDriftPct.toStringAsFixed(1).padLeft(8)}'
          '${d.engine.medianM.toStringAsFixed(1).padLeft(13)}'
          '${d.engine.p95M.toStringAsFixed(1).padLeft(7)}'
          '${d.engine.medianDriftPct.toStringAsFixed(1).padLeft(8)}'
          '${'${d.engineWins}/${d.n}'.padLeft(13)}'
          '${'${d.engineCovered}/${d.n}'.padLeft(12)}');
    }
    if (skipped.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Not scored: ${skipped.entries.map((e) => '${e.value} x ${e.key.name}').join(', ')}');
    }
    final verdict = passed;
    b
      ..writeln()
      ..writeln(verdict == null
          ? 'Verdict: not scored.'
          : 'Verdict: ${verdict ? 'PASS' : 'FAIL'} - SIH <${driftTargetPct.toStringAsFixed(0)}% '
              'drift target.');
    return b.toString();
  }
}
