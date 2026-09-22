import 'package:flutter/foundation.dart';

enum MissionGuidanceEvent {
  outageStarted,
  roadAmbiguous,
  positionUncertain,
  recovered,
}

@immutable
class MissionGuidanceContext {
  const MissionGuidanceContext({
    required this.inOutage,
    required this.marginMeters,
    required this.roadHypotheses,
    required this.leadingRoadProbability,
    this.trustedRoad,
    this.trustedHeadingDeg,
  });

  final bool inOutage;
  final double? marginMeters;
  final int roadHypotheses;
  final double? leadingRoadProbability;
  final String? trustedRoad;
  final double? trustedHeadingDeg;
}

@immutable
class MissionGuidanceDecision {
  const MissionGuidanceDecision({
    required this.event,
    required this.speech,
    required this.display,
    this.requestHaptic = false,
  });

  final MissionGuidanceEvent event;
  final String speech;
  final String display;
  final bool requestHaptic;
}

/// Transition-based driver guidance for a GNSS outage.
///
/// It never invents a turn. Ambiguity explicitly suppresses turn guidance and
/// asks the driver to use signs until an independent fix returns.
class MissionGuidancePolicy {
  bool _wasOutage = false;
  bool _ambiguityAnnounced = false;
  bool _criticalAnnounced = false;
  String? _lastTrustedRoad;
  double? _lastTrustedHeading;

  MissionGuidanceDecision? update(MissionGuidanceContext context) {
    if (!context.inOutage) {
      if (context.trustedRoad != null) _lastTrustedRoad = context.trustedRoad;
      if (context.trustedHeadingDeg != null) {
        _lastTrustedHeading = context.trustedHeadingDeg;
      }
      if (_wasOutage) {
        _wasOutage = false;
        _ambiguityAnnounced = false;
        _criticalAnnounced = false;
        return const MissionGuidanceDecision(
          event: MissionGuidanceEvent.recovered,
          speech: 'GNSS restored. Position is recovering.',
          display: 'GNSS restored · validating the returned fix',
        );
      }
      return null;
    }

    if (!_wasOutage) {
      _wasOutage = true;
      final road = context.trustedRoad ?? _lastTrustedRoad;
      final heading = context.trustedHeadingDeg ?? _lastTrustedHeading;
      final where = _lastTrustedPosition(road, heading);
      return MissionGuidanceDecision(
        event: MissionGuidanceEvent.outageStarted,
        speech: 'GNSS lost. Dead reckoning active. Continue cautiously. '
            'Automatic rerouting is paused.',
        display: 'Outage mission · $where',
        requestHaptic: true,
      );
    }

    final ambiguous = context.roadHypotheses > 1 &&
        (context.leadingRoadProbability ?? 0) < 0.7;
    if (ambiguous && !_ambiguityAnnounced) {
      _ambiguityAnnounced = true;
      return const MissionGuidanceDecision(
        event: MissionGuidanceEvent.roadAmbiguous,
        speech: 'Road fork uncertain. Do not rely on turn guidance. Follow '
            'road signs until position confidence returns.',
        display: 'Multiple road corridors possible · turn guidance paused',
        requestHaptic: true,
      );
    }

    if ((context.marginMeters ?? 0) >= 60 && !_criticalAnnounced) {
      _criticalAnnounced = true;
      return const MissionGuidanceDecision(
        event: MissionGuidanceEvent.positionUncertain,
        speech: 'Position confidence is low. Stay on the current road and '
            'follow road signs.',
        display: 'Low position confidence · use road signs',
        requestHaptic: true,
      );
    }
    return null;
  }

  static String _lastTrustedPosition(String? road, double? heading) {
    final parts = <String>[];
    if (road != null && road.trim().isNotEmpty) parts.add(road.trim());
    if (heading != null && heading.isFinite) {
      final degrees = (heading.round() % 360 + 360) % 360;
      parts.add('${degrees.toString().padLeft(3, '0')}°');
    }
    return parts.isEmpty ? 'hold the last trusted course' : parts.join(' · ');
  }
}
