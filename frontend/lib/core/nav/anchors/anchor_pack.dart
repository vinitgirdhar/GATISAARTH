import 'dart:convert';

import 'portal_anchor.dart';

class AnchorPack {
  const AnchorPack({required this.packId, required this.anchors});

  final String packId;
  final List<PortalAnchor> anchors;

  factory AnchorPack.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
      throw const FormatException('Unsupported anchor pack schema');
    }
    final packId = decoded['packId'];
    final rawAnchors = decoded['anchors'];
    if (packId is! String || packId.trim().isEmpty || rawAnchors is! List) {
      throw const FormatException('Invalid anchor pack metadata');
    }
    final ids = <String>{};
    final radios = <String>{};
    final anchors = <PortalAnchor>[];
    for (final raw in rawAnchors) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid anchor record');
      }
      final id = raw['id'];
      final label = raw['label'];
      final kindName = raw['kind'];
      final lat = raw['lat'];
      final lon = raw['lon'];
      final sigma = raw['sigmaM'];
      final descriptor = raw['visualDescriptor'];
      final radioId = raw['radioId'];
      PortalAnchorKind? kind;
      for (final candidate in PortalAnchorKind.values) {
        if (candidate.name == kindName) kind = candidate;
      }
      if (id is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id) ||
          !ids.add(id) ||
          label is! String ||
          label.trim().isEmpty ||
          kind == null ||
          lat is! num ||
          lon is! num ||
          sigma is! num ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180 ||
          !sigma.isFinite ||
          sigma <= 0 ||
          (descriptor != null &&
              (descriptor is! String ||
                  !RegExp(r'^[0-9a-f]{64}$').hasMatch(descriptor))) ||
          (radioId != null &&
              (radioId is! String ||
                  !RegExp(r'^[0-9a-f]{2}(:[0-9a-f]{2}){5}$')
                      .hasMatch(radioId) ||
                  !radios.add(radioId)))) {
        throw const FormatException('Invalid or duplicate anchor');
      }
      anchors.add(PortalAnchor(
        id: id,
        label: label,
        latitudeDeg: lat.toDouble(),
        longitudeDeg: lon.toDouble(),
        horizontalSigmaM: sigma.toDouble(),
        kind: kind,
        visualDescriptor: descriptor as String?,
        radioId: radioId as String?,
      ));
    }
    return AnchorPack(packId: packId, anchors: List.unmodifiable(anchors));
  }
}
