import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/theme/app_theme.dart';
import 'package:gatisaarth/features/navigation_engine/domain/entities/navigation_state.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/ai_inference_panel.dart';

import 'support/load_fonts.dart';

Widget _panel(InferenceStatsModel stats) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: AiInferencePanel(inferenceStats: stats)),
    );

void main() {
  setUpAll(loadAppFonts);

  testWidgets('shows -- for every figure until the model has actually run',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_panel(const InferenceStatsModel(
      latencyMs: null,
      modelVersion: 'Model not loaded',
      confidence: null,
      estimatedSpeed: null,
    )));
    expect(find.text('--'), findsNWidgets(3));
    expect(find.text('Model not loaded'), findsOneWidget);
    expect(find.textContaining(' ms'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('shows real figures once the model has run', (tester) async {
    await tester.pumpWidget(_panel(const InferenceStatsModel(
      latencyMs: 5,
      modelVersion: 'v2.0.0',
      confidence: 0.87,
      estimatedSpeed: 12.34,
    )));
    expect(find.text('5 ms'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    expect(find.text('12.3 m/s'), findsOneWidget);
  });
}
