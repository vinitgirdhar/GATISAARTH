import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/maps/map_download_service.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_reader.dart';
import 'package:gatisaarth/core/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';
import 'support/fake_map_packs.dart';
import 'support/load_fonts.dart';

/// A phone with some maps inside the app and the rest in its own storage.
class _Phone implements MapPackLocator {
  _Phone(this.folder, {this.bundled = const {}});

  final Directory folder;
  final Set<String> bundled;

  @override
  Future<PackLocation?> locate(String fileName) async {
    final file = File('${folder.path}/$fileName');
    if (file.existsSync()) {
      return PackLocation(
        path: file.path,
        offset: 0,
        length: file.lengthSync(),
        origin: PackOrigin.downloaded,
      );
    }
    if (bundled.contains(fileName)) {
      return PackLocation(
        path: '/apk',
        offset: 0,
        length: 36834779,
        origin: PackOrigin.bundled,
      );
    }
    return null;
  }
}

/// A widget test that may build the vector map. The map's layer starts a 3 s
/// cache-maintenance timer of its own; the framework fails a test that ends with
/// a timer pending, so the tree is removed and the timer let run out first.
void mapTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late Directory folder;
  late FakeInstaller installer;
  late OfflineMapService maps;
  late MapDownloadService downloads;
  late AppHarness h;
  var online = true;

  Future<void> open(
    WidgetTester tester, {
    Set<String> bundled = const {},
    List<OfflinePack> onDisk = const [],
  }) async {
    mockPathProvider();
    folder = Directory.systemTemp.createTempSync('maps_screen_');
    addTearDown(() => folder.deleteSync(recursive: true));
    for (final p in onDisk) {
      File('${folder.path}/${p.fileName}')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(64, 1));
    }
    online = true;
    installer = FakeInstaller(folder);
    maps = OfflineMapService(
      locator: _Phone(folder, bundled: bundled),
      opener: (l, p) async => EmptyTileProvider(maxZoom: p.maxZoom),
    );
    await maps.load();
    downloads = MapDownloadService(
      installer: installer,
      maps: maps,
      isOnline: () async => online,
    );
    h = AppHarness();
    await h.pumpApp(
      tester,
      route: AppRoutes.offlineMaps,
      maps: maps,
      downloads: downloads,
      size: const Size(411, 2600),
    );
    await frames(tester, count: 12);
  }

  mapTest('ready maps say where they live, and only downloaded ones can '
      'be deleted', (tester) async {
    await open(
      tester,
      bundled: {'delhi-ncr.pmtiles'},
      onDisk: [
        for (final p in OfflineCatalog.maharashtra.packs) p,
      ],
    );

    expect(find.text('Ready offline'), findsNWidgets(2));
    expect(find.textContaining('Included with the app'), findsOneWidget);
    expect(find.textContaining('Downloaded'), findsNWidgets(6));
    // One delete control per downloaded map; the bundled one has none.
    expect(find.byIcon(Icons.delete_outline_rounded), findsNWidgets(6));
    expect(find.textContaining('of maps on this phone'), findsOneWidget);
  });

  testWidgets('with nothing installed every map offers a download with its '
      'size', (tester) async {
    await open(tester);

    expect(find.text('No offline maps on this phone yet'), findsOneWidget);
    expect(find.text('Not on this phone'), findsNWidgets(2));
    expect(find.text('Download 37 MB'), findsOneWidget);
    expect(find.text('Download all 134 MB'), findsOneWidget);
    expect(find.text('4.0 MB'), findsWidgets, reason: 'Nashik');
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
  });

  testWidgets('a small map downloads straight away and then shows as ready',
      (tester) async {
    await open(tester);
    final gate = Completer<void>();
    installer.hold = gate.future;

    await tester.tap(find.widgetWithText(TextButton, '4.0 MB'));
    await frames(tester, count: 3);
    expect(installer.started, ['nashik']);
    expect(find.textContaining('Downloading · 40%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Downloading 1 map'), findsOneWidget);

    gate.complete();
    await frames(tester, count: 5);
    expect(maps.isInstalled('nashik'), isTrue);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('a big download asks first, and Cancel starts nothing',
      (tester) async {
    await open(tester);

    await tester.tap(find.text('Download all 134 MB'));
    await frames(tester, count: 4);
    expect(find.text('Download Maharashtra?'), findsOneWidget);
    expect(find.textContaining('mobile data'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await frames(tester, count: 4);
    expect(installer.started, isEmpty);
    expect(downloads.isBusy, isFalse);

    await tester.tap(find.text('Download all 134 MB'));
    await frames(tester, count: 4);
    await tester.tap(find.widgetWithText(FilledButton, 'Download 134 MB'));
    await frames(tester, count: 12);
    expect(installer.started.length, 6, reason: 'all six, one after another');
    expect(installer.started.first, 'maharashtra-state');
  });

  testWidgets('without a connection it says so and starts nothing',
      (tester) async {
    await open(tester);
    online = false;

    await tester.tap(find.widgetWithText(TextButton, '4.0 MB'));
    await frames(tester, count: 4);
    expect(find.textContaining('No internet connection'), findsOneWidget);
    expect(installer.started, isEmpty);
  });

  testWidgets('a failed download explains itself and can be retried',
      (tester) async {
    await open(tester);
    installer.failWith = const SocketException('gone');

    await tester.tap(find.widgetWithText(TextButton, '4.0 MB'));
    await frames(tester, count: 5);
    expect(find.textContaining('No connection'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(maps.isInstalled('nashik'), isFalse);

    installer.failWith = null;
    await tester.tap(find.text('Retry'));
    await frames(tester, count: 5);
    expect(maps.isInstalled('nashik'), isTrue);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a download can be cancelled', (tester) async {
    await open(tester);
    final gate = Completer<void>();
    installer.hold = gate.future;

    await tester.tap(find.widgetWithText(TextButton, '4.0 MB'));
    await frames(tester, count: 3);
    await tester.tap(find.byTooltip('Cancel'));
    gate.complete();
    await frames(tester, count: 5);

    expect(maps.isInstalled('nashik'), isFalse);
    expect(downloads.isBusy, isFalse);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.widgetWithText(TextButton, '4.0 MB'), findsOneWidget,
        reason: 'the download button is back');
  });

  testWidgets('deleting a map asks first, frees the space and offers it again',
      (tester) async {
    await open(tester, onDisk: [OfflineCatalog.pune]);
    final file = File('${folder.path}/pune.pmtiles');
    expect(file.existsSync(), isTrue);

    await tester.tap(find.byTooltip('Delete ${OfflineCatalog.pune.name}'));
    await frames(tester, count: 4);
    expect(find.text('Delete ${OfflineCatalog.pune.name}?'), findsOneWidget);

    // Keep it.
    await tester.tap(find.text('Cancel'));
    await frames(tester, count: 4);
    expect(file.existsSync(), isTrue);

    await tester.tap(find.byTooltip('Delete ${OfflineCatalog.pune.name}'));
    await frames(tester, count: 4);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await frames(tester, count: 6);

    expect(file.existsSync(), isFalse);
    expect(maps.isInstalled('pune'), isFalse);
    expect(find.textContaining('deleted'), findsOneWidget);
    expect(find.text('17 MB'), findsWidgets, reason: 'download button is back');
  });

  mapTest('"Show on map" moves the preview and highlights the region',
      (tester) async {
    await open(tester, bundled: {'delhi-ncr.pmtiles'}, onDisk: [
      for (final p in OfflineCatalog.maharashtra.packs) p,
    ]);
    // The preview map opens on Delhi.
    expect(find.text('Delhi NCR'), findsWidgets);

    final show = find.text('Show on map');
    expect(show, findsNWidgets(2));
    await tester.tap(show.last); // Maharashtra
    await frames(tester, count: 20, ms: 100);
    // The chip in the preview now names the region.
    expect(find.text('Maharashtra'), findsWidgets);
  });
}
