import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/features/anchors/presentation/portal_anchor_screen.dart';

void main() {
  testWidgets('scans locally and shows accepted portal feedback', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PortalAnchorScreen(
        scannerBuilder: (onPayload) => TextButton(
          onPressed: () => onPayload('GSARTH-ANCHOR:1:portal-a'),
          child: const Text('Test scan'),
        ),
        onPayload: (_) async => const PortalAnchorUiResult(
          accepted: true,
          message: 'Portal A accepted · EKF corrected',
        ),
      ),
    ));

    expect(find.textContaining('processed on this phone'), findsOneWidget);
    await tester.tap(find.text('Test scan'));
    await tester.pump();
    expect(find.textContaining('EKF corrected'), findsOneWidget);
  });

  testWidgets('shows a safe rejection without closing the scanner',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PortalAnchorScreen(
        scannerBuilder: (onPayload) => TextButton(
          onPressed: () => onPayload('bad'),
          child: const Text('Test scan'),
        ),
        onPayload: (_) async => const PortalAnchorUiResult(
          accepted: false,
          message: 'Unknown or unsafe marker',
        ),
      ),
    ));

    await tester.tap(find.text('Test scan'));
    await tester.pump();
    expect(find.text('Unknown or unsafe marker'), findsOneWidget);
    expect(find.text('Test scan'), findsOneWidget);
  });
}
