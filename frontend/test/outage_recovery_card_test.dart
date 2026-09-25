import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/model/outage_recovery.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/outage_recovery_card.dart';

import 'support/load_fonts.dart';

Future<void> _pump(WidgetTester tester, OutageRecovery r,
    {double width = 360}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: OutageRecoveryCard(recovery: r)),
  ));
}

void main() {
  setUpAll(loadAppFonts);

  const good = OutageRecovery(
    durationS: 42,
    distanceM: 610,
    errorM: 18.3,
    fixAccuracyM: 5,
    endedAtUs: 1,
    coreLed: true,
  );

  testWidgets('scores the outage the returning fix just ended', (tester) async {
    await _pump(tester, good);
    expect(find.textContaining('42 s'), findsOneWidget);
    expect(find.textContaining('610 m'), findsOneWidget);
    expect(find.textContaining('18 m'), findsOneWidget);
    expect(find.textContaining('3.0 %'), findsOneWidget);
    expect(find.textContaining('within the 10 % target'), findsOneWidget);
    // The truth is the phone's own fix, and the card says how good that is.
    expect(find.textContaining('±5 m'), findsOneWidget);
  });

  testWidgets('says plainly when the drift missed the target', (tester) async {
    await _pump(
      tester,
      const OutageRecovery(
        durationS: 70,
        distanceM: 900,
        errorM: 180,
        fixAccuracyM: 8,
        endedAtUs: 1,
        coreLed: true,
      ),
    );
    expect(find.textContaining('20.0 %'), findsOneWidget);
    expect(find.textContaining('above the 10 % target'), findsOneWidget);
  });

  testWidgets('does not credit the core for an outage it did not lead',
      (tester) async {
    await _pump(
      tester,
      const OutageRecovery(
        durationS: 30,
        distanceM: 300,
        errorM: 12,
        fixAccuracyM: 5,
        endedAtUs: 1,
        coreLed: false,
      ),
    );
    expect(find.textContaining('core was not leading'), findsOneWidget);
  });

  testWidgets('fits a 320 dp phone without overflow', (tester) async {
    await _pump(tester, good, width: 320);
    expect(tester.takeException(), isNull);
  });
}
