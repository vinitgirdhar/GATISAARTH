import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/features/navigation_engine/domain/navigation_safety.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/nav_safety_badge.dart';

import 'support/load_fonts.dart';

const _assessments = <TrustAssessment>[
  TrustAssessment.waitingForFix,
  TrustAssessment(
    level: TrustLevel.green,
    headline: 'Position reliable',
    reason: 'GNSS accuracy ±6 m',
    limited: false,
    displayPrecisionM: 1,
  ),
  TrustAssessment(
    level: TrustLevel.amber,
    headline: 'Dead reckoning active',
    reason: 'No GNSS fix — estimating from sensors',
    limited: false,
    displayPrecisionM: 10,
  ),
  TrustAssessment(
    level: TrustLevel.orange,
    headline: 'High uncertainty',
    reason: 'Position uncertainty growing quickly',
    limited: false,
    displayPrecisionM: 25,
  ),
  TrustAssessment(
    level: TrustLevel.red,
    headline: 'Position unreliable',
    reason: 'Uncertainty beyond the safe limit',
    limited: true,
    displayPrecisionM: 50,
  ),
];

void main() {
  setUpAll(loadAppFonts);

  for (final assessment in _assessments) {
    testWidgets('renders ${assessment.level}', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NavSafetyBadge(assessment: assessment)),
      ));
      await tester.pump();

      expect(find.byType(NavSafetyBadge), findsOneWidget);
      expect(find.textContaining(assessment.reason), findsOneWidget);
      final semantics = tester.getSemantics(find.byType(NavSafetyBadge));
      expect(semantics.label, contains(assessment.reason));
    });
  }

  testWidgets('RED shows the limited banner with its exact copy',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: NavSafetyLimitedBanner()),
    ));
    await tester.pump();

    expect(find.text(NavSafetyLimitedBanner.message), findsOneWidget);
    expect(
      find.text('Limited navigation — position unreliable. Follow road signs.'),
      findsOneWidget,
    );
  });

  testWidgets('non-RED levels have no limited banner in a plain badge tree',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NavSafetyBadge(assessment: _assessments[1])),
    ));
    await tester.pump();

    expect(find.byType(NavSafetyLimitedBanner), findsNothing);
  });
}
