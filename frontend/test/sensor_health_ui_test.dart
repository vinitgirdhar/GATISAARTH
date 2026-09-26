import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_scope.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/screens/tabs/sensors_tab.dart';

import 'support/app_harness.dart';
import 'support/load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'diagnostics can be expanded and show pending values before sensor data '
      'arrives', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 3000);
    addTearDown(tester.view.reset);
    final h = AppHarness();
    await tester.pumpWidget(LiveSessionScope(
      controller: h.controller,
      child: const MaterialApp(home: Scaffold(body: SensorsTab())),
    ));
    await frames(tester, count: 3);

    final liveCount = find.textContaining(' live');
    expect(liveCount, findsOneWidget);
    expect(
      tester.getCenter(liveCount).dx,
      greaterThan(tester.getCenter(find.text('Technical diagnostics')).dx),
    );
    await tester.tap(find.text('Technical diagnostics'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Navigation Hardware Check'), findsOneWidget);
    expect(find.text('Mount quality'), findsOneWidget);
    // Nothing has been measured yet: the aggregate chip must say so, never a
    // made-up PASS.
    expect(find.text('--'), findsWidgets);
  });
}
