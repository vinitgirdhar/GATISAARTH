import 'package:flutter/foundation.dart';

/// How far off the dead-reckoned position was when GNSS came back.
///
/// The truth is the returning fix itself, so the error carries that fix's
/// own noise ([fixAccuracyM]); the card says so. Every real outage the phone
/// lives through becomes one scored measurement of the core.
@immutable
class OutageRecovery {
  const OutageRecovery({
    required this.durationS,
    required this.distanceM,
    required this.errorM,
    required this.fixAccuracyM,
    required this.endedAtUs,
    required this.coreLed,
    this.predictedSigmaM,
    this.peakSigmaM,
    this.alongTrackM,
    this.crossTrackM,
    this.recoveryJumpM,
    this.isSimulated = false,
  });

  /// From the last accepted fix before the outage to the returning one.
  final double durationS;

  /// Distance the core travelled over the same span.
  final double distanceM;

  /// Core position just before the returning fix, to that fix.
  final double errorM;
  final double fixAccuracyM;

  /// The core's own 1-sigma horizontal uncertainty at that moment.
  final double? predictedSigmaM;

  /// The highest horizontal uncertainty reported during the outage, when it
  /// was sampled (only the GNSS Outage Simulator does this today). Null for
  /// an ordinary real-outage entry — the UI shows `--`, never a guess.
  final double? peakSigmaM;

  /// [errorM] decomposed along and across the direction of travel, when the
  /// truth's own heading near the end was known. Null otherwise.
  final double? alongTrackM;
  final double? crossTrackM;

  /// Distance the marker jumped when real fixes resumed, for a simulated
  /// blackout. Null otherwise (a real outage's "resumption" is just the fix
  /// that produced [errorM]).
  final double? recoveryJumpM;

  final int endedAtUs;

  /// Whether the core was healthy enough to lead the map when the outage
  /// ended. If not, the user saw the fallback pipeline, not this estimate.
  final bool coreLed;

  /// True for a driver-triggered "Simulate GNSS loss" run, never a real
  /// outage — the log and its CSV must never present one as the other.
  final bool isSimulated;

  double get driftPct => distanceM > 0 ? 100 * errorM / distanceM : double.nan;

  bool meetsTarget(double targetPct) => driftPct < targetPct;

  bool isRecent({required int nowUs, required Duration window}) =>
      nowUs - endedAtUs <= window.inMicroseconds;
}
