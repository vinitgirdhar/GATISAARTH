import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_reader.dart';
import 'package:gatisaarth/core/platform/maps/pmtiles_writer.dart' show TileMath;
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import 'support/fake_map_packs.dart';

void main() {
  group('OfflineMapService', () {
    test('finds nothing when the build carries no archives', () async {
      final service = await noPacksInstalled();
      expect(service.isLoaded, isTrue);
      expect(service.isLoading, isFalse);
      expect(service.installed, isEmpty);
      expect(service.installedBytes, 0);
      expect(service.covers(const LatLng(28.639, 77.0661)), isFalse);
    });

    test('opens the archives it can find and reports their real size',
        () async {
      final service = OfflineMapService(
        locator: FakeMapPackLocator({
          'delhi-ncr.pmtiles': fakeLocation(1234567),
          'pune.pmtiles': fakeLocation(999, origin: PackOrigin.sideloaded),
        }),
        opener: (l, p) async => EmptyTileProvider(),
      );
      await service.load();

      expect(service.installed.map((p) => p.pack.id),
          unorderedEquals(['delhi-ncr', 'pune']));
      expect(service.installedBytes, 1234567 + 999);
      expect(service.installedPack('pune')!.origin, PackOrigin.sideloaded);
      expect(service.isRegionComplete(OfflineCatalog.delhi), isTrue);
      expect(service.isRegionComplete(OfflineCatalog.maharashtra), isFalse);
      expect(service.installedCount(OfflineCatalog.maharashtra), 1);
      expect(service.covers(const LatLng(28.639, 77.0661)), isTrue);
      expect(service.covers(const LatLng(12.97, 77.59)), isFalse);
    });

    test('an archive that cannot be opened is reported, not fatal', () async {
      final service = OfflineMapService(
        locator: FakeMapPackLocator({
          'delhi-ncr.pmtiles': fakeLocation(10),
          'pune.pmtiles': fakeLocation(10),
        }),
        opener: (l, p) async {
          if (p.id == 'pune') throw const FormatException('bad header');
          return EmptyTileProvider();
        },
      );
      await service.load();
      expect(service.isInstalled('delhi-ncr'), isTrue);
      expect(service.isInstalled('pune'), isFalse);
      expect(service.problemWith('pune'), contains('bad header'));
      expect(service.problemWith('delhi-ncr'), isNull);
    });

    test('load again rescans, so pushed files show up', () async {
      final found = <String, PackLocation>{};
      final service = OfflineMapService(
        locator: FakeMapPackLocator(found),
        opener: (l, p) async => EmptyTileProvider(),
      );
      await service.load();
      expect(service.installed, isEmpty);

      found['nagpur.pmtiles'] = fakeLocation(5);
      await service.load();
      expect(service.isInstalled('nagpur'), isTrue);

      found.clear();
      await service.load();
      expect(service.installed, isEmpty);
    });

    test('tells listeners when loading starts and ends', () async {
      final service = OfflineMapService(
        locator: FakeMapPackLocator(const {}),
        opener: (l, p) async => EmptyTileProvider(),
      );
      var notes = 0;
      service.addListener(() => notes++);
      expect(service.isLoading, isTrue, reason: 'before the first scan');
      await service.load();
      expect(notes, greaterThanOrEqualTo(2));
    });

    test('a platform without the channel simply has no archives', () async {
      // The real locator, in a test: no plugin behind the channel.
      TestWidgetsFlutterBinding.ensureInitialized();
      final service = OfflineMapService(
        opener: (l, p) async => EmptyTileProvider(),
      );
      await service.load();
      expect(service.installed, isEmpty);
    });
  });

  group('OffsetFileAt', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('offset_file_at_');
      file = File('${dir.path}/blob.bin')
        ..writeAsBytesSync(Uint8List.fromList(
          List<int>.generate(1000, (i) => i % 251),
        ));
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Future<List<int>> read(OffsetFileAt at, int offset, int count) async =>
        (await at.readAt(offset, count)).toBytes();

    test('reads from the archive start, not the file start', () async {
      final at = OffsetFileAt(file, offset: 100, length: 500);
      expect(await read(at, 0, 5), [100, 101, 102, 103, 104]);
      expect(await read(at, 10, 3), [110, 111, 112]);
    });

    test('never reads past the end of the archive into its neighbour',
        () async {
      final at = OffsetFileAt(file, offset: 100, length: 50);
      expect((await read(at, 45, 20)).length, 5);
      expect(await read(at, 50, 10), isEmpty);
      expect(await read(at, 500, 10), isEmpty);
    });

    test('without a length it reads to the end of the file', () async {
      final at = OffsetFileAt(file);
      expect((await read(at, 990, 100)).length, 10);
    });

    test('many reads at once each get their own bytes', () async {
      final at = OffsetFileAt(file, offset: 7, length: 900);
      final results = await Future.wait([
        for (var i = 0; i < 60; i++) read(at, i * 10, 4),
      ]);
      for (var i = 0; i < 60; i++) {
        expect(
            results[i], [for (var k = 0; k < 4; k++) (7 + i * 10 + k) % 251]);
      }
    });
  });

  // A real archive: a 3 km square of West Delhi, 27 tiles, zoom 0-15.
  group('a real archive', () {
    final source = File('test/fixtures/mini_delhi.pmtiles');
    final present = source.existsSync();

    test('opens and serves tiles', () async {
      final service = OfflineMapService(
        locator: FakeMapPackLocator({
          'delhi-ncr.pmtiles': PackLocation(
            path: source.path,
            offset: 0,
            length: source.lengthSync(),
            origin: PackOrigin.sideloaded,
          ),
        }),
      );
      await service.load();
      expect(service.problemWith('delhi-ncr'), isNull);
      final provider = service.installedPack('delhi-ncr')!.provider;
      expect(provider.maximumZoom, 15);
      expect(provider.minimumZoom, 0);
      final root = await provider.provide(TileIdentity(0, 0, 0));
      expect(root.length, greaterThan(50));
    }, skip: present ? false : 'fixture missing');

    test('reads the same tiles when embedded in a bigger file (the APK case)',
        () async {
      final dir = Directory.systemTemp.createTempSync('embedded_pack_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final rnd = math.Random(7);
      final prefix =
          Uint8List.fromList(List.generate(4321, (_) => rnd.nextInt(256)));
      final suffix =
          Uint8List.fromList(List.generate(777, (_) => rnd.nextInt(256)));
      final archive = source.readAsBytesSync();
      final apk = File('${dir.path}/fake.apk')
        ..writeAsBytesSync([...prefix, ...archive, ...suffix]);

      final direct = await PmTilesVectorTileProvider.fromSource(source.path);
      final embedded = PmTilesVectorTileProvider.fromArchive(
        // ignore: invalid_use_of_visible_for_testing_member
        await PmTilesArchive.fromReadAt(
          OffsetFileAt(apk, offset: prefix.length, length: archive.length),
        ),
      );

      expect(embedded.maximumZoom, direct.maximumZoom);
      // A spread of tiles across zooms, including ones that do not exist.
      for (final t in [
        TileIdentity(0, 0, 0),
        TileIdentity(5, 22, 14), // exists only if the box reaches it
        TileIdentity(10, TileMath.tileX(77.065, 10), TileMath.tileY(28.64, 10)),
        TileIdentity(13, TileMath.tileX(77.065, 13), TileMath.tileY(28.64, 13)),
        TileIdentity(15, TileMath.tileX(77.065, 15), TileMath.tileY(28.64, 15)),
        TileIdentity(15, 1, 1), // nowhere near: absent in both
      ]) {
        Uint8List? a;
        Uint8List? b;
        try {
          a = await direct.provide(t);
        } on ProviderException {
          a = null;
        }
        try {
          b = await embedded.provide(t);
        } on ProviderException {
          b = null;
        }
        expect(b, a, reason: 'tile $t');
      }
    }, skip: present ? false : 'fixture missing');
  });
}
