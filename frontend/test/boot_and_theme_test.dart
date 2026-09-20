import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatisaarth/app_widget.dart';
import 'package:gatisaarth/core/router/app_router.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/theme/app_theme.dart';
import 'package:gatisaarth/core/theme/theme_controller.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/screens/dashboard_screen.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/dashboard_header.dart';

import 'support/fake_location_gateway.dart';
import 'support/load_fonts.dart';
import 'support/session_fakes.dart';

LiveSessionController _session(FakeLocationGateway gateway) {
  return LiveSessionController(
    sensors: FakeSensors(),
    alignment: VehicleAlignmentEngine(),
    hardware: FakeHardware(),
    speedEstimator: FakeSpeed(),
    telemetry: FakeTelemetry(),
    location: LiveLocationService(
      gateway: gateway,
      errorRetryDelay: Duration.zero,
    ),
    autoTick: false,
  );
}

/// Runs real frames for a moment. `pumpAndSettle` cannot be used on the
/// dashboard: while sensors and a fix are pending it shows a sync spinner.
Future<void> _frames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppColors.isDark = false);

  testWidgets('the header toggle switches the app into dark mode and back',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(411, 915) * 2;
    addTearDown(tester.view.reset);

    final theme = ThemeController();
    await tester.pumpWidget(GatiSaarthApp(
      session: _session(FakeLocationGateway()),
      theme: theme,
      initialRoute: AppRoutes.dashboard,
    ));
    await tester.pump();

    expect(AppColors.isDark, isFalse);
    expect(AppColors.surface, AppColors.lightSurface);

    await tester.tap(find.byType(BrightnessToggle));
    await _frames(tester); // not pumpAndSettle: a sync spinner never settles

    expect(theme.isDark, isTrue);
    expect(AppColors.isDark, isTrue);
    expect(AppColors.surface, AppColors.darkSurface);
    expect(AppColors.textPrimary, AppColors.darkTextPrimary);
    expect(
      Theme.of(tester.element(find.byType(DashboardScreen))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byType(BrightnessToggle));
    await _frames(tester); // not pumpAndSettle: a sync spinner never settles

    expect(theme.isDark, isFalse);
    expect(AppColors.surface, AppColors.lightSurface);
  });

  testWidgets('the brightness toggle leaves the subtitle on one line',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(411, 915) * 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(GatiSaarthApp(
      session: _session(FakeLocationGateway()),
      initialRoute: AppRoutes.dashboard,
    ));
    await tester.pump();

    final subtitle = find.text('Intelligent Navigation Beyond GNSS');
    final para = tester.renderObject<RenderParagraph>(subtitle);
    expect(
      tester.getSize(subtitle).width,
      greaterThanOrEqualTo(para.getMaxIntrinsicWidth(double.infinity)),
      reason: 'the header controls must not squeeze the subtitle onto two lines',
    );
  });

  testWidgets('the chosen brightness survives a restart', (tester) async {
    SharedPreferences.setMockInitialValues({'theme_is_dark': true});
    final restored = await ThemeController.load();
    expect(restored.isDark, isTrue);
    expect(restored.themeMode, ThemeMode.dark);
  });

  testWidgets('dividers follow the app brightness (not the Material default)',
      (tester) async {
    Color rule(ThemeData t) => t.dividerTheme.color!;
    expect(rule(AppTheme.lightTheme), AppColors.lightSurfaceBorder);
    expect(rule(AppTheme.darkTheme), AppColors.darkBorder,
        reason: 'a near-white rule across a dark card was the default');
  });
}
