import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_scope.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/simulated_outage_sheet.dart';

import 'support/app_harness.dart';
import 'support/load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppHarness> pump(WidgetTester tester, {double width = 360}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.reset);
    final h = AppHarness();
    await h.controller.start();
    await tester.pumpWidget(LiveSessionScope(
      controller: h.controller,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showSimulatedOutageSheet(context, h.controller),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await frames(tester, count: 2);
    return h;
  }

  testWidgets('disables Start with a reason when there is no live fix yet',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('open'));
    await frames(tester, count: 2);

    expect(find.text('Simulate GNSS loss'), findsOneWidget);
    expect(find.textContaining('Waiting for a live GNSS fix'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('picking a duration and starting shows the running banner',
      (tester) async {
    final h = await pump(tester);
    h.gateway.fixController.add(delhiFix);
    await frames(tester, count: 2);
    h.controller.tick();

    await tester.tap(find.text('open'));
    await frames(tester, count: 2);

    await tester.tap(find.text('20 s'));
    await frames(tester, count: 2);
    await tester.tap(find.text('Start'));
    await frames(tester, count: 2);

    expect(find.textContaining('GNSS blackout (simulated)'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(h.controller.isSimulatingOutage, isTrue);
  });

  testWidgets('cancelling from the sheet stops the blackout with no result',
      (tester) async {
    final h = await pump(tester);
    h.gateway.fixController.add(delhiFix);
    await frames(tester, count: 2);
    h.controller.tick();
    expect(h.controller.startSimulatedOutage(const Duration(seconds: 30)), isNull);

    await tester.tap(find.text('open'));
    await frames(tester, count: 6);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await frames(tester, count: 2);

    expect(h.controller.isSimulatingOutage, isFalse);
    expect(h.controller.lastSimulatedOutageResult, isNull);
  });

  testWidgets('shows the scorecard once a run finishes, with a PASS/target '
      'verdict', (tester) async {
    final h = await pump(tester);
    h.gateway.fixController.add(delhiFix);
    await frames(tester, count: 2);
    h.controller.tick();
    expect(h.controller.startSimulatedOutage(const Duration(seconds: 5)), isNull);

    h.now = h.now.add(const Duration(seconds: 6));
    h.controller.tick();
    expect(h.controller.lastSimulatedOutageResult, isNotNull);

    await tester.tap(find.text('open'));
    await frames(tester, count: 2);

    expect(find.textContaining('GNSS blackout simulated at'), findsOneWidget);
    expect(find.textContaining('Along-track'), findsOneWidget);
    expect(find.textContaining('Uncertainty grew'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('fits a 320 dp phone without overflow', (tester) async {
    await pump(tester, width: 320);
    await tester.tap(find.text('open'));
    await frames(tester, count: 2);
    expect(tester.takeException(), isNull);
  });
}
