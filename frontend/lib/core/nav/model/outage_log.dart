import 'dart:math' as math;

import 'outage_recovery.dart';

/// Every outage the returning GNSS scored in this session, newest last: the
/// per-outage evidence table (duration, distance, error, drift, target met).
class OutageLog {
  OutageLog({this.capacity = 500});

  final int capacity;
  final List<OutageRecovery> _entries = [];

  List<OutageRecovery> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;
  int get length => _entries.length;

  /// Adds [r] unless it is the one already logged last. True when added.
  bool add(OutageRecovery r) {
    if (_entries.isNotEmpty && _entries.last.endedAtUs == r.endedAtUs) {
      return false;
    }
    _entries.add(r);
    if (_entries.length > capacity) _entries.removeAt(0);
    return true;
  }

  /// Outages whose drift was below [targetPct] of the distance.
  int metTarget(double targetPct) =>
      _entries.where((r) => r.meetsTarget(targetPct)).length;

  /// Median drift (% of distance), or null with nothing logged.
  double? get medianDriftPct {
    if (_entries.isEmpty) return null;
    final d = [for (final r in _entries) r.driftPct]..sort();
    final n = d.length;
    return n.isOdd ? d[n ~/ 2] : 0.5 * (d[n ~/ 2 - 1] + d[n ~/ 2]);
  }

  double? get worstDriftPct => _entries.isEmpty
      ? null
      : _entries.map((r) => r.driftPct).reduce(math.max);

  /// One row per outage, for a spreadsheet. `along_track_m`, `cross_track_m`,
  /// `peak_sigma_m` and `recovery_jump_m` are blank where the entry has no
  /// value for them (an ordinary real-outage row, or a run too short to
  /// sample) — never a made-up number. `simulated` is `true` only for a
  /// driver-triggered "Simulate GNSS loss" run, never a real outage.
  String toCsv(double targetPct) {
    final b = StringBuffer(
        'outage,duration_s,distance_m,error_m,drift_pct,fix_accuracy_m,'
        'core_led,under_${targetPct.toStringAsFixed(0)}_pct,along_track_m,'
        'cross_track_m,peak_sigma_m,recovery_jump_m,simulated\n');
    for (var i = 0; i < _entries.length; i++) {
      final r = _entries[i];
      b.writeln([
        i + 1,
        r.durationS.toStringAsFixed(1),
        r.distanceM.toStringAsFixed(1),
        r.errorM.toStringAsFixed(1),
        r.driftPct.toStringAsFixed(2),
        r.fixAccuracyM.toStringAsFixed(1),
        r.coreLed,
        r.meetsTarget(targetPct),
        r.alongTrackM?.toStringAsFixed(1) ?? '',
        r.crossTrackM?.toStringAsFixed(1) ?? '',
        r.peakSigmaM?.toStringAsFixed(1) ?? '',
        r.recoveryJumpM?.toStringAsFixed(1) ?? '',
        r.isSimulated,
      ].join(','));
    }
    return b.toString();
  }

  void clear() => _entries.clear();
}
