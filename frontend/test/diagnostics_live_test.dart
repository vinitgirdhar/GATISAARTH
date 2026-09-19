import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/navigation_engine/presentation/screens/diagnostics_screen.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/load_fonts.dart';
import 'support/session_fakes.dart';

/// §64 asked for the diagnostics screen to become functional. It was demo data
/// from top to bottom; these tests pin that it is now live, and that the one
/// panel which is still demonstration data still says so.
void main() {
  setUpAll(loadAppFonts);

  late FakeSensors sensors;
  late FakeLocationGateway gateway;
  late LiveSessionController controller;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sensors = FakeSensors();
    gateway = FakeLocationGateway();
    now = DateTime(2026, 9, 19, 12);
    controller = LiveSessionController(
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
  });

  tearDown(() => controller.dispose());

  /// A tall viewport for content assertions: the screen is a lazy `ListView`,
  /// so a panel below the fold is simply not built and `find` cannot see it.
  /// The narrow sizes are used for the layout checks instead.
  Future<void> pump(WidgetTester tester,
      {Size size = const Size(360, 3000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LiveSessionScope(
        controller: controller,
        child: const MaterialApp(home: DiagnosticsScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders live sections, not a demo dashboard', (tester) async {
    await controller.start();
    await pump(tester);

    expect(find.text('Navigation core'), findsOneWidget);
    expect(find.textContaining('Uncertainty'), findsOneWidget);
    expect(find.text('GNSS'), findsOneWidget);
    expect(find.text('Vehicle state'), findsOneWidget);
    expect(find.text('Why this position?'), findsOneWidget);
    expect(find.textContaining('Performance'), findsOneWidget);
  });

  testWidgets('shows -- for what the phone has not produced', (tester) async {
    await controller.start();
    await pump(tester);

    // No samples yet, so no rate, no covariance, no calibration. None of it
    // may be dressed up as a number.
    expect(find.textContaining('--'), findsWidgets);
    expect(find.text('Leading the position'), findsOneWidget);
    expect(find.text('No'), findsWidgets);
  });

  testWidgets('never claims satellites it cannot see', (tester) async {
    await controller.start();
    await pump(tester);

    expect(
      find.textContaining('GnssStatus not wired'),
      findsOneWidget,
    );
    expect(
      find.textContaining('illustrative demo data'),
      findsOneWidget,
    );
  });

  testWidgets('reports the neural model and map honestly', (tester) async {
    await controller.start();
    sensors.frames.add(
        [0, 0, 9.81, 0, 0, 0, 100, 0, 30, 0, double.nan, double.nan]);
    await tester.pump();
    await pump(tester);

    expect(find.text('Neural velocity'), findsOneWidget);
    expect(find.text('Map matching'), findsOneWidget);
    // Neither exists, and neither pretends to.
    expect(find.textContaining('No road graph'), findsWidgets);
  });

  testWidgets('lays out without overflow at 320 dp', (tester) async {
    await controller.start();
    await pump(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out without overflow at 411 dp', (tester) async {
    await controller.start();
    await pump(tester, size: const Size(411, 915));
    expect(tester.takeException(), isNull);
  });
}
