import 'portal_anchor.dart';

class VisualMatchObservation {
  const VisualMatchObservation({
    required this.anchorId,
    required this.confidence,
    required this.secondBestConfidence,
    required this.processedOnDevice,
  });

  final String anchorId;
  final double confidence;
  final double secondBestConfidence;
  final bool processedOnDevice;
}

enum VisualRelocalizationRejection {
  notOnDevice,
  lowConfidence,
  ambiguous,
  anchorRejected,
}

class VisualRelocalizationDecision {
  const VisualRelocalizationDecision.accepted(this.measurement) : reason = null;
  const VisualRelocalizationDecision.rejected(this.reason) : measurement = null;

  final PortalAnchorMeasurement? measurement;
  final VisualRelocalizationRejection? reason;
  bool get accepted => measurement != null;
}

class VisualRelocalizationPolicy {
  const VisualRelocalizationPolicy({required this.registry});

  final PortalAnchorRegistry registry;

  VisualRelocalizationDecision evaluate({
    required VisualMatchObservation observation,
    required PortalAnchorContext context,
  }) {
    if (!observation.processedOnDevice) {
      return const VisualRelocalizationDecision.rejected(
        VisualRelocalizationRejection.notOnDevice,
      );
    }
    if (!observation.confidence.isFinite || observation.confidence < 0.88) {
      return const VisualRelocalizationDecision.rejected(
        VisualRelocalizationRejection.lowConfidence,
      );
    }
    if (!observation.secondBestConfidence.isFinite ||
        observation.confidence - observation.secondBestConfidence < 0.12) {
      return const VisualRelocalizationDecision.rejected(
        VisualRelocalizationRejection.ambiguous,
      );
    }
    final anchor = registry[observation.anchorId];
    if (anchor == null || anchor.visualDescriptor == null) {
      return const VisualRelocalizationDecision.rejected(
        VisualRelocalizationRejection.anchorRejected,
      );
    }
    final portal = PortalAnchorPolicy(registry: registry).evaluate(
      payload: 'GSARTH-ANCHOR:1:${anchor.id}',
      context: context,
    );
    if (!portal.accepted) {
      return const VisualRelocalizationDecision.rejected(
        VisualRelocalizationRejection.anchorRejected,
      );
    }
    return VisualRelocalizationDecision.accepted(portal.measurement!);
  }
}
