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
      'the hardware check and mount quality cards show up before any '
      'sensor data has arrived, honestly pending rather than a fake pass',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 3000);
    addTearDown(tester.view.reset);
    final h = AppHarness();
    await tester.pumpWidget(LiveSessionScope(
      controller: h.controller,
      child: const MaterialApp(home: Scaffold(body: SensorsTab())),
    ));
    await frames(tester, count: 3);

    expect(find.text('Navigation Hardware Check'), findsOneWidget);
    expect(find.text('Mount quality'), findsOneWidget);
    // Nothing has been measured yet: the aggregate chip must say so, never a
    // made-up PASS.
    expect(find.text('--'), findsWidgets);
  });
}
