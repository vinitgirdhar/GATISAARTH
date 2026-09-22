import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'portal_anchor.dart';
import 'visual_relocalization.dart';

/// Deliberately small, offline 256-bit difference hash. This is a conservative
/// candidate generator, not proof that a landmark is the surveyed object:
/// [VisualRelocalizationPolicy] and the EKF still have to accept the update.
class VisualLandmarkMatcher {
  const VisualLandmarkMatcher(this.registry);

  final PortalAnchorRegistry registry;

  static final RegExp descriptorPattern = RegExp(r'^[0-9a-f]{64}$');

  static String? describe(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) return null;
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null || decoded.width < 32 || decoded.height < 32) {
      return null;
    }
    final small = img.copyResize(
      decoded,
      width: 17,
      height: 16,
      interpolation: img.Interpolation.average,
    );
    final hex = StringBuffer();
    var nibble = 0;
    var bits = 0;
    var brightComparisons = 0;
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final left = small.getPixel(x, y).luminance;
        final right = small.getPixel(x + 1, y).luminance;
        final bit = left > right ? 1 : 0;
        brightComparisons += bit;
        nibble = (nibble << 1) | bit;
        bits++;
        if (bits == 4) {
          hex.write(nibble.toRadixString(16));
          nibble = 0;
          bits = 0;
        }
      }
    }
    // Flat/low-texture scenes produce a common hash and are unsafe anchors.
    if (brightComparisons < 40 || brightComparisons > 216) return null;
    return hex.toString();
  }

  VisualMatchObservation? match(List<int> bytes) {
    final query = describe(bytes);
    if (query == null) return null;
    return matchDescriptor(query);
  }

  VisualMatchObservation? matchDescriptor(String query) {
    if (!descriptorPattern.hasMatch(query)) return null;
    String? bestId;
    var best = -1.0;
    var second = 0.0;
    for (final anchor in registry.values) {
      final candidate = anchor.visualDescriptor;
      if (candidate == null || !descriptorPattern.hasMatch(candidate)) continue;
      final score = 1 - _hamming(query, candidate) / 256;
      if (score > best) {
        second = best < 0 ? 0 : best;
        best = score;
        bestId = anchor.id;
      } else if (score > second) {
        second = score;
      }
    }
    if (bestId == null) return null;
    return VisualMatchObservation(
      anchorId: bestId,
      confidence: best,
      secondBestConfidence: second,
      processedOnDevice: true,
    );
  }

  static int _hamming(String a, String b) {
    var distance = 0;
    for (var i = 0; i < 64; i++) {
      final diff = int.parse(a[i], radix: 16) ^ int.parse(b[i], radix: 16);
      distance += _bitCount[diff];
    }
    return distance;
  }

  static const _bitCount = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4];
}
