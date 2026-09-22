import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/gnss/gnss_integrity_monitor.dart';
import 'package:gatisaarth/core/platform/gnss/gnss_telemetry.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/gnss_integrity_panel.dart';

void main() {
  testWidgets('shows a receiver-backed sky plot, trend and honest warning',
      (tester) async {
    const telemetry = GnssTelemetrySnapshot(
      permissionGranted: true,
      statusSupported: true,
      rawMeasurementsSupported: true,
      rawMeasurementCount: 9,
      adrMeasurementCount: 4,
      satellites: [
        GnssSatellite(
          svid: 3,
          constellation: GnssConstellation.navic,
          cn0DbHz: 38,
          usedInFix: true,
          elevationDegrees: 45,
          azimuthDegrees: 120,
          carrierFrequencyHz: 1176.45e6,
        ),
        GnssSatellite(
          svid: 8,
          constellation: GnssConstellation.gps,
          cn0DbHz: 28,
          usedInFix: false,
          elevationDegrees: 25,
          azimuthDegrees: 260,
        ),
      ],
    );
    const assessment = GnssIntegrityAssessment(
      state: GnssSignalState.anomaly,
      reason: 'Receiver signal collapse detected; multipath is possible',
      meanCn0DbHz: 23,
      cn0ChangeDbHz: -15,
      usedRatio: 0.2,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GnssIntegrityPanel(
            telemetry: telemetry,
            assessment: assessment,
            cn0History: [40, 39, 38, 24, 23],
          ),
        ),
      ),
    ));

    expect(find.text('GNSS INTEGRITY LAB'), findsOneWidget);
    expect(find.textContaining('2 satellites'), findsOneWidget);
    expect(find.textContaining('9 raw observations'), findsOneWidget);
    expect(find.textContaining('4 ADR'), findsOneWidget);
    expect(find.textContaining('signal collapse'), findsOneWidget);
    expect(find.textContaining('spoof'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
