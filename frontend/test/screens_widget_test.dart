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
import 'package:gatisaarth/features/navigation_ui/presentation/screens/tabs/map_tab.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/engine_status_card.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/mission_guidance_card.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/nav_safety_badge.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/navigation_map.dart';

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

Future<void> _finishUiMotion(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Map leads, status floats, and controls follow speed',
      (tester) async {
    final h = _Harness();
    _phone(tester, const Size(411, 915));
    await _pumpApp(tester, h);
    await _goLive(tester, h);
    await tester.tap(find.text('Map').last);
    await _finishUiMotion(tester);

    expect(find.byType(MapTab), findsOneWidget);
    expect(find.byType(EngineStatusCard), findsNothing);
    expect(find.text('Record drive'), findsOneWidget);
    expect(find.byTooltip('Simulation Lab'), findsOneWidget);
    expect(find.text('Simulate GNSS loss'), findsNothing);
    final mapTop = tester.getTopLeft(find.byType(NavigationMap)).dy;
    final mapBottom = tester.getBottomLeft(find.byType(NavigationMap)).dy;
    final statusTop = tester.getTopLeft(find.byType(NavSafetyBadge)).dy;
    final simulationTop = tester.getTopLeft(find.text('Simulation Lab')).dy;
    final speedTop = tester.getTopLeft(find.text('SPEED')).dy;
    final recordTop = tester.getTopLeft(find.text('Record drive')).dy;
    expect(statusTop, greaterThan(mapTop));
    expect(statusTop, lessThan(mapBottom));
    expect(simulationTop, greaterThan(mapTop));
    expect(speedTop, greaterThan(simulationTop));
    expect(recordTop, greaterThan(speedTop));

    await tester.tap(find.text('Sensors').last);
    await _finishUiMotion(tester);
    expect(find.byType(EngineStatusCard), findsNothing);
  });

  testWidgets('simulation action stays compact and reflects the active test',
      (tester) async {
    final h = _Harness();
    _phone(tester, const Size(411, 915));
    await _pumpApp(tester, h);
    await tester.tap(find.text('Map').last);
    await _finishUiMotion(tester);
    expect(find.byType(EngineStatusCard), findsNothing);
    expect(find.text('Record drive'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-simulation-tools')));
    await _finishUiMotion(tester);
    expect(find.text('Tunnel test'), findsWidgets);
    await tester.tap(find.text('Tunnel test').last);
    await _finishUiMotion(tester);
    expect(find.text('End test'), findsOneWidget);

    h.controller.resetSimulation();
    await _finishUiMotion(tester);
    expect(find.text('Simulation Lab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(360, 740)]) {
    testWidgets('Map remains usable at ${size.width}x${size.height} dp',
        (tester) async {
      final h = _Harness();
      _phone(tester, size);
      await _pumpApp(tester, h);
      await tester.tap(find.text('Map').last);
      await _finishUiMotion(tester);
      expect(find.byType(NavigationMap), findsOneWidget);
      expect(
          tester
              .getSize(
                find.descendant(
                  of: find.byType(MapTab),
                  matching: find.byType(NavigationMap),
                ),
              )
              .height,
          greaterThan(80));
      expect(tester.takeException(), isNull);
      h.controller.startTunnelTest();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      if (find.byType(MissionGuidanceCard).evaluate().isNotEmpty) {
        final mapTop = tester.getTopLeft(find.byType(NavigationMap)).dy;
        final mapBottom = tester.getBottomLeft(find.byType(NavigationMap)).dy;
        expect(
          tester.getTopLeft(find.byType(MissionGuidanceCard)).dy,
          greaterThan(mapTop),
        );
        expect(
          tester.getBottomLeft(find.byType(MissionGuidanceCard)).dy,
          lessThan(mapBottom),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home presents current position and live drive metrics',
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
    final position = children.indexWhere(
      (child) => child.toStringShort() == '_NavigationOverview',
    );
    final glance = children.indexWhere(
      (child) => child is Text && child.data == 'At a glance',
    );
    final snapshot = children.indexWhere(
      (child) => child.toStringShort() == '_DriveSnapshot',
    );
    expect(position, greaterThanOrEqualTo(0));
    expect(glance, greaterThan(position));
    expect(snapshot, greaterThan(glance));
  });

  for (final size in const [Size(320, 568), Size(360, 740), Size(411, 915)]) {
    testWidgets(
        'dashboard lays out cleanly on ${size.width.toInt()}x'
        '${size.height.toInt()} dp, top to bottom', (tester) async {
      final h = _Harness();
      _phone(tester, size);
      await _pumpApp(tester, h);
      await _goLive(tester, h);

      expect(find.byType(HomeTab), findsOneWidget);
      expect(find.text('Location is ready'), findsOneWidget);
      expect(find.text('At a glance'), findsOneWidget);

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

    expect(find.byType(HomeTab), findsOneWidget);
    expect(find.textContaining('Backend'), findsNothing);
    expect(find.textContaining('Map match'), findsNothing);
    expect(find.textContaining('MAP MATCH'), findsNothing);
    expect(find.textContaining('LOCUS'), findsNothing);
  });

  testWidgets('searching state claims no confidence', (tester) async {
    final h = _Harness();
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);

    expect(find.text('Finding your location'), findsOneWidget);
    expect(find.text('Waiting for a fresh GPS fix'), findsOneWidget);
    // Speed and accuracy are unknown until a live fix arrives.
    expect(find.text('—', findRichText: true), findsWidgets);
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

    expect(find.text('Satellite signal lost'), findsOneWidget);
    await tester.tap(find.text('Map').last);
    await _finishUiMotion(tester);
    expect(find.text('Dead reckoning'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('location switched off shows an actionable banner',
      (tester) async {
    final h = _Harness()..gateway.serviceEnabled = false;
    _phone(tester, const Size(360, 740));
    await _pumpApp(tester, h);

    expect(find.text('Location is turned off'), findsOneWidget);
    expect(find.text('Live position paused'), findsOneWidget);
    expect(find.text('Open location settings'), findsOneWidget);
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

    await tester.tap(find.text('Map').last);
    await _finishUiMotion(tester);
    await tester.tap(find.byKey(const ValueKey('map-simulation-tools')));
    await _finishUiMotion(tester);
    await tester.tap(find.text('Tunnel test').last);
    h.controller.tick();
    await tester.pump(const Duration(seconds: 1));

    expect(h.controller.isSimulatingTunnel, isTrue);
    expect(find.text('End test'), findsOneWidget);
    expect(find.byType(MissionGuidanceCard), findsOneWidget);
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

    await tester.tap(find.text('Map').last);
    await tester.pump();
    expect(find.byType(MapTab), findsOneWidget);
    expect(find.byType(NavigationMap), findsOneWidget);
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
