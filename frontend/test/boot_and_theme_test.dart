import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatisaarth/app_widget.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/theme/app_theme.dart';
import 'package:gatisaarth/core/theme/theme_controller.dart';
import 'package:gatisaarth/features/boot/presentation/boot_screen.dart';
import 'package:gatisaarth/features/boot/presentation/boot_sequence.dart';
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

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppColors.isDark = false);

  testWidgets('boot screen shows the brand frame, then hands over to the '
      'dashboard once start-up work has run', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(411, 915) * 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(GatiSaarthApp(session: _session(FakeLocationGateway())));
    await tester.pump();

    expect(find.byType(BootScreen), findsOneWidget);
    // The first stage is real work, not a countdown.
    expect(find.textContaining(BootSequence.stages.first.label), findsOneWidget);

    // Long enough for every stage to finish or exhaust its budget. Each poll
    // schedules the next one, so the clock has to be advanced in steps.
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(DashboardScreen).evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();

    expect(find.byType(BootScreen), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  test('boot progress only advances with completed stages', () {
    final gateway = FakeLocationGateway();
    final boot = BootSequence(session: _session(gateway));
    expect(boot.progress, 0);
    expect(boot.isFinished, isFalse);
    expect(boot.label, BootSequence.stages.first.label);
    boot.dispose();
  });

  testWidgets('the header toggle switches the app into dark mode and back',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(411, 915) * 2;
    addTearDown(tester.view.reset);

    final theme = ThemeController();
    await tester.pumpWidget(GatiSaarthApp(
      session: _session(FakeLocationGateway()),
      theme: theme,
      initialRoute: '/',
    ));
    await tester.pump();

    expect(AppColors.isDark, isFalse);
    expect(AppColors.surface, AppColors.lightSurface);

    await tester.tap(find.byType(BrightnessToggle));
    await tester.pumpAndSettle();

    expect(theme.isDark, isTrue);
    expect(AppColors.isDark, isTrue);
    expect(AppColors.surface, AppColors.darkSurface);
    expect(AppColors.textPrimary, AppColors.darkTextPrimary);
    expect(
      Theme.of(tester.element(find.byType(DashboardScreen))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byType(BrightnessToggle));
    await tester.pumpAndSettle();

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
      initialRoute: '/',
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
}
