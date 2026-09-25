import 'package:flutter/foundation.dart';

import '../nav_config.dart';
import 'gnss_quality.dart';

/// Driver-facing GNSS health state (root CLAUDE.md: "GNSS integrity anomaly",
/// never "spoofing"). `waiting` is the pre-fix state, shown as `--`/"Waiting"
/// — distinct from `outage`, which means a fix was held and then lost.
enum GnssHealthState {
  waiting,
  normal,
  degraded,
  multipathSuspected,
  interferenceSuspected,
  outage,
}

extension GnssHealthStateLabel on GnssHealthState {
  String get label => switch (this) {
        GnssHealthState.waiting => 'Waiting',
        GnssHealthState.normal => 'Normal',
        GnssHealthState.degraded => 'Degraded',
        GnssHealthState.multipathSuspected => 'Multipath suspected',
        GnssHealthState.interferenceSuspected => 'Interference suspected',
        GnssHealthState.outage => 'Outage',
      };
}

/// Constellation identifiers, kept free of the platform layer's
/// `GnssConstellation` (which drags in `package:flutter/services.dart`) so
/// this file stays a plain classifier over plain data.
enum GnssHealthConstellation {
  unknown,
  gps,
  sbas,
  glonass,
  qzss,
  beidou,
  galileo,
  navic,
}

@immutable
class GnssHealthSatelliteSample {
  const GnssHealthSatelliteSample({
    required this.constellation,
    required this.cn0DbHz,
    required this.usedInFix,
    this.elevationDegrees,
  });

  final GnssHealthConstellation constellation;
  final double cn0DbHz;
  final bool usedInFix;
  final double? elevationDegrees;
}

/// One receiver-level telemetry sample. Optional fields are null (never a
/// made-up zero) on hosts/API levels that do not expose them.
@immutable
class GnssHealthReceiverSample {
  const GnssHealthReceiverSample({
    this.satellites = const [],
    this.multipathDetectedCount,
    this.meanAutomaticGainControlDb,
    this.clockDiscontinuityCount,
    this.clockDriftNanosPerSecond,
  });

  final List<GnssHealthSatelliteSample> satellites;
  final int? multipathDetectedCount;
  final double? meanAutomaticGainControlDb;
  final int? clockDiscontinuityCount;
  final double? clockDriftNanosPerSecond;
}

/// Rolling metrics the card shows alongside the state.
@immutable
class GnssHealthMetrics {
  const GnssHealthMetrics({
    this.satellitesUsed = 0,
    this.satellitesVisible = 0,
    this.meanCn0DbHz,
    this.navicUsed = 0,
    this.navicVisible = 0,
    this.constellationVisible = const {},
    this.constellationUsed = const {},
    this.positionJumpRejects = 0,
    this.accelerationJumpRejects = 0,
    this.headingInconsistencies = 0,
    this.accuracyWorsening = false,
    this.clockDiscontinuityCount,
    this.clockDriftNanosPerSecond,
    this.multipathDetectedCount,
    this.meanAutomaticGainControlDb,
  });

  final int satellitesUsed;
  final int satellitesVisible;
  final double? meanCn0DbHz;
  final int navicUsed;
  final int navicVisible;
  final Map<GnssHealthConstellation, int> constellationVisible;
  final Map<GnssHealthConstellation, int> constellationUsed;

  /// Reject-reason counts within `GnssHealthConfig.rejectWindowSeconds`.
  final int positionJumpRejects;
  final int accelerationJumpRejects;
  final int headingInconsistencies;
  final bool accuracyWorsening;

  /// `--` in the UI (null) when the platform/API level does not expose it.
  final int? clockDiscontinuityCount;
  final double? clockDriftNanosPerSecond;
  final int? multipathDetectedCount;
  final double? meanAutomaticGainControlDb;
}

@immutable
class GnssHealthAssessment {
  const GnssHealthAssessment({
    required this.state,
    required this.reasons,
    required this.metrics,
  });

  final GnssHealthState state;
  final List<String> reasons;
  final GnssHealthMetrics metrics;
}

class _RejectEvent {
  const _RejectEvent(this.reason, this.atSeconds);
  final GnssRejectReason reason;
  final double atSeconds;
}

/// One driver-facing GNSS HEALTH state built from receiver telemetry (C/N0,
/// constellation mix, AGC, multipath indicator, clock) and fix-level evidence
/// (`GnssQualityEngine` reject reasons, fix freshness).
///
/// Two feeds, because the two evidence streams arrive at different rates:
/// [addReceiverSample] on every GNSS status/measurement event,
/// [addFix] on every fix `GnssQualityEngine.assess()` call. Both recompute
/// the assessment from whatever evidence is freshest — feeding only one is
/// fine (the state degrades gracefully to what that evidence alone can say).
///
/// Hysteresis: a worse state is adopted the moment it is detected ("enter
/// fast"); recovering to a better state needs `leaveCleanSeconds` of
/// continuously-normal raw readings first ("leave slow"), so a single clean
/// sample between two bad ones does not flicker the UI.
class GnssHealthClassifier {
  GnssHealthClassifier({NavConfig config = NavConfig.defaults})
      : _config = config.gnssHealth;

  final GnssHealthConfig _config;

  GnssHealthReceiverSample? _lastSample;
  bool _hadFixEver = false;
  double? _lastAcceptedFixAtSeconds;
  final List<double> _cn0History = [];
  final List<double> _agcHistory = [];
  final List<double> _accuracyHistory = [];
  int? _lastClockDiscontinuityCount;
  final List<_RejectEvent> _rejectEvents = [];

  GnssHealthState _reportedState = GnssHealthState.waiting;
  List<String> _reportedReasons = const ['Waiting for a GNSS fix'];
  double? _improvingSinceSeconds;

  GnssHealthAssessment _assessment = const GnssHealthAssessment(
    state: GnssHealthState.waiting,
    reasons: ['Waiting for a GNSS fix'],
    metrics: GnssHealthMetrics(),
  );

  GnssHealthAssessment get assessment => _assessment;

  /// Feed one receiver telemetry snapshot (satellite list, AGC, multipath,
  /// clock). [nowSeconds] is any monotonic clock, consistent across calls.
  void addReceiverSample(GnssHealthReceiverSample sample,
      {required double nowSeconds}) {
    _lastSample = sample;
    _recompute(nowSeconds, recordSample: true);
  }

  /// Feed one fix-level verdict from `GnssQualityEngine.assess()`.
  /// [accuracyM] is the fix's reported horizontal accuracy, used only for the
  /// accuracy-worsening trend.
  void addFix({
    required GnssRejectReason reason,
    double? accuracyM,
    required double nowSeconds,
  }) {
    if (reason != GnssRejectReason.none) {
      _rejectEvents.add(_RejectEvent(reason, nowSeconds));
    } else {
      _hadFixEver = true;
      _lastAcceptedFixAtSeconds = nowSeconds;
      if (accuracyM != null && accuracyM.isFinite) {
        _accuracyHistory.add(accuracyM);
        while (_accuracyHistory.length > 5) {
          _accuracyHistory.removeAt(0);
        }
      }
    }
    _pruneRejectEvents(nowSeconds);
    _recompute(nowSeconds);
  }

  void reset() {
    _lastSample = null;
    _hadFixEver = false;
    _lastAcceptedFixAtSeconds = null;
    _cn0History.clear();
    _agcHistory.clear();
    _accuracyHistory.clear();
    _lastClockDiscontinuityCount = null;
    _rejectEvents.clear();
    _reportedState = GnssHealthState.waiting;
    _reportedReasons = const ['Waiting for a GNSS fix'];
    _improvingSinceSeconds = null;
    _assessment = const GnssHealthAssessment(
      state: GnssHealthState.waiting,
      reasons: ['Waiting for a GNSS fix'],
      metrics: GnssHealthMetrics(),
    );
  }

  void _pruneRejectEvents(double nowSeconds) {
    _rejectEvents.removeWhere(
        (e) => nowSeconds - e.atSeconds > _config.rejectWindowSeconds);
  }

  int _windowedCount(double nowSeconds, Set<GnssRejectReason> reasons) {
    _pruneRejectEvents(nowSeconds);
    return _rejectEvents.where((e) => reasons.contains(e.reason)).length;
  }

  bool get _accuracyWorsening {
    if (_accuracyHistory.length < 3) return false;
    final last = _accuracyHistory.last;
    final priorMean =
        _accuracyHistory.take(_accuracyHistory.length - 1).reduce((a, b) => a + b) /
            (_accuracyHistory.length - 1);
    return priorMean > 0 && last > priorMean * 1.5;
  }

  static int _severity(GnssHealthState state) => switch (state) {
        GnssHealthState.waiting => 0,
        GnssHealthState.normal => 0,
        GnssHealthState.degraded => 1,
        GnssHealthState.multipathSuspected => 2,
        GnssHealthState.interferenceSuspected => 2,
        GnssHealthState.outage => 3,
      };

  void _recompute(double nowSeconds, {bool recordSample = false}) {
    if (!_hadFixEver) {
      if (recordSample) _recordSampleHistory();
      _assessment = GnssHealthAssessment(
        state: GnssHealthState.waiting,
        reasons: const ['Waiting for a GNSS fix'],
        metrics: _metrics(nowSeconds),
      );
      return;
    }

    final raw = _classifyRaw(nowSeconds);
    if (recordSample) _recordSampleHistory();

    if (_severity(raw.state) >= _severity(_reportedState)) {
      _reportedState = raw.state;
      _reportedReasons = raw.reasons;
      _improvingSinceSeconds = null;
    } else {
      // Raw evidence looks better than what is currently reported: only
      // adopt it once it has stayed at least this good for the full window.
      _improvingSinceSeconds ??= nowSeconds;
      if (nowSeconds - _improvingSinceSeconds! >= _config.leaveCleanSeconds) {
        _reportedState = raw.state;
        _reportedReasons = raw.reasons;
        _improvingSinceSeconds = null;
      }
    }

    _assessment = GnssHealthAssessment(
      state: _reportedState,
      reasons: _reportedReasons,
      metrics: _metrics(nowSeconds),
    );
  }

  ({GnssHealthState state, List<String> reasons}) _classifyRaw(
      double nowSeconds) {
    // No receiver telemetry has arrived yet (e.g. a fix was just accepted
    // before the first GnssStatus callback) — that is not evidence of zero
    // satellites, just evidence we have not asked yet.
    final hasTelemetry = _lastSample != null;
    final sample = _lastSample ?? const GnssHealthReceiverSample();
    final satellites = sample.satellites;
    final satellitesUsed = satellites.where((s) => s.usedInFix).length;
    final satellitesVisible = satellites.length;

    final fixAgeSeconds = _lastAcceptedFixAtSeconds == null
        ? double.infinity
        : nowSeconds - _lastAcceptedFixAtSeconds!;
    // Fresh accepted fixes with zero satellites flagged "used" means the
    // receiver does not report usage (emulators, some chipsets), not an
    // outage: freshness decides OUTAGE, and the used-count rules are skipped.
    final reportsUsage = hasTelemetry && satellitesUsed > 0;

    if (fixAgeSeconds > _config.staleFixSeconds) {
      return (
        state: GnssHealthState.outage,
        reasons: [
          'No accepted fix for ${fixAgeSeconds.isFinite ? fixAgeSeconds.toStringAsFixed(0) : '--'}s',
        ],
      );
    }

    final cn0Values = satellites.map((s) => s.cn0DbHz).toList(growable: false);
    final meanCn0 = cn0Values.isEmpty
        ? null
        : cn0Values.reduce((a, b) => a + b) / cn0Values.length;
    final cn0Range =
        cn0Values.isEmpty ? null : cn0Values.reduce((a, b) => a > b ? a : b) -
            cn0Values.reduce((a, b) => a < b ? a : b);

    final cn0Drop = meanCn0 == null || _cn0History.isEmpty
        ? null
        : (_cn0History.reduce((a, b) => a + b) / _cn0History.length) -
            meanCn0;
    final agcDrop = sample.meanAutomaticGainControlDb == null ||
            _agcHistory.isEmpty
        ? null
        : (_agcHistory.reduce((a, b) => a + b) / _agcHistory.length) -
            sample.meanAutomaticGainControlDb!;

    final distinctConstellations =
        satellites.map((s) => s.constellation).toSet().length;

    final broadbandDrop = cn0Drop != null &&
        cn0Drop >= _config.broadbandCn0DropDbHz &&
        distinctConstellations >= _config.broadbandMinConstellations &&
        satellitesVisible >= _config.broadbandMinSatellites;

    final sharpAgcDrop = agcDrop != null && agcDrop >= _config.sharpAgcDropDb;

    final clockDiscontinuityJump = sample.clockDiscontinuityCount != null &&
        _lastClockDiscontinuityCount != null &&
        sample.clockDiscontinuityCount! > _lastClockDiscontinuityCount!;
    final windowRejectCount = _windowedCount(nowSeconds, {
      GnssRejectReason.impossibleJump,
      GnssRejectReason.impossibleAcceleration,
      GnssRejectReason.impossibleHeadingChange,
    });
    final clockAnomalyWithRejects = clockDiscontinuityJump && windowRejectCount > 0;

    if (broadbandDrop || sharpAgcDrop || clockAnomalyWithRejects) {
      return (
        state: GnssHealthState.interferenceSuspected,
        reasons: [
          if (broadbandDrop)
            'Signal strength dropped broadly across '
                '$distinctConstellations constellations',
          if (sharpAgcDrop)
            'Receiver gain (AGC) dropped sharply',
          if (clockAnomalyWithRejects)
            'GNSS integrity anomaly detected: receiver clock discontinuity '
                'with fix rejections',
        ],
      );
    }

    final multipathMany = sample.multipathDetectedCount != null &&
        sample.multipathDetectedCount! >= _config.multipathManyMeasurements;
    final lowElevationCount = satellites
        .where((s) =>
            s.elevationDegrees != null &&
            s.elevationDegrees! < _config.lowElevationDegrees)
        .length;
    final lowElevationDominance = satellitesVisible > 0 &&
        (lowElevationCount / satellitesVisible) >=
            _config.lowElevationDominanceRatio;
    final highVarianceMultipath = cn0Range != null &&
        cn0Range >= _config.highCn0VarianceDbHz &&
        lowElevationDominance;
    final positionOrHeadingJumps = _windowedCount(nowSeconds, {
      GnssRejectReason.impossibleJump,
      GnssRejectReason.impossibleHeadingChange,
    });
    final jumpsWhileSignalFine = positionOrHeadingJumps >=
            _config.jumpRejectsForMultipath &&
        meanCn0 != null &&
        meanCn0 >= _config.strongMeanCn0DbHz;

    if (multipathMany || highVarianceMultipath || jumpsWhileSignalFine) {
      return (
        state: GnssHealthState.multipathSuspected,
        reasons: [
          if (multipathMany)
            'Multipath indicator flagged on '
                '${sample.multipathDetectedCount} measurements',
          if (highVarianceMultipath)
            'Wide C/N0 spread dominated by low-elevation satellites',
          if (jumpsWhileSignalFine)
            'Position/heading jumps rejected while signal strength is fine',
        ],
      );
    }

    final worseningAccuracy = _accuracyWorsening;
    final intermittentRejects = windowRejectCount > 0;
    final fewUsed = reportsUsage && satellitesUsed < _config.fewSatellitesUsed;
    final weakSignal = meanCn0 != null && meanCn0 < _config.weakMeanCn0DbHz;

    if (fewUsed || weakSignal || worseningAccuracy || intermittentRejects) {
      return (
        state: GnssHealthState.degraded,
        reasons: [
          if (fewUsed) 'Only $satellitesUsed satellites used in the fix',
          if (weakSignal) 'Weak mean satellite signal strength',
          if (worseningAccuracy) 'Fix accuracy is trending worse',
          if (intermittentRejects) 'Intermittent fix rejections',
        ],
      );
    }

    return (
      state: GnssHealthState.normal,
      reasons: const ['Receiver evidence is internally consistent'],
    );
  }

  /// Rolls the current `_lastSample` into the trend histories, *after*
  /// `_classifyRaw` has compared against the previous ones, so the next call
  /// sees this sample as "previous". Called once per fresh receiver sample
  /// (not on every `addFix`, which may run between receiver samples).
  void _recordSampleHistory() {
    final sample = _lastSample ?? const GnssHealthReceiverSample();
    final cn0Values =
        sample.satellites.map((s) => s.cn0DbHz).toList(growable: false);
    if (cn0Values.isNotEmpty) {
      final meanCn0 = cn0Values.reduce((a, b) => a + b) / cn0Values.length;
      _cn0History.add(meanCn0);
      while (_cn0History.length > 10) {
        _cn0History.removeAt(0);
      }
    }
    if (sample.meanAutomaticGainControlDb != null) {
      _agcHistory.add(sample.meanAutomaticGainControlDb!);
      while (_agcHistory.length > 10) {
        _agcHistory.removeAt(0);
      }
    }
    _lastClockDiscontinuityCount =
        sample.clockDiscontinuityCount ?? _lastClockDiscontinuityCount;
  }

  GnssHealthMetrics _metrics(double nowSeconds) {
    final sample = _lastSample ?? const GnssHealthReceiverSample();
    final satellites = sample.satellites;
    final cn0Values = satellites.map((s) => s.cn0DbHz).toList(growable: false);
    final meanCn0 = cn0Values.isEmpty
        ? null
        : cn0Values.reduce((a, b) => a + b) / cn0Values.length;

    final visible = <GnssHealthConstellation, int>{};
    final used = <GnssHealthConstellation, int>{};
    for (final satellite in satellites) {
      visible[satellite.constellation] =
          (visible[satellite.constellation] ?? 0) + 1;
      if (satellite.usedInFix) {
        used[satellite.constellation] =
            (used[satellite.constellation] ?? 0) + 1;
      }
    }

    return GnssHealthMetrics(
      satellitesUsed: satellites.where((s) => s.usedInFix).length,
      satellitesVisible: satellites.length,
      meanCn0DbHz: meanCn0,
      navicUsed: used[GnssHealthConstellation.navic] ?? 0,
      navicVisible: visible[GnssHealthConstellation.navic] ?? 0,
      constellationVisible: Map.unmodifiable(visible),
      constellationUsed: Map.unmodifiable(used),
      positionJumpRejects:
          _windowedCount(nowSeconds, {GnssRejectReason.impossibleJump}),
      accelerationJumpRejects: _windowedCount(
          nowSeconds, {GnssRejectReason.impossibleAcceleration}),
      headingInconsistencies: _windowedCount(
          nowSeconds, {GnssRejectReason.impossibleHeadingChange}),
      accuracyWorsening: _accuracyWorsening,
      clockDiscontinuityCount: sample.clockDiscontinuityCount,
      clockDriftNanosPerSecond: sample.clockDriftNanosPerSecond,
      multipathDetectedCount: sample.multipathDetectedCount,
      meanAutomaticGainControlDb: sample.meanAutomaticGainControlDb,
    );
  }
}
