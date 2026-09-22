import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/features/navigation_engine/domain/entities/navigation_state.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/navigation_map.dart';

void main() {
  testWidgets('outage map draws ranked road hypotheses without a false route',
      (tester) async {
    const corridors = [
      RoadCorridorModel(
        polyline: [28.61, 77.20, 28.62, 77.20],
        probability: 0.55,
        roadName: 'Main Road',
      ),
      RoadCorridorModel(
        polyline: [28.61, 77.2002, 28.62, 77.2002],
        probability: 0.45,
        roadName: 'Service Road',
      ),
    ];
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: NavigationMap(
            navigationState: NavigationStateModel(
              latitude: 28.615,
              longitude: 77.20,
              heading: 0,
              speed: 10,
              confidence: 0.5,
              fusionMode: FusionMode.deadReckoning,
            ),
            marginMeters: 30,
            roadCorridors: corridors,
            expand: true,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    final layers = tester.widgetList<PolylineLayer>(find.byType(PolylineLayer));
    final lines = layers.expand((layer) => layer.polylines).toList();
    expect(lines, hasLength(2));
    expect(lines.first.strokeWidth, greaterThan(lines.last.strokeWidth));
    expect(find.text('2 possible roads'), findsOneWidget);
  });
}
