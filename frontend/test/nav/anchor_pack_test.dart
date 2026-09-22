import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/anchors/anchor_pack.dart';

void main() {
  test('loads a versioned local anchor pack with visual and radio metadata', () {
    final pack = AnchorPack.parse('''
{"schemaVersion":1,"packId":"sih-demo","anchors":[
 {"id":"portal-a","label":"Portal A","kind":"tunnelPortal","lat":28.639,"lon":77.0661,"sigmaM":4,"visualDescriptor":"f0f0","radioId":"GS-DEMO-A"}
]}''');

    expect(pack.packId, 'sih-demo');
    expect(pack.anchors.single.id, 'portal-a');
    expect(pack.anchors.single.visualDescriptor, 'f0f0');
    expect(pack.anchors.single.radioId, 'GS-DEMO-A');
  });

  test('rejects unsupported, duplicate, and invalid-coordinate packs', () {
    expect(() => AnchorPack.parse('{"schemaVersion":2,"packId":"x","anchors":[]}'), throwsFormatException);
    expect(
      () => AnchorPack.parse('{"schemaVersion":1,"packId":"x","anchors":[{"id":"a","label":"A","kind":"tunnelPortal","lat":0,"lon":0,"sigmaM":4},{"id":"a","label":"B","kind":"tunnelPortal","lat":1,"lon":1,"sigmaM":4}]}'),
      throwsFormatException,
    );
    expect(
      () => AnchorPack.parse('{"schemaVersion":1,"packId":"x","anchors":[{"id":"a","label":"A","kind":"tunnelPortal","lat":99,"lon":0,"sigmaM":4}]}'),
      throwsFormatException,
    );
  });
}
