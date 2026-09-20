import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/theme/app_theme.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/sync_status.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/sync_capsule.dart';

import 'support/load_fonts.dart';

const _idle = SyncStatus.idle;

SyncStatus _searching() => syncStatusOf(
      sensorsLive: true,
      modelReady: true,
      location: LocationStatus.searching,
      reacquiring: false,
    );

SyncStatus _coldStart() => syncStatusOf(
      sensorsLive: false,
      modelReady: false,
      location: LocationStatus.initializing,
      reacquiring: false,
    );

Widget _host(ValueNotifier<SyncStatus> status, {bool reduceMotion = false}) =>
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ValueListenableBuilder<SyncStatus>(
                  valueListenable: status,
                  builder: (_, s, __) => SyncCapsule(status: s),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(loadAppFonts);

  testWidgets('nothing is shown when nothing is syncing', (tester) async {
    final status = ValueNotifier(_idle);
    await tester.pumpWidget(_host(status));
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('Syncing'), findsNothing);
    expect(find.text('Synced'), findsNothing);
  });

  testWidgets('a step that finishes at once never flashes a capsule',
      (tester) async {
    final status = ValueNotifier(_searching());
    await tester.pumpWidget(_host(status));
    await tester.pump(const Duration(milliseconds: 100));
    status.value = _idle;
    await tester.pump(); // the rebuild, before any more time passes
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('Syncing'), findsNothing);
    expect(find.text('Synced'), findsNothing);
  });

  testWidgets('drops in, says what it waits for, then says Synced and leaves',
      (tester) async {
    final status = ValueNotifier(_searching());
    await tester.pumpWidget(_host(status));
    await tester.pump(const Duration(milliseconds: 350)); // past the delay
    await tester.pump(const Duration(milliseconds: 500)); // slide-in done

    expect(find.textContaining('Syncing'), findsOneWidget);
    expect(find.textContaining('Finding satellites'), findsOneWidget);
    // Sits inside the screen, under the status area, not off the top.
    expect(tester.getTopLeft(find.byType(SyncCapsule)).dy, greaterThanOrEqualTo(0));

    status.value = _idle;
    await tester.pump();
    expect(find.text('Synced'), findsOneWidget);
    expect(find.textContaining('Syncing'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1700)); // hold over
    await tester.pump(const Duration(milliseconds: 400)); // slid away
    expect(find.text('Synced'), findsNothing);
  });

  testWidgets('follows the step it is actually on', (tester) async {
    final status = ValueNotifier(_coldStart());
    await tester.pumpWidget(_host(status));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Starting sensors'), findsOneWidget);

    status.value = _searching();
    await tester.pump();
    expect(find.textContaining('Finding satellites'), findsOneWidget);
  });

  testWidgets('a long satellite search says so and what to do', (tester) async {
    final status = ValueNotifier(_searching());
    await tester.pumpWidget(_host(status));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('Finding satellites'), findsOneWidget);

    await tester.pump(const Duration(seconds: 41));
    expect(find.textContaining('Still searching'), findsOneWidget);
    expect(find.textContaining('open sky'), findsOneWidget);
  });

  testWidgets('takes no taps: what is under it stays usable', (tester) async {
    var taps = 0;
    final status = ValueNotifier(_searching());
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: ValueListenableBuilder<SyncStatus>(
                valueListenable: status,
                builder: (_, s, __) => SyncCapsule(status: s),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byType(SyncCapsule), warnIfMissed: false);
    expect(taps, 1);
  });

  testWidgets('with animations off it still appears and leaves, just instantly',
      (tester) async {
    final status = ValueNotifier(_searching());
    await tester.pumpWidget(_host(status, reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.textContaining('Syncing'), findsOneWidget);
    status.value = _idle;
    await tester.pump();
    expect(find.text('Synced'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump();
    expect(find.text('Synced'), findsNothing);
  });

  testWidgets('fits a 320 dp phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final status = ValueNotifier(_coldStart());
    await tester.pumpWidget(_host(status));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Syncing'), findsOneWidget);
  });
}
