import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_reader.dart';
import 'package:gatisaarth/core/platform/maps/place_search.dart';

import 'support/fake_map_packs.dart';
import 'support/real_map_packs.dart' show realPackFile, skipUnlessPack;

/// The real Mumbai pack, opened through a plain [OfflineMapService] (no
/// [PackRoadGraphSource] involved - place search reads different layers of
/// the same archive). Null when the archive is not on this machine.
Future<OfflineMapService?> _mumbaiMaps() async {
  final file = realPackFile('mumbai');
  if (file == null) return null;
  final maps = OfflineMapService(
    locator: FakeMapPackLocator({
      'mumbai.pmtiles': PackLocation(
        path: file.path,
        offset: 0,
        length: file.lengthSync(),
        origin: PackOrigin.sideloaded,
      ),
    }),
  );
  await maps.load();
  return maps;
}

void main() {
  group('PlaceSearch', () {
    test('a blank query returns nothing', () async {
      final maps = await noPacksInstalled();
      final search = PlaceSearch(maps);
      expect(
        await search.search('', nearLat: 19.06, nearLon: 72.835),
        isEmpty,
      );
    });

    test('no pack covering the origin returns nothing, never throws', () async {
      final maps = await noPacksInstalled();
      final search = PlaceSearch(maps);
      expect(
        await search.search('bandra', nearLat: 19.06, nearLon: 72.835),
        isEmpty,
      );
    });

    test('finds a named place near Bandra on the real Mumbai pack', () async {
      final maps = await _mumbaiMaps();
      if (maps == null) {
        markTestSkipped(skipUnlessPack('mumbai')!);
        return;
      }
      final search = PlaceSearch(maps);
      final hits =
          await search.search('bandra', nearLat: 19.06, nearLon: 72.835);

      expect(hits, isNotEmpty);
      expect(hits.first.name.toLowerCase(), contains('bandra'));
      // Within a few km of the search origin, as the brief describes.
      expect(hits.first.distanceM, lessThan(8000));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('finds a named road near Bandra on the real Mumbai pack', () async {
      final maps = await _mumbaiMaps();
      if (maps == null) {
        markTestSkipped(skipUnlessPack('mumbai')!);
        return;
      }
      final search = PlaceSearch(maps);
      final hits =
          await search.search('hill road', nearLat: 19.06, nearLon: 72.835);

      expect(hits, isNotEmpty);
      expect(hits.first.name.toLowerCase(), contains('hill road'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('an exact/prefix match ranks before a mere substring match',
        () async {
      final maps = await _mumbaiMaps();
      if (maps == null) {
        markTestSkipped(skipUnlessPack('mumbai')!);
        return;
      }
      final search = PlaceSearch(maps);
      final hits =
          await search.search('bandra', nearLat: 19.06, nearLon: 72.835);
      if (hits.length < 2) return; // not enough data to compare tiers with

      // Every hit whose name starts with the query comes before every hit
      // where it is merely a substring.
      var sawSubstringOnly = false;
      for (final hit in hits) {
        final startsWith = hit.name.toLowerCase().startsWith('bandra');
        if (!startsWith) {
          sawSubstringOnly = true;
        } else {
          expect(sawSubstringOnly, isFalse,
              reason: '"${hit.name}" (a prefix match) ranked after a '
                  'substring-only match');
        }
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
