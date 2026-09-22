import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/features/navigation_engine/domain/entities/navigation_state.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/satellite_breakdown.dart';

void main() {
  const empty = SatelliteBreakdownModel(
    navIC: SatelliteInfoModel(count: 0, signalStrength: 0),
    gps: SatelliteInfoModel(count: 0, signalStrength: 0),
    galileo: SatelliteInfoModel(count: 0, signalStrength: 0),
    glonass: SatelliteInfoModel(count: 0, signalStrength: 0),
  );

  testWidgets('never presents placeholder satellites as hardware telemetry',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SatelliteBreakdown(
          satelliteBreakdown: empty,
          isHardwareBacked: false,
          rawMeasurementsSupported: false,
        ),
      ),
    ));

    expect(find.text('Waiting for Android GNSS status'), findsOneWidget);
    expect(find.text('0 Sats Active'), findsOneWidget);
    expect(find.textContaining('Raw measurements'), findsNothing);
  });

  testWidgets('labels receiver-backed counts and raw capability',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SatelliteBreakdown(
          satelliteBreakdown: SatelliteBreakdownModel(
            navIC: SatelliteInfoModel(count: 2, signalStrength: 39),
            gps: SatelliteInfoModel(count: 4, signalStrength: 35),
            galileo: SatelliteInfoModel(count: 1, signalStrength: 31),
            glonass: SatelliteInfoModel(count: 0, signalStrength: 0),
          ),
          isHardwareBacked: true,
          rawMeasurementsSupported: true,
        ),
      ),
    ));

    expect(find.text('7 Sats Active'), findsOneWidget);
    expect(find.text('Receiver-backed · raw measurements available'),
        findsOneWidget);
    expect(find.text('2 sats • 39.0 dBHz'), findsOneWidget);
  });
}
