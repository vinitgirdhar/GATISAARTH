import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';

void main() {
  const mumbaiPoint = LatLng(19.076, 72.8777);
  const delhiPoint = LatLng(28.639, 77.0661);
  const bengaluruPoint = LatLng(12.9716, 77.5946);

  test('every pack is a valid box with a positive size', () {
    for (final p in OfflineCatalog.packs) {
      expect(p.south, lessThan(p.north), reason: p.id);
      expect(p.west, lessThan(p.east), reason: p.id);
      expect(p.south, inInclusiveRange(-90, 90), reason: p.id);
      expect(p.west, inInclusiveRange(-180, 180), reason: p.id);
      expect(p.maxZoom, inInclusiveRange(8, 16), reason: p.id);
      expect(p.approxBytes, greaterThan(1e6), reason: p.id);
      expect(p.fileName, '${p.id}.pmtiles');
    }
  });

  test('ids and file names are unique', () {
    final ids = OfflineCatalog.packs.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('Delhi and Maharashtra are both offered', () {
    expect(OfflineCatalog.regions.map((r) => r.name),
        ['Delhi NCR', 'Maharashtra']);
    expect(OfflineCatalog.delhi.packs, hasLength(1));
    expect(OfflineCatalog.maharashtra.packs.length, greaterThanOrEqualTo(2));
  });

  test('city archives are details drawn over a statewide overview', () {
    final state = OfflineCatalog.maharashtraState;
    expect(state.detail, isFalse);
    for (final p in OfflineCatalog.maharashtra.packs.where((p) => p.detail)) {
      expect(p.maxZoom, greaterThan(state.maxZoom), reason: p.id);
      expect(p.south, greaterThanOrEqualTo(state.south), reason: p.id);
      expect(p.north, lessThanOrEqualTo(state.north), reason: p.id);
      expect(p.west, greaterThanOrEqualTo(state.west), reason: p.id);
      expect(p.east, lessThanOrEqualTo(state.east), reason: p.id);
    }
  });

  test('the whole set stays inside the size the app was planned for', () {
    final total =
        OfflineCatalog.packs.fold<int>(0, (sum, p) => sum + p.approxBytes);
    expect(total, inInclusiveRange(165e6, 175e6));
  });

  test('a point resolves to the archives that hold it', () {
    expect(OfflineCatalog.packsAt(delhiPoint).map((p) => p.id), ['delhi-ncr']);
    expect(OfflineCatalog.packsAt(mumbaiPoint).map((p) => p.id),
        containsAll(['maharashtra-state', 'mumbai']));
    expect(OfflineCatalog.packsAt(bengaluruPoint), isEmpty);
  });

  test('the region a phone in West Delhi needs is covered', () {
    // The point the app's own tests and the bundled raster tiles centre on.
    expect(OfflineCatalog.delhiNcr.contains(delhiPoint), isTrue);
  });

  test('intersects is true for overlap and false for a clear miss', () {
    final p = OfflineCatalog.pune;
    expect(
        p.intersects(south: 18.0, west: 73.0, north: 18.5, east: 73.7), isTrue);
    expect(
        p.intersects(south: 19.0, west: 73.0, north: 19.5, east: 73.7), isFalse);
  });

  test('the archives on disk match the catalogue (when present)', () {
    for (final p in OfflineCatalog.packs) {
      final file = File('assets/maps/packs/${p.fileName}');
      if (!file.existsSync()) continue; // a checkout without the big files
      expect(file.lengthSync(), p.approxBytes, reason: p.fileName);
    }
  });

  test('the build script cuts exactly the boxes the app expects', () {
    final script = File('../tools/offline_maps/build_offline_maps.py');
    expect(script.existsSync(), isTrue);
    final row = RegExp(
      r'\("([a-z-]+)",\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*(\d+)\)',
    );
    final fromScript = {
      for (final m in row.allMatches(script.readAsStringSync()))
        m.group(1)!: [
          double.parse(m.group(2)!), // west
          double.parse(m.group(3)!), // south
          double.parse(m.group(4)!), // east
          double.parse(m.group(5)!), // north
          int.parse(m.group(6)!), // max zoom
        ],
    };
    expect(fromScript.keys.toSet(),
        OfflineCatalog.packs.map((p) => p.id).toSet());
    for (final p in OfflineCatalog.packs) {
      expect(fromScript[p.id], [p.west, p.south, p.east, p.north, p.maxZoom],
          reason: p.id);
    }
  });
}
