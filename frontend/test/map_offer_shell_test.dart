import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/platform/maps/map_download_service.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';
import 'support/fake_map_packs.dart';
import 'support/load_fonts.dart';

const _bengaluru = GnssFix(
  latitude: 12.9716,
  longitude: 77.5946,
  altitude: 900,
  accuracy: 5,
  speed: 0,
);

const _title = 'Save maps for Pune & Pimpri-Chinchwad?';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late AppHarness h;
  late FakeInstaller installer;
  var online = true;
  Completer<void>? gate;

  /// Opens the app and delivers [fix] as the first position.
  Future<MapDownloadService> run(
    WidgetTester tester,
    GnssFix fix, {
    bool offer = true,
    List<OfflinePack> installed = const [],
    bool busy = false,
  }) async {
    final maps = OfflineMapService(
      locator: FakeMapPackLocator({
        for (final p in installed) p.fileName: fakeLocation(p.approxBytes),
      }),
      opener: (l, p) async => EmptyTileProvider(),
    );
    await maps.load();
    installer = FakeInstaller(mockPathProvider());
    online = true;
    final downloads = MapDownloadService(
      installer: installer,
      maps: maps,
      isOnline: () async => online,
      offerOnFirstFix: offer,
    );
    gate = null;
    if (busy) {
      gate = Completer<void>();
      installer.hold = gate!.future;
      downloads.download(OfflineCatalog.nagpur);
    }
    h = AppHarness();
    h.gateway.permission = LocationPermission.whileInUse;
    await h.pumpApp(tester, maps: maps, downloads: downloads);
    h.controller.tick();
    await tester.pump(const Duration(milliseconds: 800));

    h.gateway.fixController.add(fix);
    await tester.pump();
    h.controller.tick();
    await tester.pump();
    // Long enough for the two-second settle before the sheet opens.
    await frames(tester, count: 40);
    return downloads;
  }

  testWidgets('in Pune without its map, the first position offers it',
      (tester) async {
    await run(tester, puneFix);
    expect(find.text(_title), findsOneWidget);
    expect(find.text('Download 96 MB'), findsOneWidget);
  });

  testWidgets('in Delhi with the Delhi map already there, it stays quiet',
      (tester) async {
    await run(tester, delhiFix, installed: [OfflineCatalog.delhiNcr]);
    expect(find.textContaining('Save maps for'), findsNothing);
  });

  testWidgets('outside the regions the app knows, it stays quiet',
      (tester) async {
    await run(tester, _bengaluru);
    expect(find.textContaining('Save maps for'), findsNothing);
  });

  testWidgets('it does not ask while the phone is offline', (tester) async {
    final maps = await noPacksInstalled();
    installer = FakeInstaller(mockPathProvider());
    final downloads = MapDownloadService(
      installer: installer,
      maps: maps,
      isOnline: () async => false,
      offerOnFirstFix: true,
    );
    h = AppHarness();
    h.gateway.permission = LocationPermission.whileInUse;
    await h.pumpApp(tester, maps: maps, downloads: downloads);
    h.controller.tick();
    await tester.pump(const Duration(milliseconds: 800));
    h.gateway.fixController.add(puneFix);
    await tester.pump();
    h.controller.tick();
    await frames(tester, count: 40);
    expect(find.textContaining('Save maps for'), findsNothing);
  });

  testWidgets('it is off unless the app root turns it on', (tester) async {
    await run(tester, puneFix, offer: false);
    expect(find.textContaining('Save maps for'), findsNothing);
  });

  testWidgets('it does not ask on top of a download already running',
      (tester) async {
    await run(tester, puneFix, busy: true);
    expect(find.textContaining('Save maps for'), findsNothing);
    gate!.complete();
    await frames(tester, count: 5);
  });

  testWidgets('it asks once, not every time the position updates',
      (tester) async {
    await run(tester, puneFix);
    expect(find.text(_title), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await frames(tester, count: 10);
    expect(find.text(_title), findsNothing);

    for (var i = 0; i < 5; i++) {
      await h.fix(tester, puneFix);
      await frames(tester, count: 30);
    }
    expect(find.text(_title), findsNothing);
  });
}
