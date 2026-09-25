import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../map/road_noding.dart' show metresPerDegree;
import 'outage_recovery.dart';

/// One GNSS fix withheld during a simulated blackout: never handed to the
/// engine or the heuristic pipeline (the app runs pure dead reckoning through
/// it, exactly as in a real outage) — kept only as truth for
/// [SimulatedOutageScorer] once the blackout ends.
@immutable
class TruthFix {
  const TruthFix({
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.accuracyM,
    required this.at,
  });

  final double latitudeDeg;
  final double longitudeDeg;
  final double accuracyM;
  final DateTime at;
}

/// One sample of the reported horizontal uncertainty taken during the
/// blackout (about once a second — see `SimulatedOutageConfig`), so the
/// result can show how far the margin grew, not just where it ended.
@immutable
class SigmaSample {
  const SigmaSample({required this.at, required this.sigmaM});

  final DateTime at;
  final double sigmaM;
}

/// A flat local projection good for the few hundred metres a blackout demo
/// covers — the same small-area approximation `core/nav/map` already uses.
class _LocalMetres {
  _LocalMetres(double referenceLatDeg)
      : _metresPerLon =
            metresPerDegree * math.cos(referenceLatDeg * math.pi / 180);

  final double _metresPerLon;

  double x(double lonDeg) => lonDeg * _metresPerLon;
  double y(double latDeg) => latDeg * metresPerDegree;
}

double _distanceM(
  _LocalMetres proj,
  double lat0,
  double lon0,
  double lat1,
  double lon1,
) {
  final dx = proj.x(lon1) - proj.x(lon0);
  final dy = proj.y(lat1) - proj.y(lat0);
  return math.sqrt(dx * dx + dy * dy);
}

/// What one "Simulate GNSS loss" run measured: how far the vehicle actually
/// went (along the withheld truth fixes), how far the dead-reckoned position
/// had drifted from the truth by the time it ended, that error split into
/// along-track and cross-track components, how the reported uncertainty grew,
/// and how far the marker jumped when real fixes resumed.
///
/// Every field is nullable rather than a made-up number: fewer than two truth
/// fixes gives no distance or track split, no sigma samples gives no
/// uncertainty growth, and a cancelled run has no recovery jump. The UI shows
/// `--` for whichever of these could not be measured.
@immutable
class SimulatedOutageResult {
  const SimulatedOutageResult({
    required this.startedAt,
    required this.plannedDuration,
    required this.actualDuration,
    required this.distanceM,
    required this.endpointErrorM,
    required this.alongTrackM,
    required this.crossTrackM,
    required this.initialSigmaM,
    required this.peakSigmaM,
    required this.finalSigmaM,
    required this.recoveryJumpM,
    required this.fixAccuracyM,
    required this.coreLed,
  });

  /// Wall-clock time the driver pressed Start.
  final DateTime startedAt;

  final Duration plannedDuration;
  final Duration actualDuration;

  /// Along the withheld truth fixes, metres. Null with fewer than two.
  final double? distanceM;

  /// Last dead-reckoned position to the final withheld fix, metres.
  final double? endpointErrorM;

  /// Signed-then-absolute components of [endpointErrorM] relative to the
  /// truth's direction of travel near the end: a pure lateral offset reads as
  /// mostly cross-track, a pure along-road offset as mostly along-track. Null
  /// with fewer than two truth fixes (no direction to decompose against).
  final double? alongTrackM;
  final double? crossTrackM;

  /// First, peak and final reported horizontal uncertainty sampled during the
  /// blackout (see [SigmaSample]). Null when no sample was taken (e.g. an
  /// outage that ended within the first sampling interval).
  final double? initialSigmaM;
  final double? peakSigmaM;
  final double? finalSigmaM;

  /// Distance between the last dead-reckoned position and the first
  /// fused/live position once real fixes resumed. Null for a cancelled run.
  final double? recoveryJumpM;

  /// Accuracy of the final withheld fix (the truth the error is measured
  /// against), or null with no truth fix at all.
  final double? fixAccuracyM;

  /// Whether the navigation core was leading the map when the blackout ended.
  final bool coreLed;

  /// The same result once the first restored fix has been fused.
  SimulatedOutageResult withRecoveryJump(double? jumpM) => SimulatedOutageResult(
        startedAt: startedAt,
        plannedDuration: plannedDuration,
        actualDuration: actualDuration,
        distanceM: distanceM,
        endpointErrorM: endpointErrorM,
        alongTrackM: alongTrackM,
        crossTrackM: crossTrackM,
        initialSigmaM: initialSigmaM,
        peakSigmaM: peakSigmaM,
        finalSigmaM: finalSigmaM,
        recoveryJumpM: jumpM,
        fixAccuracyM: fixAccuracyM,
        coreLed: coreLed,
      );

  double? get driftPct {
    final distance = distanceM, error = endpointErrorM;
    if (distance == null || error == null || distance <= 0) return null;
    return 100 * error / distance;
  }

  /// Null when there is no basis for a verdict (see [driftPct]).
  bool? meetsTarget(double targetPct) {
    final pct = driftPct;
    return pct == null ? null : pct < targetPct;
  }

  /// Folds this result into the same evidence table real outages score into
  /// (`LiveSessionController.outageLog`), marked [OutageRecovery.isSimulated]
  /// so the log and its CSV never present it as a field measurement.
  OutageRecovery toOutageRecovery() => OutageRecovery(
        durationS: actualDuration.inMicroseconds / 1e6,
        distanceM: distanceM ?? 0,
        errorM: endpointErrorM ?? 0,
        fixAccuracyM: fixAccuracyM ?? 0,
        endedAtUs: startedAt.add(actualDuration).microsecondsSinceEpoch,
        coreLed: coreLed,
        predictedSigmaM: finalSigmaM,
        peakSigmaM: peakSigmaM,
        alongTrackM: alongTrackM,
        crossTrackM: crossTrackM,
        recoveryJumpM: recoveryJumpM,
        isSimulated: true,
      );
}

/// Accumulates one running blackout from `startSimulatedOutage` to the moment
/// it ends or is cancelled. A mutable builder, not a result — see
/// [SimulatedOutageScorer] for that.
class SimulatedOutageSession {
  SimulatedOutageSession({
    required this.plannedDuration,
    required this.startedAt,
  });

  final Duration plannedDuration;
  final DateTime startedAt;

  /// Real fixes withheld so far, in arrival order.
  final List<TruthFix> truthFixes = [];
  final List<SigmaSample> sigmaSamples = [];

  /// The dead-reckoned position as of the last tick, sampled continuously so
  /// whichever moment the blackout actually ends on has one ready.
  double? lastDrLatitudeDeg;
  double? lastDrLongitudeDeg;
  DateTime? lastSigmaSampleAt;

  Duration elapsed(DateTime now) => now.difference(startedAt);

  Duration remaining(DateTime now) {
    final left = plannedDuration - elapsed(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool isDue(DateTime now) => elapsed(now) >= plannedDuration;
}

/// Scores a finished [SimulatedOutageSession] against the truth fixes it
/// withheld. Pure function of its inputs — no clock, no engine, no I/O — so
/// it is unit-tested on synthetic tracks without any of that machinery.
class SimulatedOutageScorer {
  const SimulatedOutageScorer._();

  static SimulatedOutageResult score({
    required DateTime startedAt,
    required Duration plannedDuration,
    required Duration actualDuration,
    required List<TruthFix> truthFixes,
    required double lastDrLatitudeDeg,
    required double lastDrLongitudeDeg,
    List<SigmaSample> sigmaSamples = const [],
    double? firstRestoredLatitudeDeg,
    double? firstRestoredLongitudeDeg,
    required bool coreLed,
  }) {
    final initialSigmaM =
        sigmaSamples.isEmpty ? null : sigmaSamples.first.sigmaM;
    final peakSigmaM = sigmaSamples.isEmpty
        ? null
        : sigmaSamples.map((s) => s.sigmaM).reduce(math.max);
    final finalSigmaM = sigmaSamples.isEmpty ? null : sigmaSamples.last.sigmaM;

    if (truthFixes.isEmpty) {
      return SimulatedOutageResult(
        startedAt: startedAt,
        plannedDuration: plannedDuration,
        actualDuration: actualDuration,
        distanceM: null,
        endpointErrorM: null,
        alongTrackM: null,
        crossTrackM: null,
        initialSigmaM: initialSigmaM,
        peakSigmaM: peakSigmaM,
        finalSigmaM: finalSigmaM,
        recoveryJumpM: null,
        fixAccuracyM: null,
        coreLed: coreLed,
      );
    }

    final proj = _LocalMetres(truthFixes.first.latitudeDeg);
    var distanceM = 0.0;
    for (var i = 1; i < truthFixes.length; i++) {
      distanceM += _distanceM(
        proj,
        truthFixes[i - 1].latitudeDeg,
        truthFixes[i - 1].longitudeDeg,
        truthFixes[i].latitudeDeg,
        truthFixes[i].longitudeDeg,
      );
    }

    final last = truthFixes.last;
    final endpointErrorM = _distanceM(
      proj,
      lastDrLatitudeDeg,
      lastDrLongitudeDeg,
      last.latitudeDeg,
      last.longitudeDeg,
    );

    double? alongTrackM;
    double? crossTrackM;
    if (truthFixes.length >= 2) {
      final prev = truthFixes[truthFixes.length - 2];
      final dirX = proj.x(last.longitudeDeg) - proj.x(prev.longitudeDeg);
      final dirY = proj.y(last.latitudeDeg) - proj.y(prev.latitudeDeg);
      final dirLen = math.sqrt(dirX * dirX + dirY * dirY);
      // A near-zero direction (the last two truth fixes barely moved) has no
      // travel direction to decompose the error against.
      if (dirLen > 1e-6) {
        final ux = dirX / dirLen, uy = dirY / dirLen;
        final errX = proj.x(lastDrLongitudeDeg) - proj.x(last.longitudeDeg);
        final errY = proj.y(lastDrLatitudeDeg) - proj.y(last.latitudeDeg);
        alongTrackM = (errX * ux + errY * uy).abs();
        crossTrackM = (errX * -uy + errY * ux).abs();
      }
    }

    double? recoveryJumpM;
    if (firstRestoredLatitudeDeg != null && firstRestoredLongitudeDeg != null) {
      recoveryJumpM = _distanceM(
        proj,
        lastDrLatitudeDeg,
        lastDrLongitudeDeg,
        firstRestoredLatitudeDeg,
        firstRestoredLongitudeDeg,
      );
    }

    return SimulatedOutageResult(
      startedAt: startedAt,
      plannedDuration: plannedDuration,
      actualDuration: actualDuration,
      distanceM: distanceM,
      endpointErrorM: endpointErrorM,
      alongTrackM: alongTrackM,
      crossTrackM: crossTrackM,
      initialSigmaM: initialSigmaM,
      peakSigmaM: peakSigmaM,
      finalSigmaM: finalSigmaM,
      recoveryJumpM: recoveryJumpM,
      fixAccuracyM: last.accuracyM,
      coreLed: coreLed,
    );
  }
}
