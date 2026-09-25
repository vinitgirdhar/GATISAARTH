import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/model/outage_recovery.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_scope.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/screens/outage_log_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';
import 'support/load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppHarness> pump(WidgetTester tester, {double width = 360}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
    final h = AppHarness();
    await tester.pumpWidget(LiveSessionScope(
      controller: h.controller,
      child: const MaterialApp(home: OutageLogScreen()),
    ));
    await frames(tester, count: 2);
    return h;
  }

  testWidgets('empty, it explains what will appear', (tester) async {
    await pump(tester);
    expect(find.textContaining('No outage has ended yet'), findsOneWidget);
    expect(find.byTooltip('Copy as CSV'), findsNothing);
  });

  testWidgets('lists each scored outage with its verdict', (tester) async {
    final h = await pump(tester);
    h.controller.outageLog
      ..add(const OutageRecovery(
          durationS: 42,
          distanceM: 610,
          errorM: 18,
          fixAccuracyM: 5,
          endedAtUs: 1,
          coreLed: true))
      ..add(const OutageRecovery(
          durationS: 70,
          distanceM: 900,
          errorM: 180,
          fixAccuracyM: 8,
          endedAtUs: 2,
          coreLed: true));
    await tester.pumpWidget(LiveSessionScope(
      controller: h.controller,
      child: const MaterialApp(home: OutageLogScreen()),
    ));
    await frames(tester, count: 2);
    expect(find.textContaining('#1 · 42 s · 610 m'), findsOneWidget);
    expect(find.text('3.0 %'), findsOneWidget);
    expect(find.text('20.0 %'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byTooltip('Copy as CSV'), findsOneWidget);
  });

  testWidgets('fits a 320 dp phone', (tester) async {
    await pump(tester, width: 320);
    expect(tester.takeException(), isNull);
  });
}
