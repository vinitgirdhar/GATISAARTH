import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/theme/app_theme.dart';
import 'package:gatisaarth/core/theme/theme_controller.dart';
import 'package:gatisaarth/core/widgets/theme_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `const`, so the framework skips it whenever its parent rebuilds - exactly
/// the shape of the Privacy tile that showed dark text on a dark card.
class _PaletteProbe extends StatelessWidget {
  const _PaletteProbe();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.surface,
        child: Text(
          'probe',
          textDirection: TextDirection.ltr,
          style: TextStyle(color: AppColors.textPrimary),
        ),
      );
}

Widget _host(ThemeController theme, {required bool animate}) => ThemeScope(
      controller: theme,
      child: ThemeTransitionHost(
        controller: theme,
        enabled: animate,
        child: AnimatedBuilder(
          animation: theme,
          builder: (context, _) {
            AppColors.isDark = theme.isDark;
            return const Directionality(
              textDirection: TextDirection.ltr,
              child: _PaletteProbe(),
            );
          },
        ),
      ),
    );

Color _probeColor(WidgetTester tester) =>
    tester.widget<Text>(find.text('probe')).style!.color!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppColors.isDark = false);

  testWidgets('a const widget that reads the palette follows a flip',
      (tester) async {
    final theme = ThemeController();
    await tester.pumpWidget(_host(theme, animate: false));
    expect(_probeColor(tester), AppColors.lightTextPrimary);

    await theme.toggle();
    await tester.pump();
    expect(_probeColor(tester), AppColors.darkTextPrimary);

    await theme.toggle();
    await tester.pump();
    expect(_probeColor(tester), AppColors.lightTextPrimary);
  });

  testWidgets('without the host that same const widget is left stale',
      (tester) async {
    // Pins the bug the host exists to fix, so a future "simplification" that
    // drops it cannot pass unnoticed.
    final theme = ThemeController();
    await tester.pumpWidget(ThemeScope(
      controller: theme,
      child: AnimatedBuilder(
        animation: theme,
        builder: (context, _) {
          AppColors.isDark = theme.isDark;
          return const Directionality(
            textDirection: TextDirection.ltr,
            child: _PaletteProbe(),
          );
        },
      ),
    ));
    await theme.toggle();
    await tester.pump();
    expect(_probeColor(tester), AppColors.lightTextPrimary,
        reason: 'const subtree is skipped: this is the bug');
  });

  testWidgets('a flip is wiped in and then the frozen picture is released',
      (tester) async {
    final theme = ThemeController();
    await tester.pumpWidget(_host(theme, animate: true));
    expect(find.byKey(ThemeTransitionHost.wipeOverlayKey), findsNothing);

    final flip = theme.toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await flip;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // The new brightness is already live underneath.
    expect(theme.isDark, isTrue);
    expect(_probeColor(tester), AppColors.darkTextPrimary);
    expect(find.byKey(ThemeTransitionHost.wipeOverlayKey), findsOneWidget,
        reason: 'the old picture covers the screen while it is wiped away');

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byKey(ThemeTransitionHost.wipeOverlayKey), findsNothing);
    expect(_probeColor(tester), AppColors.darkTextPrimary);
  });

  testWidgets('a second tap during a wipe still lands on the right theme',
      (tester) async {
    final theme = ThemeController();
    await tester.pumpWidget(_host(theme, animate: true));

    unawaited(theme.toggle());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    unawaited(theme.toggle());
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(theme.isDark, isFalse);
    expect(_probeColor(tester), AppColors.lightTextPrimary);
    expect(find.byKey(ThemeTransitionHost.wipeOverlayKey), findsNothing);
  });

  testWidgets('the wipe is skipped when animations are turned off',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final theme = ThemeController();
    await tester.pumpWidget(_host(theme, animate: true));
    await theme.toggle();
    await tester.pump();
    expect(find.byKey(ThemeTransitionHost.wipeOverlayKey), findsNothing);
    expect(_probeColor(tester), AppColors.darkTextPrimary);
  });
}
