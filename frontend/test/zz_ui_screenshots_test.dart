import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/app_widget.dart';
import 'package:gatisaarth/core/nav/model/outage_recovery.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/router/app_router.dart';
import 'package:gatisaarth/core/theme/app_theme.dart';
import 'package:gatisaarth/core/theme/theme_controller.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/load_fonts.dart';
import 'support/session_fakes.dart';

/// Local visual check, not a regression gate: renders the main screens at a
/// 360 dp phone in light and dark to PNG files for a human to look at.
///
///     UI_SHOTS=<dir> flutter test test/zz_ui_screenshots_test.dart --update-goldens
void main() {
  final dir = Platform.environment['UI_SHOTS'];
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppColors.isDark = false);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('screens ($mode)', skip: dir == null, (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(360, 780) * 2;
      addTearDown(tester.view.reset);

      var now = DateTime(2026, 9, 24, 9);
      final sensors = FakeSensors();
      final gateway = FakeLocationGateway();
      final controller = LiveSessionController(
        sensors: sensors,
        alignment: VehicleAlignmentEngine(),
        hardware: FakeHardware(),
        speedEstimator: FakeSpeed(),
        telemetry: FakeTelemetry(),
        location: LiveLocationService(
          gateway: gateway,
          clock: () => now,
          errorRetryDelay: Duration.zero,
        ),
        clock: () => now,
        autoTick: false,
      );
      AppColors.isDark = dark;
      await tester.pumpWidget(GatiSaarthApp(
        session: controller,
        theme: ThemeController(isDark: dark),
        initialRoute: AppRoutes.dashboard,
        animateTheme: false,
      ));
      await tester.pump(const Duration(seconds: 2));
      gateway.fixController.add(const GnssFix(
        latitude: 28.6139,
        longitude: 77.2090,
        altitude: 216,
        accuracy: 4,
        speed: 8,
      ));
      for (var i = 0; i < 30; i++) {
        sensors.frames.add([
          0.1, 0.05, 9.81, 0.001, 0.0, 0.002, i * 0.02,
          20.0, 5.0, -40.0, 986.2, 230.0,
        ]);
        now = now.add(const Duration(milliseconds: 20));
      }
      await tester.pump();
      controller.tick();
      await tester.pump(const Duration(seconds: 1));
      controller.outageLog.add(const OutageRecovery(
        durationS: 42,
        distanceM: 610,
        errorM: 18,
        fixAccuracyM: 5,
        endedAtUs: 1,
        coreLed: true,
      ));

      Future<void> shot(String name) async {
        await tester.pump(const Duration(milliseconds: 400));
        final problem = tester.takeException();
        // ignore: avoid_print
        if (problem != null) print('LAYOUT PROBLEM before $name: $problem');
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(Uri.file('$dir/${name}_$mode.png')),
        );
      }

      await shot('1_home');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await shot('1_home_scrolled');
      for (final (i, tab) in ['Map', 'Sensors', 'Profile'].indexed) {
        await tester.tap(find.text(tab).last);
        await tester.pump(const Duration(milliseconds: 400));
        await shot('${i + 2}_${tab.toLowerCase()}');
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await shot('4_profile_scrolled');
      await tester.tap(find.text('Sensors').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await shot('3_sensors_scrolled');

      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.pushNamed(AppRoutes.outageLog);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      await shot('5_outage_log');
      nav.pop();
      nav.pushNamed(AppRoutes.diagnostics);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      await shot('6_diagnostics');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1400));
      await shot('6_diagnostics_scrolled');
      nav.pop();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      controller.dispose();
    });
  }
}
