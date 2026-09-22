import 'dart:math' as math;

import 'portal_anchor.dart';

class RadioAnchorObservation {
  const RadioAnchorObservation({
    required this.radioId,
    required this.rangeM,
    required this.rangeSigmaM,
    required this.age,
  });

  final String radioId;
  final double rangeM;
  final double rangeSigmaM;
  final Duration age;
}

enum RadioAnchorRejection { unknown, invalid, stale, anchorRejected }

class RadioAnchorDecision {
  const RadioAnchorDecision.accepted(this.measurement) : reason = null;
  const RadioAnchorDecision.rejected(this.reason) : measurement = null;

  final PortalAnchorMeasurement? measurement;
  final RadioAnchorRejection? reason;
  bool get accepted => measurement != null;
}

class RadioAnchorPolicy {
  const RadioAnchorPolicy({required this.registry});

  final PortalAnchorRegistry registry;

  RadioAnchorDecision evaluate({
    required RadioAnchorObservation observation,
    required PortalAnchorContext context,
  }) {
    PortalAnchor? anchor;
    for (final candidate in registry.values) {
      if (candidate.radioId == observation.radioId) anchor = candidate;
    }
    if (anchor == null) {
      return const RadioAnchorDecision.rejected(RadioAnchorRejection.unknown);
    }
    if (!observation.rangeM.isFinite ||
        observation.rangeM < 0 ||
        observation.rangeM > 15 ||
        !observation.rangeSigmaM.isFinite ||
        observation.rangeSigmaM <= 0 ||
        observation.age.isNegative) {
      return const RadioAnchorDecision.rejected(RadioAnchorRejection.invalid);
    }
    if (observation.age > const Duration(seconds: 3)) {
      return const RadioAnchorDecision.rejected(RadioAnchorRejection.stale);
    }
    final portal = PortalAnchorPolicy(registry: registry).evaluate(
      payload: 'GSARTH-ANCHOR:1:${anchor.id}',
      context: context,
    );
    if (!portal.accepted) {
      return const RadioAnchorDecision.rejected(
        RadioAnchorRejection.anchorRejected,
      );
    }
    final sigma = math.max(
      6.0,
      math.max(anchor.horizontalSigmaM, observation.rangeSigmaM) +
          observation.rangeM,
    );
    return RadioAnchorDecision.accepted(
      PortalAnchorMeasurement(
        anchor: PortalAnchor(
          id: anchor.id,
          label: anchor.label,
          latitudeDeg: anchor.latitudeDeg,
          longitudeDeg: anchor.longitudeDeg,
          horizontalSigmaM: sigma,
          kind: anchor.kind,
          visualDescriptor: anchor.visualDescriptor,
          radioId: anchor.radioId,
        ),
        residualM: portal.measurement!.residualM,
      ),
    );
  }
}
