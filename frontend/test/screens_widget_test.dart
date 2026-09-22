import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatisaarth/app_widget.dart';
import 'package:gatisaarth/core/router/app_router.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/screens/tabs/home_tab.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/road_anomaly_ticker.dart';

import 'support/fake_location_gateway.dart';
import 'support/load_fonts.dart';
import 'support/session_fakes.dart';

/// A fix inside the bundled Delhi tile coverage, so the map resolves tiles
/// from assets and never touches the network.
const _delhiFix = GnssFix(
  latitude: 28.639,
  longitude: 77.0661,
  altitude: 200,
  accuracy: 5,
  speed: 0,
);

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
  DateTime now = DateTime(2026, 9, 18, 12);
  late final LiveSessionController controller;
}

void _phone(WidgetTester tester, Size logical) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = logical * 2;
  addTearDown(tester.view.reset);
}

Future<void> _pumpApp(WidgetTester tester, _Harness h) async {
  // Straight to the dashboard: the boot sequence has its own test.
  await tester.pumpWidget(GatiSaarthApp(
    session: h.controller,
    initialRoute: AppRoutes.dashboard,
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  h.controller.tick(); // autoTick is off in tests; production ticks at 10 Hz
  await tester.pump();
}

Future<void> _goLive(WidgetTester tester, _Harness h) async {
  h.gateway.fixController.add(_delhiFix);
  await tester.pump();
  h.controller.tick();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump(const Duration(milliseconds: 100)); // apply the scroll
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('GNSS and sensor status follows Edge AI and telemetry',
      (tester) async {
    final h = _Harness();
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);
    final list = tester.widget<ListView>(find
        .descendant(
          of: find.byType(HomeTab),
          matching: find.byType(ListView),
        )
        .first);
    final children =
        (list.childrenDelegate as SliverChildListDelegate).children;
    final heading = children.indexWhere(
      (child) => child is Text && child.data == 'Edge AI & Telemetry',
    );
    final ticker = children.indexWhere(
      (child) => child is RoadAnomalyTicker,
    );
    final status = children.indexWhere(
      (child) => child.toStringShort() == '_SystemStatusCard',
    );
    expect(heading, greaterThanOrEqualTo(0));
    expect(ticker, greaterThan(heading));
    expect(status, greaterThan(ticker));
  });

  for (final size in const [Size(320, 568), Size(360, 740), Size(411, 915)]) {
    testWidgets(
        'dashboard lays out cleanly on ${size.width.toInt()}x'
        '${size.height.toInt()} dp, top to bottom', (tester) async {
      final h = _Harness();
      _phone(tester, size);
      await _pumpApp(tester, h);
      await _goLive(tester, h);

      expect(find.text('GatiSaarth'), findsOneWidget);
      expect(find.text('Nominal GNSS lock'), findsOneWidget);
      await _scrollTo(tester, find.text('GNSS locked'));
      expect(find.text('GNSS locked'), findsWidgets);

      await _scrollTo(tester, find.text('Start fullscreen navigation'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('honest header: no fabricated backend or map-match claims',
      (tester) async {
    final h = _Harness();
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);
    await _goLive(tester, h);

    await _scrollTo(tester, find.text('Standalone · backend offline'));
    expect(find.text('Standalone · backend offline'), findsOneWidget);
    expect(find.textContaining('Map match'), findsNothing);
    expect(find.textContaining('MAP MATCH'), findsNothing);
    expect(find.textContaining('LOCUS'), findsNothing);
  });

  testWidgets('searching state claims no confidence', (tester) async {
    final h = _Harness();
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);

    expect(find.text('Searching for GNSS…'), findsOneWidget);
    expect(find.text('No fix yet'), findsWidgets);
    expect(find.textContaining('--'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('losing GNSS switches the whole UI to dead reckoning',
      (tester) async {
    final h = _Harness();
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);
    await _goLive(tester, h);

    h.now = h.now.add(const Duration(seconds: 7));
    h.controller.tick();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('GNSS signal lost'), findsOneWidget);
    await _scrollTo(tester, find.text('Dead reckoning · inertial'));
    expect(find.text('Dead reckoning · inertial'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('location switched off shows an actionable banner',
      (tester) async {
    final h = _Harness()..gateway.serviceEnabled = false;
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);

    expect(find.text('Location is turned off'), findsOneWidget);
    expect(find.text('Open location settings'), findsOneWidget);
    expect(find.text('Location is off'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked permission shows how to fix it', (tester) async {
    final h = _Harness()..gateway.permission = LocationPermission.deniedForever;
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);

    expect(find.text('Location access is blocked'), findsOneWidget);
    expect(find.text('Open app settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fullscreen navigation opens, renders and exits', (tester) async {
    final h = _Harness();
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);
    await _goLive(tester, h);

    await _scrollTo(tester, find.text('Start fullscreen navigation'));
    await tester.tap(find.text('Start fullscreen navigation'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Live navigation'), findsOneWidget);
    await _scrollTo(tester, find.text('Exit live navigation'));
    expect(find.text('Exit live navigation'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Exit live navigation'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Live navigation'), findsNothing);
  });

  testWidgets('choosing the two-wheeler profile reaches the engine',
      (tester) async {
    final h = _Harness();
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);
    await _goLive(tester, h);

    await _scrollTo(tester, find.text('Two-wheeler'));
    await tester.tap(find.text('Two-wheeler'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.controller.vehicleProfile, VehicleProfile.twoWheeler);
  });

  testWidgets('tunnel scenario button starts a simulated outage',
      (tester) async {
    final h = _Harness();
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);
    await _goLive(tester, h);

    await _scrollTo(tester, find.text('Tunnel test'));
    await tester.tap(find.text('Tunnel test'));
    h.controller.tick();
    await tester.pump(const Duration(seconds: 1));

    expect(h.controller.isSimulatingTunnel, isTrue);
    expect(find.textContaining('Simulating a GNSS blackout'), findsOneWidget);
  });

  testWidgets('reduced motion shows content immediately', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final h = _Harness();
    _phone(tester, const Size(360, 740));
    // Straight to the dashboard: the boot sequence has its own test.
    await tester.pumpWidget(GatiSaarthApp(
      session: h.controller,
      initialRoute: AppRoutes.dashboard,
    ));
    await tester.pump();

    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('GatiSaarth'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1.0);
  });

  testWidgets(
      'backgrounding the app stops sensors and GPS; foregrounding '
      'brings them back', (tester) async {
    final h = _Harness();
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);
    await _goLive(tester, h);
    expect(h.gateway.hasFixListener, isTrue);
    final startsBefore = h.sensors.starts;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(h.gateway.hasFixListener, isFalse);
    expect(h.sensors.stops, greaterThanOrEqualTo(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(h.gateway.hasFixListener, isTrue);
    expect(h.sensors.starts, startsBefore + 1);
  });
}
