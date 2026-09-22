import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/anchors/anchor_pack_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unsurveyed bundled pack contains no usable anchor', () async {
    final pack = await const BundledAnchorPackSource().load();
    expect(pack.anchors, isEmpty);
  });

  test('installed surveyed pack replaces the empty default', () async {
    final root = await Directory.systemTemp.createTemp('gs-anchor-test-');
    addTearDown(() => root.delete(recursive: true));
    final anchors = Directory('${root.path}${Platform.pathSeparator}anchors');
    await anchors.create();
    await File('${anchors.path}${Platform.pathSeparator}portal_anchors.json')
        .writeAsString('''
{"schemaVersion":1,"packId":"field-pack","anchors":[
 {"id":"portal-a","label":"Surveyed A","kind":"tunnelPortal","lat":28.6,"lon":77.1,"sigmaM":5}
]}''');
    final pack =
        await InstalledAnchorPackSource(directory: () async => root).load();
    expect(pack.packId, 'field-pack');
    expect(pack.anchors.single.id, 'portal-a');
  });
}
