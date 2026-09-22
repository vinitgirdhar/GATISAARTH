import 'package:flutter/services.dart';

import '../../nav/anchors/anchor_pack.dart';

abstract interface class AnchorPackSource {
  Future<AnchorPack> load();
}

class BundledAnchorPackSource implements AnchorPackSource {
  const BundledAnchorPackSource(
      [this.assetPath = 'assets/config/portal_anchors.json']);

  final String assetPath;

  @override
  Future<AnchorPack> load() async =>
      AnchorPack.parse(await rootBundle.loadString(assetPath));
}

class EmptyAnchorPackSource implements AnchorPackSource {
  const EmptyAnchorPackSource();

  @override
  Future<AnchorPack> load() async =>
      const AnchorPack(packId: 'none', anchors: []);
}
