import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/pack_installer.dart';

/// Developer tool, not a test: cuts any region out of the newest Protomaps
/// OpenStreetMap build with HTTP range requests, exactly as the phone does
/// when it downloads a map pack, and writes `<id>.pmtiles` to a folder.
///
/// Used to get the roads under the real IO-VNBD drives (West Midlands, UK) so
/// map matching can be scored on real sensors on real roads:
///
///     EXTRACT_PACK_DIR=ml/data/raw/osm EXTRACT_ID=west-midlands \
///       EXTRACT_BBOX=52.33,-1.66,52.58,-1.20 \
///       flutter test test/tool/extract_region_pack_test.dart
///
/// EXTRACT_BBOX is `south,west,north,east` in degrees.
void main() {
  final dir = Platform.environment['EXTRACT_PACK_DIR'];
  final id = Platform.environment['EXTRACT_ID'] ?? 'region';
  final bbox = Platform.environment['EXTRACT_BBOX'];

  test('extract $id from the newest Protomaps build',
      skip: dir == null || bbox == null
          ? 'set EXTRACT_PACK_DIR and EXTRACT_BBOX'
          : false,
      timeout: const Timeout(Duration(minutes: 30)), () async {
    final v = bbox!.split(',').map(double.parse).toList();
    final pack = OfflinePack(
      id: id,
      name: id,
      south: v[0],
      west: v[1],
      north: v[2],
      east: v[3],
      maxZoom: 15,
      approxBytes: 0,
    );
    final installer = PackInstaller(folder: () async => Directory(dir!));
    var lastPrinted = -1;
    final file = await installer.install(pack, onProgress: (f) {
      final pct = (f * 10).floor();
      if (pct != lastPrinted) {
        lastPrinted = pct;
        // ignore: avoid_print
        print('extract $id: ${(f * 100).round()} %');
      }
    });
    // ignore: avoid_print
    print('wrote ${file.path} (${file.lengthSync()} bytes)');
    expect(file.lengthSync(), greaterThan(1000000));
  });
}
