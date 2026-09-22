import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/anchors/portal_anchor.dart';

void main() {
  const northPortal = PortalAnchor(
    id: 'delhi-demo-north',
    label: 'Demo tunnel · north portal',
    latitudeDeg: 28.6390,
    longitudeDeg: 77.0661,
    horizontalSigmaM: 4,
    kind: PortalAnchorKind.tunnelPortal,
  );
  final registry = PortalAnchorRegistry(const [northPortal]);
  final policy = PortalAnchorPolicy(registry: registry);

  test('accepts a recognised local portal only during a GNSS outage', () {
    final decision = policy.evaluate(
      payload: 'GSARTH-ANCHOR:1:delhi-demo-north',
      context: const PortalAnchorContext(
        inOutage: true,
        estimatedLatitudeDeg: 28.6392,
        estimatedLongitudeDeg: 77.0661,
        horizontalSigmaM: 12,
      ),
    );

    expect(decision.accepted, isTrue);
    expect(decision.measurement!.anchor, northPortal);
    expect(decision.measurement!.horizontalSigmaM, 4);
    expect(decision.measurement!.residualM, lessThan(30));
  });

  test('rejects a recognised portal while GNSS is healthy', () {
    final decision = policy.evaluate(
      payload: 'GSARTH-ANCHOR:1:delhi-demo-north',
      context: const PortalAnchorContext(
        inOutage: false,
        estimatedLatitudeDeg: 28.6390,
        estimatedLongitudeDeg: 77.0661,
        horizontalSigmaM: 5,
      ),
    );

    expect(decision.accepted, isFalse);
    expect(decision.reason, PortalAnchorRejection.notInOutage);
  });

  test('rejects unknown, malformed, and implausibly distant portal payloads', () {
    final context = const PortalAnchorContext(
      inOutage: true,
      estimatedLatitudeDeg: 28.6390,
      estimatedLongitudeDeg: 77.0661,
      horizontalSigmaM: 5,
    );

    expect(
      policy.evaluate(payload: 'GSARTH-ANCHOR:1:unknown', context: context)
          .reason,
      PortalAnchorRejection.unknownAnchor,
    );
    expect(
      policy.evaluate(payload: 'delhi-demo-north', context: context).reason,
      PortalAnchorRejection.malformedPayload,
    );
    expect(
      policy
          .evaluate(
            payload: 'GSARTH-ANCHOR:1:delhi-demo-north',
            context: const PortalAnchorContext(
              inOutage: true,
              estimatedLatitudeDeg: 28.6500,
              estimatedLongitudeDeg: 77.0661,
              horizontalSigmaM: 5,
            ),
          )
          .reason,
      PortalAnchorRejection.implausibleResidual,
    );
  });
}
