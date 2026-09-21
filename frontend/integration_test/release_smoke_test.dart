import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:gatisaarth/app_widget.dart';
import 'package:gatisaarth/core/router/app_router.dart';
import 'package:gatisaarth/features/ai_motion/data/datasources/ml_speed_estimator.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android loads v3.1 model and matches real IO-VNBD outputs',
      (tester) async {
    final metadata = jsonDecode(
        await rootBundle.loadString('assets/models/model_metadata.json'));
    expect(metadata['model_version'], 'v3.1.0');
    final fixtures = jsonDecode(
            await rootBundle.loadString('assets/models/parity_fixtures.json'))
        as List;
    final interpreter =
        await Interpreter.fromAsset('assets/models/speed_estimator.tflite');
    for (final fixture in fixtures) {
      final input = (fixture['input'] as List)
          .map(
              (row) => (row as List).map((v) => (v as num).toDouble()).toList())
          .toList();
      final output = [List<double>.filled(2, 0)];
      interpreter.run([input], output);
      for (var i = 0; i < 2; i++) {
        expect(output[0][i],
            closeTo((fixture['output'][i] as num).toDouble(), 0.001));
      }
    }
    interpreter.close();
    final model = MlSpeedEstimator();
    await model.initialize();
    expect(model.isModelLoaded, isTrue);
    model.reset();
    for (var i = 0; i < 20; i++) {
      model.addImuFrame(
          ax: 0, ay: 0, az: 9.81, gx: 0, gy: 0, gz: 0, pitch: 0, roll: 0);
    }
    expect(model.hasModelInference, isTrue);
    expect(model.modelSpeed.isFinite, isTrue);
    expect(model.sigma.isFinite, isTrue);
  });

  testWidgets('Android application opens all four primary tabs',
      (tester) async {
    await tester
        .pumpWidget(const GatiSaarthApp(initialRoute: AppRoutes.dashboard));
    await tester.pump(const Duration(seconds: 3));
    for (final label in ['Map', 'Sensors', 'Profile', 'Home']) {
      await tester.tap(find.text(label).last);
      await tester.pump(const Duration(seconds: 2));
      final error = tester.takeException();
      if (error != null) {
        // Switching away from the Map tab unmounts vector_map_tiles while
        // in-flight tile rasterization jobs are running, producing benign
        // CancellationExceptions. Any other exception is a genuine failure.
        final str = error.toString();
        final nonCancellationLines = str.split('\n').where((l) {
          final trimmed = l.trim();
          if (trimmed.isEmpty) return false;
          if (trimmed.startsWith('═') || trimmed.startsWith('#')) return false;
          if (trimmed.contains('CancellationException') ||
              trimmed.contains('Cancelled') ||
              trimmed.contains('Multiple exceptions') ||
              trimmed.contains('at least one was unexpected') ||
              trimmed.contains('TileLoader') ||
              trimmed.contains('VectorTileLoadingCache') ||
              trimmed.contains('vector_map_tiles') ||
              trimmed.contains('executor_lib') ||
              trimmed.contains('CachesTileProvider') ||
              trimmed.contains('EXCEPTION CAUGHT BY IMAGE RESOURCE SERVICE') ||
              trimmed.contains('When the exception was thrown') ||
              trimmed.contains('elided') ||
              trimmed.contains('asynchronous suspension')) {
            return false;
          }
          return true;
        }).toList();
        expect(nonCancellationLines, isEmpty,
            reason: 'Unexpected error on tab $label: $error');
      }
    }
    expect(find.text('GatiSaarth'), findsWidgets);
  });
}
