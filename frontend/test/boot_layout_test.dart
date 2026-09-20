import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatisaarth/app_widget.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/boot/presentation/boot_screen.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/screens/dashboard_screen.dart';

import 'support/fake_location_gateway.dart';
import 'support/load_fonts.dart';
import 'support/session_fakes.dart';

LiveSessionController _session() {
  return LiveSessionController(
    sensors: FakeSensors(),
    alignment: VehicleAlignmentEngine(),
    hardware: FakeHardware(),
    speedEstimator: FakeSpeed(),
    telemetry: FakeTelemetry(),
    location: LiveLocationService(
      gateway: FakeLocationGateway(),
      errorRetryDelay: Duration.zero,
    ),
    autoTick: false,
  );
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // A RenderFlex overflow is a thrown FlutterError, so simply laying the
  // screen out at the smallest phone we support is the assertion.
  for (final size in const [Size(320, 568), Size(360, 740), Size(411, 915)]) {
    testWidgets('boot screen lays out on ${size.width.toInt()}x'
        '${size.height.toInt()} dp and transitions to dashboard', (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = size * 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(GatiSaarthApp(session: _session()));
      await tester.pump();

      expect(find.byType(BootScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Advance past the 1400ms animation duration + 300ms transition
      await tester.pump(const Duration(milliseconds: 1500));
      // Bounded, not pumpAndSettle: the dashboard shows a sync spinner until
      // sensors and a fix arrive, and a loading spinner never "settles".
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(DashboardScreen), findsOneWidget);
    });
  }
}
