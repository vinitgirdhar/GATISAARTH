import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ekf/navigation_filter.dart';

/// One source of correction and, in plain words, what the filter last did
/// with it and why.
@immutable
class CorrectionExplanation {
  const CorrectionExplanation({
    required this.name,
    required this.source,
    required this.used,
    required this.reason,
    required this.accepted,
    required this.refused,
    required this.lastUs,
  });

  /// The measurement's internal name (`gnss_position`, `nhc`, …).
  final String name;

  /// Human name of the source.
  final String source;

  /// Whether the last one was applied.
  final bool used;
  final String reason;

  /// Counts inside the window.
  final int accepted;
  final int refused;
  final int lastUs;
}

/// Keeps, per measurement source, the last outcome and recent counts, and
/// words them: "GNSS position refused — 2.1× further from the inertial
/// estimate than its uncertainty allows". Nothing here changes the estimate.
class CorrectionExplainer {
  CorrectionExplainer({this.window = const Duration(seconds: 60)});

  /// Sources silent for longer than this are left out.
  final Duration window;

  final Map<String, _Track> _tracks = {};

  void record(MeasurementResult r, int monotonicUs) {
    if (r.outcome == MeasurementOutcome.skipped) return;
    final t = _tracks.putIfAbsent(r.name, _Track.new);
    t.last = r;
    t.lastUs = monotonicUs;
    t.events.add((us: monotonicUs, ok: r.accepted));
    final from = monotonicUs - window.inMicroseconds;
    while (t.events.isNotEmpty && t.events.first.us < from) {
      t.events.removeFirst();
    }
  }

  /// Newest first.
  List<CorrectionExplanation> explain({required int nowUs}) {
    final from = nowUs - window.inMicroseconds;
    final out = <CorrectionExplanation>[];
    _tracks.forEach((name, t) {
      if (t.lastUs < from) return;
      final recent = t.events.where((e) => e.us >= from);
      out.add(CorrectionExplanation(
        name: name,
        source: _label(name),
        used: t.last!.accepted,
        reason: _reason(t.last!),
        accepted: recent.where((e) => e.ok).length,
        refused: recent.where((e) => !e.ok).length,
        lastUs: t.lastUs,
      ));
    });
    out.sort((a, b) => b.lastUs.compareTo(a.lastUs));
    return out;
  }

  void reset() => _tracks.clear();

  static const Map<String, String> _labels = {
    'gnss_position': 'GNSS position',
    'gnss_velocity': 'GNSS velocity',
    'body_velocity': 'Body velocity',
    'zupt': 'Stop detection (ZUPT)',
    'zaru': 'No-rotation (ZARU)',
    'nhc': 'No side-slip (NHC)',
    'forward_speed': 'Forward speed',
    'ai_forward_speed': 'AI speed model',
    'turn_speed': 'Turn speedometer',
    'vibration_speed': 'Tyre-vibration speed',
    'baro_altitude': 'Barometric altitude',
    'heading': 'Heading',
    'map_heading': 'Road heading (map)',
    'magnetometer': 'Magnetometer heading',
    'portal_anchor': 'Surveyed anchor',
  };

  static const Map<String, String> _whyUsed = {
    'gnss_position': 'agreed with the inertial estimate',
    'gnss_velocity': 'Doppler speed agreed with the inertial estimate',
    'zupt': 'the vehicle is stopped, so its speed is pinned to zero',
    'zaru': 'the vehicle is still, so the gyro bias is learned',
    'nhc': 'a vehicle cannot slide sideways or lift off, so that motion is removed',
    'ai_forward_speed': 'validated against GNSS on this drive, so it holds the speed',
    'turn_speed': 'a steady turn gives speed = sideways force ÷ turn rate',
    'vibration_speed': 'the tyre vibration line gives the speed',
    'map_heading': 'the matched road gives the direction of travel',
    'magnetometer': 'the calibrated compass steadies the heading',
    'baro_altitude': 'the barometer holds the height',
    'portal_anchor': 'a surveyed point pins the position',
  };

  static String _label(String name) =>
      _labels[name] ?? name.replaceAll('_', ' ');

  static String _reason(MeasurementResult r) {
    switch (r.outcome) {
      case MeasurementOutcome.accepted:
        return 'Used · ${_whyUsed[r.name] ?? 'passed the consistency check'}';
      case MeasurementOutcome.rejectedByGate:
        final nis = r.nis, gate = r.gateLimit;
        final factor = nis != null && gate != null && gate > 0
            // NIS is a squared, normalised distance: its root compares lengths.
            ? ' — ${math.sqrt(nis / gate).toStringAsFixed(1)}× further from the '
                'inertial estimate than its uncertainty allows'
            : ' — it disagreed with the inertial estimate';
        final streak =
            r.rejectStreak > 1 ? ' (${r.rejectStreak} in a row)' : '';
        return 'Refused$factor$streak';
      case MeasurementOutcome.singular:
        return 'Not used · the update was numerically unsafe';
      case MeasurementOutcome.skipped:
        return 'Not used';
    }
  }
}

class _Track {
  MeasurementResult? last;
  int lastUs = 0;
  final Queue<({int us, bool ok})> events = Queue();
}
