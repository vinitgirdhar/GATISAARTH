import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/anchors/anchor_pack.dart';

void main() {
  test('loads a versioned local anchor pack with visual and radio metadata',
      () {
    final pack = AnchorPack.parse('''
{"schemaVersion":1,"packId":"sih-demo","anchors":[
 {"id":"portal-a","label":"Portal A","kind":"tunnelPortal","lat":28.639,"lon":77.0661,"sigmaM":4,"visualDescriptor":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","radioId":"aa:bb:cc:dd:ee:ff"}
]}''');

    expect(pack.packId, 'sih-demo');
    expect(pack.anchors.single.id, 'portal-a');
    expect(pack.anchors.single.visualDescriptor,
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef');
    expect(pack.anchors.single.radioId, 'aa:bb:cc:dd:ee:ff');
  });

  test('rejects unsupported, duplicate, and invalid-coordinate packs', () {
    expect(
        () => AnchorPack.parse('{"schemaVersion":2,"packId":"x","anchors":[]}'),
        throwsFormatException);
    expect(
      () => AnchorPack.parse(
          '{"schemaVersion":1,"packId":"x","anchors":[{"id":"a","label":"A","kind":"tunnelPortal","lat":0,"lon":0,"sigmaM":4},{"id":"a","label":"B","kind":"tunnelPortal","lat":1,"lon":1,"sigmaM":4}]}'),
      throwsFormatException,
    );
    expect(
      () => AnchorPack.parse(
          '{"schemaVersion":1,"packId":"x","anchors":[{"id":"a","label":"A","kind":"tunnelPortal","lat":99,"lon":0,"sigmaM":4}]}'),
      throwsFormatException,
    );
  });

  test('rejects malformed visual descriptors and duplicate radio IDs', () {
    expect(
      () => AnchorPack.parse('''
{"schemaVersion":1,"packId":"x","anchors":[
 {"id":"a","label":"A","kind":"approvedLandmark","lat":28,"lon":77,"sigmaM":5,"visualDescriptor":"f0f0"}
]}'''),
      throwsFormatException,
    );
    expect(
      () => AnchorPack.parse('''
{"schemaVersion":1,"packId":"x","anchors":[
 {"id":"a","label":"A","kind":"tunnelPortal","lat":28,"lon":77,"sigmaM":5,"radioId":"aa:bb:cc:dd:ee:ff"},
 {"id":"b","label":"B","kind":"tunnelPortal","lat":28,"lon":77,"sigmaM":5,"radioId":"aa:bb:cc:dd:ee:ff"}
]}'''),
      throwsFormatException,
    );
  });
}
