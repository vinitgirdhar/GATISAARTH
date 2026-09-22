import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:gatisaarth/core/nav/anchors/portal_anchor.dart';
import 'package:gatisaarth/core/nav/anchors/visual_landmark_matcher.dart';

void main() {
  img.Image patterned(bool reverse) {
    final image = img.Image(width: 170, height: 160);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final v = ((x ~/ 10 + y ~/ 10) % 2 == (reverse ? 1 : 0)) ? 230 : 25;
        image.setPixelRgb(x, y, v, v, v);
      }
    }
    return image;
  }

  test('local camera bytes yield a bounded 256-bit descriptor', () {
    final descriptor =
        VisualLandmarkMatcher.describe(img.encodePng(patterned(false)));
    expect(descriptor, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(VisualLandmarkMatcher.describe([]), isNull);
  });

  test('registered descriptor matches locally and never uploads image', () {
    final image = img.encodePng(patterned(false));
    final descriptor = VisualLandmarkMatcher.describe(image)!;
    final matcher = VisualLandmarkMatcher(PortalAnchorRegistry([
      PortalAnchor(
        id: 'landmark-a',
        label: 'Approved landmark',
        latitudeDeg: 28.6,
        longitudeDeg: 77.1,
        horizontalSigmaM: 5,
        kind: PortalAnchorKind.approvedLandmark,
        visualDescriptor: descriptor,
      ),
    ]));
    final match = matcher.match(image);
    expect(match, isNotNull);
    expect(match!.anchorId, 'landmark-a');
    expect(match.confidence, 1);
    expect(match.processedOnDevice, isTrue);
    expect(matcher.match(img.encodePng(patterned(true)))!.confidence,
        lessThan(0.94));
  });
}
