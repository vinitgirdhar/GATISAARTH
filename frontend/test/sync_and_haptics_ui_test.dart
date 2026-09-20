import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatisaarth/app_widget.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/router/app_router.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';

import 'support/fake_location_gateway.dart';
import 'support/load_fonts.dart';
import 'support/session_fakes.dart';

const _delhiFix = GnssFix(
  latitude: 28.639,
  longitude: 77.0661,
  altitude: 200,
  accuracy: 5,
  speed: 0,
);

/// Frame layout: [ax, ay, az, gx, gy, gz, t, mx, my, mz, pressure, altitude].
List<double> _frame(double t) =>
    [0, 0, 9.81, 0, 0, 0, t, 0, 30, 0, double.nan, double.nan];

class _Harness {
  _Harness() {
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
  }

  final sensors = FakeSensors();
  final gateway = FakeLocationGateway();
  DateTime now = DateTime(2026, 9, 20, 12);
  late final LiveSessionController controller;
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(411, 915) * 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(GatiSaarthApp(
    session: h.controller,
    initialRoute: AppRoutes.dashboard,
  ));
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the capsule follows a real start-up and ends on Synced',
      (tester) async {
    final h = _Harness();
    h.gateway.permission = LocationPermission.whileInUse;
    await _pump(tester, h);
    h.controller.tick();
    await tester.pump(const Duration(milliseconds: 800));

    // Nothing has arrived yet: no sensor frame, no fix.
    expect(find.textContaining('Syncing'), findsOneWidget);
    expect(find.textContaining('Starting sensors'), findsOneWidget);

    h.sensors.frames.add(_frame(1));
    await tester.pump();
    h.controller.tick();
    await tester.pump();
    expect(find.textContaining('Finding satellites'), findsOneWidget);

    h.gateway.fixController.add(_delhiFix);
    await tester.pump();
    h.controller.tick();
    await tester.pump();
    expect(find.text('Synced'), findsOneWidget);
    expect(find.textContaining('Syncing'), findsNothing);

    // It holds "Synced" for a moment, then slides away. Real frames, not one
    // big jump: the slide-out needs frames to run.
    for (var i = 0; i < 26; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Synced'), findsNothing);
  });

  testWidgets('the Haptic alerts switch is on by default and turns it all off',
      (tester) async {
    final h = _Harness();
    await _pump(tester, h);
    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.scrollUntilVisible(
      find.text('Haptic alerts'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final tileRow = find.ancestor(
      of: find.text('Haptic alerts'),
      matching: find.byType(Row),
    ).first;
    final toggle = find.descendant(of: tileRow, matching: find.byType(Switch));
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(h.controller.hapticsEnabled, isTrue);

    await tester.tap(toggle);
    await tester.pump();
    expect(h.controller.hapticsEnabled, isFalse);
    expect(tester.widget<Switch>(toggle).value, isFalse);
  });
}
