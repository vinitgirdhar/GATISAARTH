import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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

/// A manually surveyed pack can be sideloaded into the app-specific Android
/// files directory. The empty bundled pack remains the safe default.
class InstalledAnchorPackSource implements AnchorPackSource {
  const InstalledAnchorPackSource(
      {this.directory, this.fallback = const BundledAnchorPackSource()});

  final Future<Directory?> Function()? directory;
  final AnchorPackSource fallback;

  @override
  Future<AnchorPack> load() async {
    Directory? base;
    try {
      base = await (directory?.call() ?? getExternalStorageDirectory());
    } catch (_) {
      return fallback.load();
    }
    if (base != null) {
      final installed = File('${base.path}${Platform.pathSeparator}anchors'
          '${Platform.pathSeparator}portal_anchors.json');
      if (await installed.exists()) {
        return AnchorPack.parse(await installed.readAsString());
      }
    }
    return fallback.load();
  }
}

class EmptyAnchorPackSource implements AnchorPackSource {
  const EmptyAnchorPackSource();

  @override
  Future<AnchorPack> load() async =>
      const AnchorPack(packId: 'none', anchors: []);
}
