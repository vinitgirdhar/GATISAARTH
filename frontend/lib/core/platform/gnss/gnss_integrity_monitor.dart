import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'gnss_telemetry.dart';

enum GnssSignalState { unavailable, healthy, degraded, anomaly }

@immutable
class GnssIntegrityAssessment {
  const GnssIntegrityAssessment({
    required this.state,
    required this.reason,
    this.meanCn0DbHz,
    this.cn0ChangeDbHz,
    this.usedRatio,
  });

  final GnssSignalState state;
  final String reason;
  final double? meanCn0DbHz;
  final double? cn0ChangeDbHz;
  final double? usedRatio;
}

/// Conservative receiver-level integrity monitor.
///
/// It reports observable symptoms only. A simultaneous C/N0 and fix-usage
/// collapse can come from a tunnel, blockage, multipath or interference, so it
/// is deliberately called an anomaly and never proof of spoofing or jamming.
class GnssIntegrityMonitor {
  GnssIntegrityMonitor({this.maxHistory = 60});

  final int maxHistory;
  final List<double> _cn0History = [];
  GnssIntegrityAssessment _assessment = const GnssIntegrityAssessment(
    state: GnssSignalState.unavailable,
    reason: 'Waiting for receiver evidence',
  );

  GnssIntegrityAssessment get assessment => _assessment;
  List<double> get cn0History => List<double>.unmodifiable(_cn0History);

  void add(GnssTelemetrySnapshot snapshot) {
    if (!snapshot.permissionGranted) {
      _assessment = const GnssIntegrityAssessment(
        state: GnssSignalState.unavailable,
        reason: 'Location permission is required for GNSS status',
      );
      return;
    }
    if (!snapshot.statusSupported) {
      _assessment = const GnssIntegrityAssessment(
        state: GnssSignalState.unavailable,
        reason: 'This device does not expose GNSS status',
      );
      return;
    }
    if (snapshot.satellites.isEmpty) {
      _assessment = const GnssIntegrityAssessment(
        state: GnssSignalState.degraded,
        reason: 'Receiver currently reports no visible satellites',
        usedRatio: 0,
      );
      return;
    }

    final mean = snapshot.satellites
            .map((satellite) => satellite.cn0DbHz)
            .reduce((a, b) => a + b) /
        snapshot.satellites.length;
    final previous = _cn0History.isEmpty
        ? null
        : _cn0History
                .skip(math.max(0, _cn0History.length - 5))
                .reduce((a, b) => a + b) /
            math.min(5, _cn0History.length);
    final change = previous == null ? null : mean - previous;
    final usedRatio = snapshot.usedInFixCount / snapshot.visibleCount;

    _cn0History.add(mean);
    while (_cn0History.length > maxHistory) {
      _cn0History.removeAt(0);
    }

    if (change != null && change <= -12 && usedRatio < 0.35) {
      _assessment = GnssIntegrityAssessment(
        state: GnssSignalState.anomaly,
        reason: 'Receiver signal collapse detected; blockage, multipath or '
            'interference is possible',
        meanCn0DbHz: mean,
        cn0ChangeDbHz: change,
        usedRatio: usedRatio,
      );
      return;
    }
    if (mean < 25 || usedRatio < 0.35) {
      _assessment = GnssIntegrityAssessment(
        state: GnssSignalState.degraded,
        reason: mean < 25
            ? 'Satellite signal strength is weak'
            : 'Few visible satellites are contributing to the fix',
        meanCn0DbHz: mean,
        cn0ChangeDbHz: change,
        usedRatio: usedRatio,
      );
      return;
    }
    _assessment = GnssIntegrityAssessment(
      state: GnssSignalState.healthy,
      reason: 'Receiver evidence is internally consistent',
      meanCn0DbHz: mean,
      cn0ChangeDbHz: change,
      usedRatio: usedRatio,
    );
  }

  void reset() {
    _cn0History.clear();
    _assessment = const GnssIntegrityAssessment(
      state: GnssSignalState.unavailable,
      reason: 'Waiting for receiver evidence',
    );
  }
}
