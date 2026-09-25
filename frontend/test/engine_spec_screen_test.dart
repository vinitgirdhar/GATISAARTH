import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/router/app_router.dart';
import 'package:gatisaarth/core/theme/app_theme.dart';
import 'package:gatisaarth/core/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';
import 'support/fake_map_packs.dart';
import 'support/load_fonts.dart';

/// The model card reads two asset files, which is real file I/O: give it a
/// moment outside the fake clock, then draw.
Future<void> _loadAssets(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)));
  await frames(tester, count: 5);
}

/// Opens the Profile tab of the dashboard.
Future<void> _openProfile(WidgetTester tester) async {
  await tester.tap(find.text('Profile'));
  await frames(tester, count: 6);
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppColors.isDark = false);

  group('the engine page', () {
    testWidgets('lists what the app is and how it works', (tester) async {
      final h = AppHarness();
      await h.pumpApp(tester,
          route: AppRoutes.engine, size: const Size(411, 4200));
      await _loadAssets(tester);

      expect(find.text('Navigation engine'), findsOneWidget, reason: 'title');
      expect(find.text('GatiSaarth Navigation Engine'), findsOneWidget);
      expect(find.text('v4.5.0 (build 47)'), findsOneWidget);
      for (final section in [
        'Right now',
        'How it works',
        'Specifications',
        'Motion model (edge AI)',
        'Maps',
        'Privacy and data',
        'Known limits',
        'This phone',
      ]) {
        expect(find.text(section), findsOneWidget, reason: section);
      }
      for (final step in ['Sense', 'Align', 'Fuse', 'Constrain', 'Carry on']) {
        expect(find.text(step), findsOneWidget, reason: step);
      }
      expect(find.text('15-state error-state Kalman filter'), findsOneWidget);
    });

    testWidgets('its numbers come from the code, not from prose',
        (tester) async {
      final h = AppHarness();
      await h.pumpApp(tester,
          route: AppRoutes.engine, size: const Size(411, 4200));
      await _loadAssets(tester);

      expect(find.textContaining('Up to 100 Hz'), findsOneWidget);
      expect(find.textContaining('10 Hz to the screen'), findsOneWidget);
      expect(find.textContaining('newer than 6 s'), findsOneWidget);
      expect(find.textContaining('at least 0.5 m/s'), findsOneWidget);
      expect(find.textContaining('20 straight accelerate'), findsOneWidget);
    });

    testWidgets('the model card says what the model is for', (tester) async {
      final h = AppHarness();
      await h.pumpApp(tester,
          route: AppRoutes.engine, size: const Size(411, 4200));
      await _loadAssets(tester);

      expect(find.text('Motion model (edge AI)'), findsOneWidget);
      expect(find.textContaining('temporal convolutions (TCN)'), findsOneWidget);
      expect(find.textContaining('Advisory'), findsOneWidget);
      expect(find.textContaining('never sets speed or position'),
          findsOneWidget);
    });

    testWidgets('it does not claim accuracy it has not measured',
        (tester) async {
      final h = AppHarness();
      await h.pumpApp(tester,
          route: AppRoutes.engine, size: const Size(411, 4200));
      await _loadAssets(tester);

      expect(find.textContaining('simulated drive'), findsOneWidget);
      expect(find.textContaining('not lane level'), findsOneWidget);
      expect(find.textContaining('no account'), findsOneWidget);
    });

    testWidgets('the live card reflects the session', (tester) async {
      final h = AppHarness();
      await h.pumpApp(tester,
          route: AppRoutes.engine, size: const Size(411, 4200));
      await _loadAssets(tester);
      expect(find.text('Sensors'), findsOneWidget);
      expect(find.text('Idle'), findsOneWidget, reason: 'no samples yet');
      expect(find.text('Fallback pipeline'), findsOneWidget,
          reason: 'the core is not leading yet');
    });

    testWidgets('the maps card shows what is installed and links to them',
        (tester) async {
      mockPathProvider();
      final maps = await allPacksInstalled();
      final h = AppHarness();
      await h.pumpApp(tester,
          route: AppRoutes.engine, maps: maps, size: const Size(411, 4200));
      await _loadAssets(tester);

      expect(find.text('Ready offline'), findsNWidgets(2));
      await tester.ensureVisible(find.text('Manage offline maps'));
      await tester.tap(find.text('Manage offline maps'));
      await frames(tester, count: 15);
      expect(find.text('Offline maps'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('Profile', () {
    testWidgets('the Navigation Engine row opens the specifications',
        (tester) async {
      final h = AppHarness();
      await h.pumpApp(tester);
      await _openProfile(tester);

      final tile = find.text('GatiSaarth Navigation Engine');
      await tester.scrollUntilVisible(tile, 200,
          scrollable: find.byType(Scrollable).first);
      // Built is not the same as reachable: it may sit under the tab bar.
      await tester.ensureVisible(tile);
      await frames(tester, count: 3);
      await tester.tap(tile);
      await frames(tester, count: 15);

      expect(find.text('Navigation engine'), findsOneWidget);
      expect(find.text('How it works'), findsOneWidget);
    });

    testWidgets('the Offline Maps row opens the offline maps',
        (tester) async {
      final h = AppHarness();
      await h.pumpApp(tester, maps: await noPacksInstalled());
      await _openProfile(tester);

      final tile = find.text('Offline Maps');
      await tester.scrollUntilVisible(tile, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(tile);
      await frames(tester, count: 3);
      await tester.tap(tile);
      await frames(tester, count: 15);
      expect(find.text('Offline maps'), findsOneWidget);
      expect(find.text('Delhi NCR'), findsWidgets);
    });

    testWidgets('Privacy & Architecture is readable in dark mode, and back',
        (tester) async {
      final theme = ThemeController();
      final h = AppHarness();
      await h.pumpApp(tester, theme: theme);
      await _openProfile(tester);

      Color titleColor() => tester
          .widget<Text>(find.text('Privacy & Architecture'))
          .style!
          .color!;
      Color subtitleColor() => tester
          .widget<Text>(find.text('100% on-device pure Dart dead reckoning'))
          .style!
          .color!;

      final tile = find.text('Privacy & Architecture');
      await tester.scrollUntilVisible(tile, 200,
          scrollable: find.byType(Scrollable).first);
      expect(titleColor(), AppColors.lightTextPrimary);

      // The bug: this tile is `const`, so it was never rebuilt and kept its
      // light-mode colours - near-black text on a near-black card.
      await theme.toggle();
      await frames(tester, count: 6);
      expect(theme.isDark, isTrue);
      expect(titleColor(), AppColors.darkTextPrimary);
      expect(subtitleColor(), AppColors.darkTextSecondary);
      expect(AppColors.surface, AppColors.darkSurface);

      await theme.toggle();
      await frames(tester, count: 6);
      expect(titleColor(), AppColors.lightTextPrimary);
      expect(subtitleColor(), AppColors.lightTextSecondary);
    });

    testWidgets('the whole theme change is animated when animation is on',
        (tester) async {
      final theme = ThemeController();
      final h = AppHarness();
      await h.pumpApp(tester, theme: theme, animateTheme: true);
      await _openProfile(tester);

      final flip = theme.toggle();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await flip;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(theme.isDark, isTrue);
      // Mid-wipe the new brightness is already live underneath.
      expect(AppColors.surface, AppColors.darkSurface);

      await frames(tester, count: 12, ms: 60);
    });
  });
}
