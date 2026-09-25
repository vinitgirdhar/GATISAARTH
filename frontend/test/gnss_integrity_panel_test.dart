import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_health.dart';
import 'package:gatisaarth/core/platform/gnss/gnss_integrity_monitor.dart';
import 'package:gatisaarth/core/platform/gnss/gnss_telemetry.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/gnss_integrity_panel.dart';

import 'support/load_fonts.dart';

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

const legacyAssessment = GnssIntegrityAssessment(
  state: GnssSignalState.anomaly,
  reason: 'Receiver signal collapse detected; multipath is possible',
  meanCn0DbHz: 23,
  cn0ChangeDbHz: -15,
  usedRatio: 0.2,
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('shows a receiver-backed sky plot, trend and honest warning',
      (tester) async {
    const health = GnssHealthAssessment(
      state: GnssHealthState.multipathSuspected,
      reasons: ['Multipath indicator flagged on 4 measurements'],
      metrics: GnssHealthMetrics(
        satellitesUsed: 1,
        satellitesVisible: 2,
        meanCn0DbHz: 33,
        navicUsed: 1,
        navicVisible: 1,
        multipathDetectedCount: 4,
      ),
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GnssIntegrityPanel(
            telemetry: telemetry,
            assessment: legacyAssessment,
            cn0History: [40, 39, 38, 24, 23],
            health: health,
          ),
        ),
      ),
    ));

    expect(find.text('GNSS HEALTH'), findsOneWidget);
    expect(find.textContaining('MULTIPATH SUSPECTED'), findsWidgets);
    expect(
        find.textContaining('Multipath indicator flagged'), findsOneWidget);
    expect(find.textContaining('1/2'), findsOneWidget); // satellites used/visible
    expect(find.textContaining('4'), findsWidgets); // multipath count metric
    expect(find.textContaining('2 satellites'), findsOneWidget);
    expect(find.textContaining('9 raw observations'), findsOneWidget);
    expect(find.textContaining('4 ADR'), findsOneWidget);
    expect(find.textContaining('spoof'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('shows -- for waiting and for unsupported optional metrics',
      (tester) async {
    const health = GnssHealthAssessment(
      state: GnssHealthState.waiting,
      reasons: ['Waiting for a GNSS fix'],
      metrics: GnssHealthMetrics(),
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GnssIntegrityPanel(
            telemetry: null,
            assessment: legacyAssessment,
            cn0History: [],
            health: health,
          ),
        ),
      ),
    ));

    expect(find.text('GNSS HEALTH'), findsOneWidget);
    expect(find.textContaining('--'), findsWidgets);
    expect(find.textContaining('spoof'), findsNothing);
  });
}
