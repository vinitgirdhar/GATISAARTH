import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/maps/map_download_service.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/features/offline_maps/domain/map_download_prompt.dart';
import 'package:gatisaarth/features/offline_maps/presentation/map_download_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';
import 'support/fake_map_packs.dart';
import 'support/load_fonts.dart';

final _offer = MapOffer(
  region: OfflineCatalog.maharashtra,
  packs: [OfflineCatalog.pune, OfflineCatalog.maharashtraState],
);

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late FakeInstaller installer;
  late MapDownloadService downloads;
  late MapDownloadPrompter prompter;
  var online = true;

  /// A page with one button that opens the sheet.
  Future<void> openSheet(WidgetTester tester) async {
    final maps = await noPacksInstalled();
    final dir = mockPathProvider();
    installer = FakeInstaller(dir);
    online = true;
    downloads = MapDownloadService(
      installer: installer,
      maps: maps,
      isOnline: () async => online,
    );
    prompter = MapDownloadPrompter(maps: maps);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(411, 915) * 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showMapDownloadSheet(
                context,
                offer: _offer,
                prompter: prompter,
                downloads: downloads,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await frames(tester, count: 12);
  }

  Future<bool?> neverAsked() async =>
      (await SharedPreferences.getInstance())
          .getBool('map_prompt_never_maharashtra');
  Future<int?> snoozedAt() async => (await SharedPreferences.getInstance())
      .getInt('map_prompt_snoozed_at_maharashtra');

  testWidgets('it names the place, lists the maps with sizes and totals them',
      (tester) async {
    await openSheet(tester);
    expect(find.text('Save maps for Pune & Pimpri-Chinchwad?'), findsOneWidget);
    expect(find.textContaining('You are in Maharashtra'), findsOneWidget);
    expect(find.text('Pune & Pimpri-Chinchwad'), findsOneWidget);
    expect(find.text('Maharashtra statewide'), findsOneWidget);
    expect(find.text('17 MB'), findsOneWidget);
    expect(find.text('79 MB'), findsOneWidget);
    expect(find.text('Download 96 MB'), findsOneWidget);
    expect(find.textContaining('mobile data'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Do not ask again'), findsOneWidget);
    // Nothing downloads on its own.
    expect(installer.started, isEmpty);
  });

  testWidgets('unticking a map changes the total, and none disables the button',
      (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Maharashtra statewide'));
    await frames(tester, count: 2);
    expect(find.text('Download 17 MB'), findsOneWidget);

    await tester.tap(find.text('Pune & Pimpri-Chinchwad'));
    await frames(tester, count: 2);
    expect(find.text('Choose a map'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('Download starts the ticked maps, city first, and closes',
      (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Download 96 MB'));
    await frames(tester, count: 10);

    expect(find.text('Save maps for Pune & Pimpri-Chinchwad?'), findsNothing);
    expect(installer.started, ['pune', 'maharashtra-state']);
    expect(find.textContaining('Downloading maps'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
    // Answered: it must not be treated as a dismissal.
    expect(await snoozedAt(), isNull);
  });

  testWidgets('only the ticked maps are downloaded', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Maharashtra statewide'));
    await frames(tester, count: 2);
    await tester.tap(find.text('Download 17 MB'));
    await frames(tester, count: 10);
    expect(installer.started, ['pune']);
  });

  testWidgets('"Not now" holds the question back and downloads nothing',
      (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Not now'));
    await frames(tester, count: 8);

    expect(find.text('Save maps for Pune & Pimpri-Chinchwad?'), findsNothing);
    expect(installer.started, isEmpty);
    expect(await snoozedAt(), isNotNull);
    expect(await neverAsked(), isNull);
  });

  testWidgets('"Do not ask again" is remembered', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Do not ask again'));
    await frames(tester, count: 8);

    expect(installer.started, isEmpty);
    expect(await neverAsked(), isTrue);
  });

  testWidgets('swiping it away counts as "Not now"', (tester) async {
    await openSheet(tester);
    await tester.fling(find.text('Save maps for Pune & Pimpri-Chinchwad?'),
        const Offset(0, 500), 2000);
    await frames(tester, count: 12);

    expect(find.text('Save maps for Pune & Pimpri-Chinchwad?'), findsNothing);
    expect(await snoozedAt(), isNotNull);
    expect(installer.started, isEmpty);
  });

  testWidgets('with no connection it says so instead of failing later',
      (tester) async {
    await openSheet(tester);
    online = false;
    await tester.tap(find.text('Download 96 MB'));
    await frames(tester, count: 8);

    expect(find.textContaining('No internet connection'), findsOneWidget);
    expect(installer.started, isEmpty);
  });
}
