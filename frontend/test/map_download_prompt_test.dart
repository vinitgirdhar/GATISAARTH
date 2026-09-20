import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/features/offline_maps/domain/map_download_prompt.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_map_packs.dart';

const _delhi = LatLng(28.639, 77.0661);
const _pune = LatLng(18.5204, 73.8567);
const _mumbai = LatLng(19.0760, 72.8777);
const _ruralMaharashtra = LatLng(19.9, 76.5); // inside the state, no city pack
const _bengaluru = LatLng(12.9716, 77.5946);

Future<OfflineMapService> _phoneWith(List<OfflinePack> installed) async {
  final service = OfflineMapService(
    locator: FakeMapPackLocator({
      for (final p in installed) p.fileName: fakeLocation(p.approxBytes),
    }),
    opener: (l, p) async => EmptyTileProvider(),
  );
  await service.load();
  return service;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a phone in Delhi without the Delhi map is offered it', () async {
    final prompter = MapDownloadPrompter(maps: await _phoneWith([]));
    final offer = (await prompter.offerAt(_delhi))!;
    expect(offer.region.id, 'delhi');
    expect(offer.packs.map((p) => p.id), ['delhi-ncr']);
    expect(offer.bytes, OfflineCatalog.delhiNcr.approxBytes);
  });

  test('...and not when it already has it (bundled, or downloaded)', () async {
    final prompter =
        MapDownloadPrompter(maps: await _phoneWith([OfflineCatalog.delhiNcr]));
    expect(await prompter.offerAt(_delhi), isNull);
  });

  test('in Pune it offers the city first, then the state overview', () async {
    final prompter = MapDownloadPrompter(maps: await _phoneWith([]));
    final offer = (await prompter.offerAt(_pune))!;
    expect(offer.region.id, 'maharashtra');
    expect(offer.packs.map((p) => p.id), ['pune', 'maharashtra-state']);
    expect(offer.headline.name, contains('Pune'));
    expect(
      offer.bytes,
      OfflineCatalog.pune.approxBytes +
          OfflineCatalog.maharashtraState.approxBytes,
    );
  });

  test('it only offers what is missing', () async {
    final withState = MapDownloadPrompter(
        maps: await _phoneWith([OfflineCatalog.maharashtraState]));
    expect((await withState.offerAt(_pune))!.packs.map((p) => p.id), ['pune']);

    final withCity =
        MapDownloadPrompter(maps: await _phoneWith([OfflineCatalog.mumbai]));
    expect((await withCity.offerAt(_mumbai))!.packs.map((p) => p.id),
        ['maharashtra-state']);

    final everything = MapDownloadPrompter(
      maps: await _phoneWith(
          [OfflineCatalog.pune, OfflineCatalog.maharashtraState]),
    );
    expect(await everything.offerAt(_pune), isNull);
  });

  test('outside the cities only the state overview is offered', () async {
    final prompter = MapDownloadPrompter(maps: await _phoneWith([]));
    final offer = (await prompter.offerAt(_ruralMaharashtra))!;
    expect(offer.packs.map((p) => p.id), ['maharashtra-state']);
  });

  test('nothing is offered outside the regions the app knows', () async {
    final prompter = MapDownloadPrompter(maps: await _phoneWith([]));
    expect(await prompter.offerAt(_bengaluru), isNull);
    expect(MapDownloadPrompter.regionAt(_bengaluru), isNull);
  });

  test('"Not now" holds the question back for a few days, then asks again',
      () async {
    var now = DateTime(2026, 9, 20, 12);
    final prompter = MapDownloadPrompter(
      maps: await _phoneWith([]),
      clock: () => now,
      snooze: const Duration(days: 3),
    );
    final offer = (await prompter.offerAt(_pune))!;
    await prompter.notNow(offer.region);

    expect(await prompter.offerAt(_pune), isNull);
    now = now.add(const Duration(days: 2));
    expect(await prompter.offerAt(_pune), isNull);
    now = now.add(const Duration(days: 2));
    expect(await prompter.offerAt(_pune), isNotNull, reason: 'four days on');
  });

  test('"Never" is for good, and only for that region', () async {
    final prompter = MapDownloadPrompter(maps: await _phoneWith([]));
    final offer = (await prompter.offerAt(_pune))!;
    await prompter.neverAsk(offer.region);

    expect(await prompter.offerAt(_pune), isNull);
    expect(await prompter.offerAt(_mumbai), isNull, reason: 'same region');
    expect(await prompter.offerAt(_delhi), isNotNull, reason: 'another region');
  });

  test('answers survive a restart', () async {
    final first = MapDownloadPrompter(maps: await _phoneWith([]));
    await first.neverAsk(MapDownloadPrompter.regionAt(_pune)!);
    // A new prompter over the same stored preferences.
    final second = MapDownloadPrompter(maps: await _phoneWith([]));
    expect(await second.offerAt(_pune), isNull);
  });
}
