import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_scope.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/screens/tabs/sensors_tab.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/navic_weight_indicator.dart';

import 'support/app_harness.dart';
import 'support/load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the speed model is described as the FP32 file it ships as',
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

    expect(find.text('TFLite FP32 model active'), findsOneWidget);
    expect(find.textContaining('Int8'), findsNothing);
  });

  testWidgets(
      'the NavIC card reports the receiver\'s share of the fix, '
      'not a fusion weight or an S-band priority', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: NavicWeightIndicator(navicWeight: 0.25)),
    ));

    expect(find.text('25%'), findsOneWidget);
    expect(find.text('NAVIC SHARE OF FIX'), findsOneWidget);
    expect(find.textContaining('used in its last fix'), findsOneWidget);
    expect(find.textContaining('FUSION WEIGHT'), findsNothing);
    expect(find.textContaining('S-band'), findsNothing);
    expect(find.textContaining('priority'), findsNothing);
  });
}
