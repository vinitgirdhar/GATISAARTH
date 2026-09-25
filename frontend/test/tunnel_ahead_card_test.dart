import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/tunnel_lookahead.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/tunnel_ahead_card.dart';

import 'support/load_fonts.dart';

Future<void> _pump(WidgetTester tester, TunnelAhead t,
    {bool validated = true, double width = 360}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
        body: TunnelAheadCard(tunnel: t, speedAidValidated: validated)),
  ));
}

void main() {
  setUpAll(loadAppFonts);

  const ahead = TunnelAhead(
    distanceM: 1240,
    lengthM: 850,
    remainingM: 850,
    inside: false,
    exitLat: 0,
    exitLon: 0,
    name: 'Pragati Maidan Tunnel',
  );

  testWidgets('warns with the distance, the name and the length',
      (tester) async {
    await _pump(tester, ahead);
    expect(find.textContaining('Tunnel ahead · 1.24 km'), findsOneWidget);
    expect(find.textContaining('Pragati Maidan Tunnel · 850 m long'),
        findsOneWidget);
    expect(find.textContaining('speed aid validated'), findsOneWidget);
  });

  testWidgets('says plainly when the speed aid has not been validated',
      (tester) async {
    await _pump(tester, ahead, validated: false);
    expect(find.textContaining('not validated yet'), findsOneWidget);
  });

  testWidgets('inside, it counts down to the exit', (tester) async {
    await _pump(
      tester,
      const TunnelAhead(
        distanceM: 0,
        lengthM: 850,
        remainingM: 320,
        inside: true,
        exitLat: 0,
        exitLon: 0,
      ),
    );
    expect(find.textContaining('In tunnel · 320 m to the exit'), findsOneWidget);
  });

  testWidgets('fits a 320 dp phone without overflow', (tester) async {
    await _pump(tester, ahead, width: 320);
    expect(tester.takeException(), isNull);
  });
}
