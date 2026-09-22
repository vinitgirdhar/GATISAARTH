import 'dart:math' as math;

import '../math/nav_math.dart';

/// Physical feature represented by a locally registered anchor.
///
/// The QR/AprilTag deliberately carries only this record's identifier. Its
/// coordinates remain in the device-local registry, so a printed arbitrary
/// coordinate can never become a navigation measurement.
enum PortalAnchorKind { tunnelPortal, parkingCheckpoint, approvedLandmark }

class PortalAnchor {
  const PortalAnchor({
    required this.id,
    required this.label,
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.horizontalSigmaM,
    required this.kind,
    this.visualDescriptor,
    this.radioId,
  })  : assert(id != ''),
        assert(label != ''),
        assert(horizontalSigmaM > 0);

  final String id;
  final String label;
  final double latitudeDeg;
  final double longitudeDeg;

  /// Surveyed/declared uncertainty for the fixed physical marker.
  final double horizontalSigmaM;
  final PortalAnchorKind kind;
  final String? visualDescriptor;
  final String? radioId;
}

class PortalAnchorRegistry {
  PortalAnchorRegistry(Iterable<PortalAnchor> anchors)
      : _byId =
            Map.unmodifiable({for (final anchor in anchors) anchor.id: anchor});

  final Map<String, PortalAnchor> _byId;

  PortalAnchor? operator [](String id) => _byId[id];
  Iterable<PortalAnchor> get values => _byId.values;
}

class PortalAnchorContext {
  const PortalAnchorContext({
    required this.inOutage,
    required this.estimatedLatitudeDeg,
    required this.estimatedLongitudeDeg,
    required this.horizontalSigmaM,
  });

  final bool inOutage;
  final double estimatedLatitudeDeg;
  final double estimatedLongitudeDeg;
  final double horizontalSigmaM;
}

enum PortalAnchorRejection {
  malformedPayload,
  unknownAnchor,
  notInOutage,
  invalidEstimate,
  implausibleResidual,
}

class PortalAnchorMeasurement {
  const PortalAnchorMeasurement({
    required this.anchor,
    required this.residualM,
  });

  final PortalAnchor anchor;
  final double residualM;

  double get horizontalSigmaM => anchor.horizontalSigmaM;
}

class PortalAnchorDecision {
  const PortalAnchorDecision.accepted(this.measurement) : reason = null;

  const PortalAnchorDecision.rejected(this.reason) : measurement = null;

  final PortalAnchorMeasurement? measurement;
  final PortalAnchorRejection? reason;

  bool get accepted => measurement != null;
}

/// Trust boundary for a QR/AprilTag portal observation.
///
/// A scan proves only that the camera saw an identifier. It may be used as a
/// filter measurement only during a GNSS outage, only if that identifier is
/// locally registered, and only if its residual is plausible for the current
/// uncertainty. Visual re-localisation feeds this same gate later in Phase B.
class PortalAnchorPolicy {
  const PortalAnchorPolicy({required this.registry});

  static const String _prefix = 'GSARTH-ANCHOR:1:';
  static const double _minimumResidualGateM = 50;
  static const double _sigmaGate = 4;

  final PortalAnchorRegistry registry;

  PortalAnchorDecision evaluate({
    required String payload,
    required PortalAnchorContext context,
  }) {
    final id = _anchorIdFrom(payload);
    if (id == null) {
      return const PortalAnchorDecision.rejected(
        PortalAnchorRejection.malformedPayload,
      );
    }
    final anchor = registry[id];
    if (anchor == null) {
      return const PortalAnchorDecision.rejected(
        PortalAnchorRejection.unknownAnchor,
      );
    }
    if (!context.inOutage) {
      return const PortalAnchorDecision.rejected(
          PortalAnchorRejection.notInOutage);
    }
    if (!_isFiniteCoordinate(
            context.estimatedLatitudeDeg, context.estimatedLongitudeDeg) ||
        !context.horizontalSigmaM.isFinite ||
        context.horizontalSigmaM <= 0) {
      return const PortalAnchorDecision.rejected(
        PortalAnchorRejection.invalidEstimate,
      );
    }

    final residualM = NavMath.horizontalDistance(
      lat0: context.estimatedLatitudeDeg,
      lon0: context.estimatedLongitudeDeg,
      lat1: anchor.latitudeDeg,
      lon1: anchor.longitudeDeg,
    );
    final gateM = math.max(
      _minimumResidualGateM,
      _sigmaGate * context.horizontalSigmaM + anchor.horizontalSigmaM,
    );
    if (!residualM.isFinite || residualM > gateM) {
      return const PortalAnchorDecision.rejected(
        PortalAnchorRejection.implausibleResidual,
      );
    }
    return PortalAnchorDecision.accepted(
      PortalAnchorMeasurement(anchor: anchor, residualM: residualM),
    );
  }

  static String? _anchorIdFrom(String payload) {
    if (!payload.startsWith(_prefix)) return null;
    final id = payload.substring(_prefix.length);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id)) return null;
    return id;
  }

  static bool _isFiniteCoordinate(double latitudeDeg, double longitudeDeg) =>
      latitudeDeg.isFinite &&
      longitudeDeg.isFinite &&
      latitudeDeg.abs() <= 90 &&
      longitudeDeg.abs() <= 180;
}
