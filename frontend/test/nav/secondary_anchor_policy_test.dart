import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/anchors/portal_anchor.dart';
import 'package:gatisaarth/core/nav/anchors/radio_anchor.dart';
import 'package:gatisaarth/core/nav/anchors/visual_relocalization.dart';

void main() {
  const anchor = PortalAnchor(
    id: 'portal-a',
    label: 'Portal A',
    latitudeDeg: 28.639,
    longitudeDeg: 77.0661,
    horizontalSigmaM: 4,
    kind: PortalAnchorKind.tunnelPortal,
    visualDescriptor: 'f0f0',
    radioId: 'GS-DEMO-A',
  );
  final registry = PortalAnchorRegistry(const [anchor]);
  const context = PortalAnchorContext(
    inOutage: true,
    estimatedLatitudeDeg: 28.6391,
    estimatedLongitudeDeg: 77.0661,
    horizontalSigmaM: 15,
  );

  test('accepts only a strong, distinctive, on-device visual match', () {
    final policy = VisualRelocalizationPolicy(registry: registry);
    final accepted = policy.evaluate(
      observation: const VisualMatchObservation(
        anchorId: 'portal-a',
        confidence: 0.94,
        secondBestConfidence: 0.71,
        processedOnDevice: true,
      ),
      context: context,
    );
    expect(accepted.accepted, isTrue);
    expect(accepted.measurement!.anchor.id, 'portal-a');

    expect(
      policy
          .evaluate(
            observation: const VisualMatchObservation(
              anchorId: 'portal-a',
              confidence: 0.94,
              secondBestConfidence: 0.90,
              processedOnDevice: true,
            ),
            context: context,
          )
          .reason,
      VisualRelocalizationRejection.ambiguous,
    );
    expect(
      policy
          .evaluate(
            observation: const VisualMatchObservation(
              anchorId: 'portal-a',
              confidence: 0.99,
              secondBestConfidence: 0.1,
              processedOnDevice: false,
            ),
            context: context,
          )
          .reason,
      VisualRelocalizationRejection.notOnDevice,
    );
  });

  test('optional radio ranging is fresh, registered, and conservatively noisy',
      () {
    final policy = RadioAnchorPolicy(registry: registry);
    final accepted = policy.evaluate(
      observation: const RadioAnchorObservation(
        radioId: 'GS-DEMO-A',
        rangeM: 7,
        rangeSigmaM: 5,
        age: Duration(milliseconds: 800),
      ),
      context: context,
    );
    expect(accepted.accepted, isTrue);
    expect(accepted.measurement!.horizontalSigmaM, greaterThanOrEqualTo(6));

    expect(
      policy
          .evaluate(
            observation: const RadioAnchorObservation(
              radioId: 'GS-DEMO-A',
              rangeM: 7,
              rangeSigmaM: 2,
              age: Duration(seconds: 8),
            ),
            context: context,
          )
          .reason,
      RadioAnchorRejection.stale,
    );
  });
}
