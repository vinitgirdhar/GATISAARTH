import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/map/tile_roads.dart' show TileRoadLine;
import 'package:gatisaarth/core/nav/nav_config.dart' show RouteConfig;
import 'package:gatisaarth/core/nav/route/planned_route.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_reader.dart';
import 'package:gatisaarth/features/journey/application/journey_service.dart';
import 'package:gatisaarth/features/journey/domain/journey.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';

import 'support/app_harness.dart' show FakeInstaller;
import 'support/fake_location_gateway.dart';
import 'support/fake_map_packs.dart';
import 'support/session_fakes.dart';

/// A [LiveSessionController] whose position, GNSS and route hooks are plain
/// fields: `startRoute`/`endRoute` are stubs on the real controller (another
/// agent's contract to fill in), so route-related assertions here are made
/// against this spy rather than against real dead-reckoning state.
class _SpySession extends LiveSessionController {
  _SpySession()
      : super(
          sensors: FakeSensors(),
          alignment: VehicleAlignmentEngine(),
          hardware: FakeHardware(),
          speedEstimator: FakeSpeed(),
          telemetry: FakeTelemetry(),
          location: LiveLocationService(
            gateway: FakeLocationGateway(),
            clock: DateTime.now,
            errorRetryDelay: Duration.zero,
          ),
          autoTick: false,
          haptics: Haptics(FakeHardware(), pause: (_) async {}),
        );

  double fakeLat = 0;
  double fakeLon = 0;
  bool fakeOffRoute = false;
  bool fakeLiveGnss = false;
  final List<PlannedRoute> startedRoutes = [];
  int endCalls = 0;

  @override
  double get latitude => fakeLat;
  @override
  double get longitude => fakeLon;
  @override
  bool get isOffRoute => fakeOffRoute;
  @override
  bool get hasLiveGnss => fakeLiveGnss;
  @override
  void startRoute(PlannedRoute route) => startedRoutes.add(route);
  @override
  void endRoute() => endCalls++;

  /// Fires the change notification `JourneyService` listens for.
  void poke() => notifyListeners();
}

/// Finds a pack's archive by file name inside [dir], the way the real
/// Android locator finds any `<id>.pmtiles` under `offline_maps` regardless
/// of the static catalogue - so a corridor pack just downloaded there is
/// found on the next scan.
class _DirLocator implements MapPackLocator {
  _DirLocator(this.dir);
  final Directory dir;

  @override
  Future<PackLocation?> locate(String fileName) async {
    final file = File('${dir.path}/$fileName');
    if (!file.existsSync()) return null;
    return PackLocation(
      path: file.path,
      offset: 0,
      length: file.lengthSync(),
      origin: PackOrigin.downloaded,
    );
  }
}

PlannedRoute _route(double fromLat, double fromLon, double toLat, double toLon) =>
    PlannedRoute(
      polyline: [fromLat, fromLon, toLat, toLon],
      maneuvers: [
        RouteManeuver(kind: ManeuverKind.depart, atM: 0, lat: fromLat, lon: fromLon),
        RouteManeuver(kind: ManeuverKind.arrive, atM: 100, lat: toLat, lon: toLon),
      ],
      durationS: 60,
    );

/// A [JourneyPlannerFn] that ignores the road graph and just returns a
/// straight line between the requested endpoints - tests do not depend on
/// the other agent's real `planRoute`.
PlannedRoute? Function(
  RoadGraph graph, {
  required double fromLat,
  required double fromLon,
  required double toLat,
  required double toLon,
  VehicleAccess vehicle,
  RouteConfig config,
}) _fakePlanner({bool returnsNull = false}) {
  return (
    graph, {
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    VehicleAccess vehicle = VehicleAccess.cars,
    RouteConfig config = const RouteConfig(),
  }) {
    if (returnsNull) return null;
    return _route(fromLat, fromLon, toLat, toLon);
  };
}

/// A [CorridorLinesReader] that hands back one plausible road line, so
/// `buildRoadGraph` succeeds without a real archive.
CorridorLinesReader _fakeLines({String packId = 'test-pack'}) {
  return ({
    required double south,
    required double west,
    required double north,
    required double east,
    int maxTiles = 250,
  }) async {
    return (
      lines: [
        TileRoadLine(latLon: [south, west, north, east]),
      ],
      packId: packId,
    );
  };
}

Future<OfflineMapService> _mapsWithPack(OfflinePack pack) async {
  final service = OfflineMapService(
    locator: FakeMapPackLocator({pack.fileName: fakeLocation(pack.approxBytes)}),
    opener: (l, p) async => EmptyTileProvider(maxZoom: p.maxZoom),
    catalog: [pack],
  );
  await service.load();
  return service;
}

const _wideBandraPack = OfflinePack(
  id: 'wide',
  name: 'wide',
  south: 19.0,
  west: 72.7,
  north: 19.2,
  east: 73.0,
  maxZoom: 15,
  approxBytes: 1,
);

const _from = JourneyPlace(name: 'A', lat: 19.05, lon: 72.83);
const _to = JourneyPlace(name: 'B', lat: 19.10, lon: 72.90);

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('journey_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('JourneyService.plan', () {
    test('a covered corridor plans without downloading and saves a preview',
        () async {
      final maps = await _mapsWithPack(_wideBandraPack);
      final installer = FakeInstaller(Directory('${tmp.path}/maps'));
      final session = _SpySession();
      final service = JourneyService(
        maps: maps,
        session: session,
        installer: installer,
        folder: () async => Directory('${tmp.path}/journeys'),
        isOnline: () async => false,
        planner: _fakePlanner(),
        linesInBox: _fakeLines(),
      );
      addTearDown(service.dispose);

      final journey = await service.plan(from: _from, to: _to);

      expect(journey, isNotNull);
      expect(service.stage, JourneyStage.ready);
      expect(service.preview, journey);
      expect(service.error, isNull);
      expect(installer.started, isEmpty);
      expect(File('${tmp.path}/journeys/preview.json').existsSync(), isTrue);
    });

    test('start persists the journey as active and starts the route',
        () async {
      final maps = await _mapsWithPack(_wideBandraPack);
      final session = _SpySession();
      final service = JourneyService(
        maps: maps,
        session: session,
        folder: () async => Directory('${tmp.path}/journeys'),
        planner: _fakePlanner(),
        linesInBox: _fakeLines(),
      );
      addTearDown(service.dispose);

      final journey = await service.plan(from: _from, to: _to);
      await service.start(journey!);

      expect(service.active, journey);
      expect(service.preview, isNull);
      expect(session.startedRoutes, [journey.route]);
      expect(File('${tmp.path}/journeys/active.json').existsSync(), isTrue);
    });

    test('end clears the active journey and ends the route', () async {
      final maps = await _mapsWithPack(_wideBandraPack);
      final session = _SpySession();
      final service = JourneyService(
        maps: maps,
        session: session,
        folder: () async => Directory('${tmp.path}/journeys'),
        planner: _fakePlanner(),
        linesInBox: _fakeLines(),
      );
      addTearDown(service.dispose);
      final journey = await service.plan(from: _from, to: _to);
      await service.start(journey!);

      await service.end();

      expect(service.active, isNull);
      expect(session.endCalls, 1);
      expect(File('${tmp.path}/journeys/active.json').existsSync(), isFalse);
    });

    test('an unresolved "Your location" fails clearly', () async {
      final service = JourneyService(
        maps: await noPacksInstalled(),
        session: _SpySession(),
        folder: () async => Directory('${tmp.path}/journeys'),
        planner: _fakePlanner(),
        linesInBox: _fakeLines(),
      );
      addTearDown(service.dispose);

      final journey = await service.plan(
        from: const JourneyPlace(
            name: 'Your location', lat: 0, lon: 0, isCurrentLocation: true),
        to: _to,
      );

      expect(journey, isNull);
      expect(service.stage, JourneyStage.failed);
      expect(service.error, 'Waiting for your location');
    });

    test('a destination over 80 km away is refused', () async {
      final service = JourneyService(
        maps: await noPacksInstalled(),
        session: _SpySession(),
        folder: () async => Directory('${tmp.path}/journeys'),
        planner: _fakePlanner(),
        linesInBox: _fakeLines(),
      );
      addTearDown(service.dispose);

      final journey = await service.plan(
        from: _from,
        to: const JourneyPlace(name: 'Far', lat: 21.0, lon: 75.0),
      );

      expect(journey, isNull);
      expect(service.stage, JourneyStage.failed);
      expect(service.error, contains('too long'));
    });

    test('a destination under 50 m away is refused', () async {
      final service = JourneyService(
        maps: await noPacksInstalled(),
        session: _SpySession(),
        folder: () async => Directory('${tmp.path}/journeys'),
        planner: _fakePlanner(),
        linesInBox: _fakeLines(),
      );
      addTearDown(service.dispose);

      final journey = await service.plan(
        from: _from,
        to: const JourneyPlace(name: 'Next door', lat: 19.05001, lon: 72.83),
      );

      expect(journey, isNull);
      expect(service.stage, JourneyStage.failed);
    });

    test('no drivable route found fails clearly', () async {
      final maps = await _mapsWithPack(_wideBandraPack);
      final service = JourneyService(
        maps: maps,
        session: _SpySession(),
        folder: () async => Directory('${tmp.path}/journeys'),
        planner: _fakePlanner(returnsNull: true),
        linesInBox: _fakeLines(),
      );
      addTearDown(service.dispose);

      final journey = await service.plan(from: _from, to: _to);

      expect(journey, isNull);
      expect(service.error, contains('No drivable route'));
    });

    test('uncovered and online downloads a corridor pack, then plans',
        () async {
      final mapsDir = Directory('${tmp.path}/maps');
      final maps = OfflineMapService(
        locator: _DirLocator(mapsDir),
        opener: (l, p) async => EmptyTileProvider(maxZoom: p.maxZoom),
        catalog: const [],
      );
      await maps.load();
      final installer = FakeInstaller(mapsDir);
      final session = _SpySession();
      final service = JourneyService(
        maps: maps,
        session: session,
        installer: installer,
        folder: () async => Directory('${tmp.path}/journeys'),
        isOnline: () async => true,
        planner: _fakePlanner(),
        linesInBox: _fakeLines(),
      );
      addTearDown(service.dispose);

      final journey = await service.plan(from: _from, to: _to);

      expect(journey, isNotNull);
      expect(installer.started, ['journey-corridor']);
      expect(journey!.corridorPackId, 'journey-corridor');
      expect(journey.corridorPackBox, isNotNull);
      expect(maps.isInstalled('journey-corridor'), isTrue);
    });

    test('uncovered and offline fails with a clear message', () async {
      final service = JourneyService(
        maps: await noPacksInstalled(),
        session: _SpySession(),
        folder: () async => Directory('${tmp.path}/journeys'),
        isOnline: () async => false,
        planner: _fakePlanner(),
        linesInBox: _fakeLines(),
      );
      addTearDown(service.dispose);

      final journey = await service.plan(from: _from, to: _to);

      expect(journey, isNull);
      expect(service.stage, JourneyStage.failed);
      expect(service.error, contains('No offline map covers this route'));
    });
  });

  group('JourneyService.restore', () {
    test('reloads a saved active journey and resumes the route', () async {
      final journeysDir = Directory('${tmp.path}/journeys')
        ..createSync(recursive: true);
      final journey = Journey(
        from: _from,
        to: _to,
        route: _route(19.05, 72.83, 19.10, 72.90),
        createdAt: DateTime(2026, 1, 1),
      );
      File('${journeysDir.path}/active.json')
          .writeAsStringSync(jsonEncode(journey.toJson()));
      final session = _SpySession();
      final service = JourneyService(
        maps: await noPacksInstalled(),
        session: session,
        folder: () async => journeysDir,
      );
      addTearDown(service.dispose);

      await service.restore();

      expect(service.active, isNotNull);
      expect(service.active!.from.name, 'A');
      expect(session.startedRoutes, hasLength(1));
    });

    test('ignores a malformed active.json', () async {
      final journeysDir = Directory('${tmp.path}/journeys')
        ..createSync(recursive: true);
      File('${journeysDir.path}/active.json').writeAsStringSync('{not json');
      final service = JourneyService(
        maps: await noPacksInstalled(),
        session: _SpySession(),
        folder: () async => journeysDir,
      );
      addTearDown(service.dispose);

      await service.restore();

      expect(service.active, isNull);
    });

    test('re-registers the stored corridor pack', () async {
      final mapsDir = Directory('${tmp.path}/maps')..createSync(recursive: true);
      File('${mapsDir.path}/journey-corridor.pmtiles')
          .writeAsBytesSync([1, 2, 3]);
      final maps = OfflineMapService(
        locator: _DirLocator(mapsDir),
        opener: (l, p) async => EmptyTileProvider(maxZoom: p.maxZoom),
        catalog: const [],
      );
      await maps.load();
      expect(maps.isInstalled('journey-corridor'), isFalse);

      final journeysDir = Directory('${tmp.path}/journeys')
        ..createSync(recursive: true);
      final journey = Journey(
        from: _from,
        to: _to,
        route: _route(19.05, 72.83, 19.10, 72.90),
        createdAt: DateTime(2026, 1, 1),
        corridorPackId: 'journey-corridor',
        corridorPackBox: const CorridorBox(
            south: 19.0, west: 72.7, north: 19.2, east: 73.0, maxZoom: 15),
      );
      File('${journeysDir.path}/active.json')
          .writeAsStringSync(jsonEncode(journey.toJson()));

      final service = JourneyService(
        maps: maps,
        session: _SpySession(),
        folder: () async => journeysDir,
      );
      addTearDown(service.dispose);

      await service.restore();

      expect(maps.isInstalled('journey-corridor'), isTrue);
    });
  });

  group('JourneyService reroute', () {
    test('a sustained off-route condition on live GNSS replans the active journey',
        () async {
      final maps = await _mapsWithPack(_wideBandraPack);
      final session = _SpySession();
      var now = DateTime(2026, 1, 1, 12);
      final service = JourneyService(
        maps: maps,
        session: session,
        folder: () async => Directory('${tmp.path}/journeys'),
        planner: _fakePlanner(),
        linesInBox: _fakeLines(),
        clock: () => now,
      );
      addTearDown(service.dispose);

      final journey = Journey(
        from: _from,
        to: _to,
        route: _route(_from.lat, _from.lon, _to.lat, _to.lon),
        createdAt: now,
      );
      await service.start(journey);
      expect(session.startedRoutes, hasLength(1));

      // Past the reroute cooldown from the moment `start` planned.
      now = now.add(const Duration(seconds: 25));

      // On route (or GNSS not live): no reroute.
      session.fakeLat = 19.06;
      session.fakeLon = 72.84;
      session.fakeLiveGnss = true;
      session.fakeOffRoute = false;
      session.poke();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(session.startedRoutes, hasLength(1));

      // Off route with live GNSS: replans.
      session.fakeOffRoute = true;
      session.poke();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.isRerouting, isFalse);
      expect(session.startedRoutes, hasLength(2));
      expect(service.active!.route, session.startedRoutes.last);

      // Within the cooldown, further off-route pokes do nothing.
      session.poke();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(session.startedRoutes, hasLength(2));

      // Past the cooldown, it can replan again.
      now = now.add(const Duration(seconds: 21));
      session.poke();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(session.startedRoutes, hasLength(3));
    });

    test('never downloads while rerouting: an uncovered position gives up silently',
        () async {
      final maps = await noPacksInstalled();
      final session = _SpySession();
      final service = JourneyService(
        maps: maps,
        session: session,
        folder: () async => Directory('${tmp.path}/journeys'),
        planner: _fakePlanner(),
        linesInBox: _fakeLines(),
      );
      addTearDown(service.dispose);
      final journey = Journey(
        from: _from,
        to: _to,
        route: _route(_from.lat, _from.lon, _to.lat, _to.lon),
        createdAt: DateTime(2026, 1, 1),
      );
      await service.start(journey);

      session.fakeLat = 19.06;
      session.fakeLon = 72.84;
      session.fakeLiveGnss = true;
      session.fakeOffRoute = true;
      session.poke();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(session.startedRoutes, hasLength(1)); // no reroute happened
      expect(service.isRerouting, isFalse);
    });
  });
}
