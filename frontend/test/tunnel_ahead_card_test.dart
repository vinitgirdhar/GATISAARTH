import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/tunnel_lookahead.dart';
import 'package:gatisaarth/features/navigation_engine/domain/dr_readiness.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/tunnel_ahead_card.dart';

import 'support/load_fonts.dart';

const _readyReport = DrReadinessReport(
  alignment: ReadinessRow(
      label: 'Alignment', status: ReadinessStatus.ok, reason: 'Converged'),
  imu: ReadinessRow(
      label: 'IMU healthy', status: ReadinessStatus.ok, reason: 'Nominal'),
  roadLock: ReadinessRow(
      label: 'Road lock available',
      status: ReadinessStatus.ok,
      reason: 'Road nearby'),
  velocity: ReadinessRow(
      label: 'Velocity stable', status: ReadinessStatus.ok, reason: 'Steady'),
  gnssQuality: ReadinessRow(
      label: 'GNSS quality', status: ReadinessStatus.ok, reason: 'Normal'),
  overall: DrReadinessLevel.ready,
);

Future<void> _pump(WidgetTester tester, TunnelAhead t,
    {bool validated = true,
    double width = 360,
    DrReadinessReport? readiness}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
        body: TunnelAheadCard(
            tunnel: t, speedAidValidated: validated, readiness: readiness)),
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
    expect(
        find.textContaining('Tunnel 1.24 km ahead · GNSS loss preparation'),
        findsOneWidget);
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

  testWidgets('shows the readiness checklist while approaching',
      (tester) async {
    await _pump(tester, ahead, readiness: _readyReport);
    expect(find.text('Dead reckoning ready'), findsOneWidget);
    expect(find.textContaining('Alignment:'), findsOneWidget);
    expect(find.textContaining('Road lock available:'), findsOneWidget);
  });

  testWidgets('hides the checklist once inside the tunnel', (tester) async {
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
      readiness: _readyReport,
    );
    expect(find.text('Dead reckoning ready'), findsNothing);
  });

  testWidgets('a 320 dp phone with the checklist still does not overflow',
      (tester) async {
    await _pump(tester, ahead, width: 320, readiness: _readyReport);
    expect(tester.takeException(), isNull);
  });
}
