import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/guidance/mission_guidance.dart';

void main() {
  test('announces outage once and preserves the last trusted road', () {
    final policy = MissionGuidancePolicy();
    policy.update(const MissionGuidanceContext(
      inOutage: false,
      marginMeters: 5,
      roadHypotheses: 1,
      leadingRoadProbability: 0.95,
      trustedRoad: 'Ring Road',
      trustedHeadingDeg: 82,
    ));

    final started = policy.update(const MissionGuidanceContext(
      inOutage: true,
      marginMeters: 12,
      roadHypotheses: 1,
      leadingRoadProbability: 0.9,
      trustedRoad: 'Ring Road',
      trustedHeadingDeg: 82,
    ));

    expect(started?.event, MissionGuidanceEvent.outageStarted);
    expect(started?.speech, contains('GNSS lost'));
    expect(started?.display, contains('Ring Road'));
    expect(started?.display, contains('082°'));
    expect(policy.update(const MissionGuidanceContext(
      inOutage: true,
      marginMeters: 13,
      roadHypotheses: 1,
      leadingRoadProbability: 0.9,
    )), isNull);
  });

  test('warns about an ambiguous fork without issuing a false turn', () {
    final policy = MissionGuidancePolicy();
    policy.update(const MissionGuidanceContext(
      inOutage: false,
      marginMeters: 4,
      roadHypotheses: 1,
      leadingRoadProbability: 1,
      trustedRoad: 'Tunnel Road',
    ));
    policy.update(const MissionGuidanceContext(
      inOutage: true,
      marginMeters: 15,
      roadHypotheses: 1,
      leadingRoadProbability: 0.9,
    ));

    final ambiguous = policy.update(const MissionGuidanceContext(
      inOutage: true,
      marginMeters: 25,
      roadHypotheses: 3,
      leadingRoadProbability: 0.48,
    ));

    expect(ambiguous?.event, MissionGuidanceEvent.roadAmbiguous);
    expect(ambiguous?.speech, contains('Do not rely on turn guidance'));
    expect(ambiguous?.speech.toLowerCase(), isNot(contains('turn left')));
    expect(ambiguous?.speech.toLowerCase(), isNot(contains('turn right')));
  });

  test('announces critical uncertainty and recovery only on transitions', () {
    final policy = MissionGuidancePolicy();
    policy.update(const MissionGuidanceContext(
      inOutage: true,
      marginMeters: 10,
      roadHypotheses: 1,
      leadingRoadProbability: 0.9,
    ));
    final critical = policy.update(const MissionGuidanceContext(
      inOutage: true,
      marginMeters: 80,
      roadHypotheses: 1,
      leadingRoadProbability: 0.8,
    ));
    expect(critical?.event, MissionGuidanceEvent.positionUncertain);
    expect(critical?.requestHaptic, isTrue);

    final recovered = policy.update(const MissionGuidanceContext(
      inOutage: false,
      marginMeters: 8,
      roadHypotheses: 1,
      leadingRoadProbability: 0.95,
    ));
    expect(recovered?.event, MissionGuidanceEvent.recovered);
    expect(recovered?.speech, contains('GNSS restored'));
  });
}
