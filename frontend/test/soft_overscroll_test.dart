import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/widgets/soft_overscroll.dart';

Widget _app({ScrollBehavior? behavior}) => MaterialApp(
      scrollBehavior: behavior,
      home: Scaffold(
        body: ListView(
          children: [
            for (var i = 0; i < 30; i++)
              SizedBox(height: 100, child: Text('row $i')),
          ],
        ),
      ),
    );

/// Drags the list down from the top edge (an overscroll) and returns the
/// stretch the framework applied while the finger was still down.
Future<double> _pullDownStrength(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(200, 300));
  for (var i = 0; i < 8; i++) {
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 16));
  }
  final strength = tester.widget<StretchEffect>(find.byType(StretchEffect));
  final value = strength.stretchStrength.abs();
  await gesture.up();
  await tester.pumpAndSettle();
  return value;
}

void main() {
  testWidgets('the app stretch is a fixed fraction of the platform stretch',
      (tester) async {
    await tester.pumpWidget(_app());
    final platform = await _pullDownStrength(tester);

    await tester.pumpWidget(_app(behavior: const AppScrollBehavior()));
    final ours = await _pullDownStrength(tester);

    expect(platform, greaterThan(0), reason: 'the drag must overscroll');
    expect(ours / platform, closeTo(kStretchStrength, 1e-6));
    // Half, then 30 % less again.
    expect(kStretchStrength, closeTo(0.5 * 0.7, 1e-12));
  });

  testWidgets('the stretch springs back to rest after release',
      (tester) async {
    await tester.pumpWidget(_app(behavior: const AppScrollBehavior()));
    final gesture = await tester.startGesture(const Offset(200, 300));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.widget<StretchEffect>(find.byType(StretchEffect)).stretchStrength,
      0,
    );
  });

  testWidgets('other platforms keep their own overscroll', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(_app(behavior: const AppScrollBehavior()));
      expect(find.byType(SoftStretchOverscrollIndicator), findsNothing);
      expect(find.byType(StretchEffect), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a fling into the end stretches, at reduced strength',
      (tester) async {
    await tester.pumpWidget(_app(behavior: const AppScrollBehavior()));
    // Fling upwards hard enough to hit the bottom edge.
    await tester.fling(find.byType(ListView), const Offset(0, -600), 8000);
    var peak = 0.0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final effects = find.byType(StretchEffect);
      if (effects.evaluate().isEmpty) continue;
      final s = tester.widget<StretchEffect>(effects).stretchStrength.abs();
      if (s > peak) peak = s;
    }
    await tester.pumpAndSettle();
    // The platform's own absorb stretch is capped at 1.25 * 0.016 * ~2 = ~0.05
    // in normalised units; at reduced strength it must stay well below that.
    expect(peak, lessThan(0.03));
  });
}
