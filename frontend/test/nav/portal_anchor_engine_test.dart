import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/anchors/portal_anchor.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';

void main() {
  const anchor = PortalAnchor(
    id: 'demo-portal',
    label: 'Demo tunnel portal',
    latitudeDeg: 28.6140,
    longitudeDeg: 77.2090,
    horizontalSigmaM: 4,
    kind: PortalAnchorKind.tunnelPortal,
  );
  const measurement = PortalAnchorMeasurement(anchor: anchor, residualM: 11);

  NavigationEngine seededEngine() {
    final engine = NavigationEngine();
    engine.filter.initialise(
      latitudeDeg: 28.6139,
      longitudeDeg: 77.2090,
      altitudeM: 0,
      headingRad: 0,
      positionSigma: 25,
      timestampUs: 1,
    );
    return engine;
  }

  test('an accepted portal is an auditable EKF measurement during an outage',
      () {
    final engine = seededEngine();
    engine.onGnssLost(2);

    final result = engine.onPortalAnchor(measurement, monotonicUs: 3);

    expect(result, isNotNull);
    expect(result!.accepted, isTrue);
    expect(result.name, 'portal_anchor');
    expect(engine.recentMeasurements.last.name, 'portal_anchor');
    expect(engine.snapshot!.contribution.anchor, greaterThan(0));
    expect(engine.snapshot!.outageDuration, isNot(Duration.zero));
  });

  test('a portal cannot correct the filter while GNSS is not in outage', () {
    final engine = seededEngine();

    final result = engine.onPortalAnchor(measurement, monotonicUs: 2);

    expect(result, isNull);
    expect(engine.recentMeasurements, isEmpty);
  });
}
