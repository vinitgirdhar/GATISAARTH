import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/route/planned_route.dart';
import 'package:gatisaarth/core/nav/route/route_tracker.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/place_search.dart';
import 'package:gatisaarth/features/journey/application/journey_service.dart';
import 'package:gatisaarth/features/journey/domain/journey.dart';
import 'package:gatisaarth/features/journey/presentation/place_picker_screen.dart';
import 'package:gatisaarth/features/journey/presentation/route_planner_screen.dart';
import 'package:gatisaarth/features/journey/presentation/widgets/maneuver_banner.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_scope.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/screens/tabs/home_tab.dart';

import 'support/fake_location_gateway.dart';
import 'support/load_fonts.dart';
import 'support/session_fakes.dart';

/// A fake offline place search: hands back a canned list, records queries.
class FakePlaceSearch extends PlaceSearch {
  FakePlaceSearch(super.maps, this.results);

  final List<PlaceResult> results;
  final List<String> queries = [];

  @override
  Future<List<PlaceResult>> search(
    String query, {
    required double nearLat,
    required double nearLon,
    int limit = 20,
  }) async {
    queries.add(query);
    return results;
  }
}

/// A fake journey service: the real one talks to storage, the network and a
/// background isolate. Tests drive the UI against these plain fields instead.
class FakeJourneyService extends JourneyService {
  FakeJourneyService({
    required LiveSessionController session,
    required this.fakePlaces,
  }) : super(maps: OfflineMapService(), session: session);

  final FakePlaceSearch fakePlaces;

  @override
  PlaceSearch get places => fakePlaces;

  JourneyStage _stage = JourneyStage.idle;
  @override
  JourneyStage get stage => _stage;

  Journey? _preview;
  @override
  Journey? get preview => _preview;

  Journey? _active;
  @override
  Journey? get active => _active;

  /// What the next [plan] call resolves to.
  Journey? planResult;
  final List<({JourneyPlace from, JourneyPlace to})> planCalls = [];

  @override
  Future<Journey?> plan({
    required JourneyPlace from,
    required JourneyPlace to,
  }) async {
    planCalls.add((from: from, to: to));
    _preview = planResult;
    _stage = planResult == null ? JourneyStage.failed : JourneyStage.ready;
    notifyListeners();
    return planResult;
  }

  final List<Journey> startCalls = [];
  @override
  Future<void> start(Journey journey) async {
    startCalls.add(journey);
    _active = journey;
    _preview = null;
    notifyListeners();
  }

  int endCalls = 0;
  @override
  Future<void> end() async {
    endCalls++;
    _active = null;
    notifyListeners();
  }

  @override
  void clearPreview() {
    _preview = null;
    notifyListeners();
  }
}

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

PlannedRoute _testRoute() => PlannedRoute(
      polyline: const [28.600, 77.200, 28.610, 77.210, 28.620, 77.220],
      maneuvers: const [
        RouteManeuver(kind: ManeuverKind.depart, atM: 0, lat: 28.600, lon: 77.200),
        RouteManeuver(
          kind: ManeuverKind.left,
          atM: 700,
          lat: 28.610,
          lon: 77.210,
          roadName: 'MG Road',
        ),
        RouteManeuver(kind: ManeuverKind.arrive, atM: 1500, lat: 28.620, lon: 77.220),
      ],
      durationS: 300,
    );

/// Wraps [child] the way the real app wraps its whole Navigator (in
/// `app_widget.dart`) — the scopes must sit above `MaterialApp` so every
/// pushed route can still see them, not just the first one.
Widget _wrap(_Harness h, FakeJourneyService journey, Widget child) {
  return LiveSessionScope(
    controller: h.controller,
    child: JourneyScope(
      service: journey,
      child: MaterialApp(home: child),
    ),
  );
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Home shows the Where-to card and opens the planner',
      (tester) async {
    final h = _Harness();
    final journey = FakeJourneyService(
      session: h.controller,
      fakePlaces: FakePlaceSearch(OfflineMapService(), const []),
    );

    await tester.pumpWidget(_wrap(
      h,
      journey,
      Scaffold(body: HomeTab(onNavigateToTab: (_) {})),
    ));
    await tester.pump();

    expect(find.text('From · Your location'), findsOneWidget);
    expect(find.textContaining('Choose destination'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('where-to-card')));
    await tester.pumpAndSettle();

    expect(find.byType(RoutePlannerScreen), findsOneWidget);
    expect(find.text('Plan a journey'), findsOneWidget);
  });

  testWidgets(
      'Planner shows offline search results and the choose-on-map option',
      (tester) async {
    final h = _Harness();
    final journey = FakeJourneyService(
      session: h.controller,
      fakePlaces: FakePlaceSearch(OfflineMapService(), const [
        PlaceResult(
          name: 'Connaught Place',
          kind: 'locality',
          lat: 28.62,
          lon: 77.22,
          distanceM: 1200,
        ),
      ]),
    );

    await tester.pumpWidget(
        _wrap(h, journey, const RoutePlannerScreen(focusTo: true)));
    await tester.pump(); // postFrameCallback focuses the To field

    expect(find.text('Choose on map'), findsOneWidget);
    expect(find.text('Your location'), findsWidgets);

    await tester.enterText(
        find.byKey(const ValueKey('journey-to-field')), 'Connaught');
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();

    expect(journey.fakePlaces.queries, contains('Connaught'));
    expect(find.text('Connaught Place'), findsOneWidget);
  });

  testWidgets('Choose on map returns a dropped-pin place', (tester) async {
    final h = _Harness();
    final journey = FakeJourneyService(
      session: h.controller,
      fakePlaces: FakePlaceSearch(OfflineMapService(), const []),
    );

    await tester.pumpWidget(
        _wrap(h, journey, const RoutePlannerScreen(focusTo: true)));
    await tester.pump();

    await tester.tap(find.text('Choose on map'));
    await tester.pumpAndSettle();

    expect(find.byType(PlacePickerScreen), findsOneWidget);
    expect(find.text('Set destination'), findsOneWidget);

    await tester.tap(find.text('Set destination'));
    await tester.pumpAndSettle();

    expect(find.byType(PlacePickerScreen), findsNothing);
    expect(find.text('Dropped pin'), findsOneWidget);
  });

  testWidgets(
      'Planning to a destination and starting activates the journey and '
      'switches Home to the Map tab', (tester) async {
    final h = _Harness();
    final preview = Journey(
      from: const JourneyPlace(
          name: 'Your location', lat: 0, lon: 0, isCurrentLocation: true),
      to: const JourneyPlace(name: 'Connaught Place', lat: 28.62, lon: 77.22),
      route: _testRoute(),
      createdAt: DateTime(2026, 1, 1),
    );
    final journey = FakeJourneyService(
      session: h.controller,
      fakePlaces: FakePlaceSearch(OfflineMapService(), const [
        PlaceResult(
          name: 'Connaught Place',
          kind: 'locality',
          lat: 28.62,
          lon: 77.22,
          distanceM: 1200,
        ),
      ]),
    )..planResult = preview;

    final navigated = <int>[];
    await tester.pumpWidget(_wrap(
      h,
      journey,
      Scaffold(body: HomeTab(onNavigateToTab: navigated.add)),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('where-to-card')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('journey-to-field')), 'Connaught');
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();

    await tester.tap(find.text('Connaught Place'));
    await tester.pump();

    expect(journey.planCalls, hasLength(1));
    expect(journey.planCalls.single.to.name, 'Connaught Place');

    // The plan succeeded: the preview summary and Start are on screen.
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('ETA'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Saved for offline use'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(journey.startCalls, hasLength(1));
    expect(navigated, contains(1));

    // Back on Home: the active-journey card, not the planner card.
    expect(find.byType(RoutePlannerScreen), findsNothing);
    expect(find.text('Connaught Place'), findsOneWidget);
    expect(find.text('Resume navigation'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);

    await tester.tap(find.text('End'));
    await tester.pump();
    expect(journey.endCalls, 1);
  });

  testWidgets(
      'ManeuverBanner shows the next instruction, distance and GPS-lost '
      'status', (tester) async {
    const progress = RouteProgress(
      alongM: 400,
      remainingM: 1100,
      remainingS: 180,
      arrived: false,
      next: RouteManeuver(
        kind: ManeuverKind.left,
        atM: 700,
        lat: 28.61,
        lon: 77.21,
        roadName: 'MG Road',
      ),
      distanceToNextM: 300,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ManeuverBanner(progress: progress, isRouteLocked: true),
      ),
    ));
    await tester.pump();

    expect(find.text('300 m'), findsOneWidget);
    expect(find.text('Turn left onto MG Road'), findsOneWidget);
    expect(find.text('GPS lost · following the saved route'), findsOneWidget);
  });

  testWidgets('ManeuverBanner reports rerouting over other statuses',
      (tester) async {
    const progress = RouteProgress(
      alongM: 0,
      remainingM: 1500,
      remainingS: 300,
      arrived: false,
      next: RouteManeuver(kind: ManeuverKind.depart, atM: 0, lat: 0, lon: 0),
      distanceToNextM: 50,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ManeuverBanner(
          progress: progress,
          isRouteLocked: true,
          isRerouting: true,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Rerouting…'), findsOneWidget);
    expect(find.text('GPS lost · following the saved route'), findsNothing);
  });
}
