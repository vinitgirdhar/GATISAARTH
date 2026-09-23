import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/gnss/local_gnss_risk_map.dart';

final _now = DateTime.utc(2026, 9, 23, 12);

GnssRiskSample _sample({
  required String journey,
  bool degraded = true,
  DateTime? at,
  double lat = 28.6139,
  double lon = 77.2090,
  double accuracy = 5,
}) =>
    GnssRiskSample(
      latitudeDeg: lat,
      longitudeDeg: lon,
      accuracyM: accuracy,
      observedAt: at ?? _now,
      journeyId: journey,
      degraded: degraded,
    );

void main() {
  test('collection is off by default and revocation erases local data', () {
    final map = LocalGnssRiskMap();
    expect(map.add(_sample(journey: 'a'), now: _now), isFalse);
    map.setOptIn(true);
    for (final journey in ['a', 'b', 'c']) {
      map.add(_sample(journey: journey), now: _now);
      map.add(_sample(journey: journey), now: _now);
    }
    expect(map.visibleCells(_now), hasLength(1));
    map.setOptIn(false);
    expect(map.visibleCells(_now), isEmpty);
    map.setOptIn(true);
    expect(map.visibleCells(_now), isEmpty);
  });

  test('publishes only coarse cells with enough independent journeys', () {
    final map = LocalGnssRiskMap()..setOptIn(true);
    for (var i = 0; i < 6; i++) {
      expect(map.add(_sample(journey: 'one'), now: _now), isTrue);
    }
    expect(map.visibleCells(_now), isEmpty);
    for (final journey in ['two', 'three']) {
      expect(map.add(_sample(journey: journey, degraded: false), now: _now),
          isTrue);
    }
    final cells = map.visibleCells(_now);
    expect(cells, hasLength(1));
    expect(cells.single.observations, 8);
    expect(cells.single.distinctJourneys, 3);
    expect(cells.single.riskFraction, closeTo(1 / 3, 0.00001));
  });

  test('high-rate samples from one journey cannot dominate the risk score', () {
    final map = LocalGnssRiskMap()..setOptIn(true);
    for (var i = 0; i < 100; i++) {
      map.add(_sample(journey: 'one'), now: _now);
    }
    map.add(_sample(journey: 'two', degraded: false), now: _now);
    map.add(_sample(journey: 'three', degraded: false), now: _now);
    expect(map.visibleCells(_now).single.riskFraction, closeTo(1 / 3, 0.00001));
  });

  test('rejects invalid, imprecise, stale and future observations', () {
    final map = LocalGnssRiskMap()..setOptIn(true);
    expect(map.add(_sample(journey: 'a', lat: double.nan), now: _now), isFalse);
    expect(map.add(_sample(journey: 'a', accuracy: 100), now: _now), isFalse);
    expect(
        map.add(
          _sample(journey: 'a', at: _now.subtract(const Duration(days: 8))),
          now: _now,
        ),
        isFalse);
    expect(
        map.add(
          _sample(journey: 'a', at: _now.add(const Duration(seconds: 1))),
          now: _now,
        ),
        isFalse);
    expect(map.visibleCells(_now), isEmpty);
  });

  test('old contributions expire before a cell can be published', () {
    final map = LocalGnssRiskMap()..setOptIn(true);
    for (final journey in ['a', 'b', 'c']) {
      for (var i = 0; i < 2; i++) {
        map.add(_sample(journey: journey), now: _now);
      }
    }
    expect(map.visibleCells(_now), hasLength(1));
    expect(map.visibleCells(_now.add(const Duration(days: 8))), isEmpty);
  });
}
