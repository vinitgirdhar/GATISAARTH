import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/sensors/parking_level.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/parking_level_card.dart';

import 'support/load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('names the floor and how far below the entry it is',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: ParkingLevelCard(level: ParkingLevel(level: -2, heightM: -6.2))),
    ));
    expect(find.text('Parking level B2'), findsOneWidget);
    expect(find.textContaining('6.2 m below where GNSS was lost'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
