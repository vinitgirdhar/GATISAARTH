import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_reader.dart';
import 'package:gatisaarth/core/platform/maps/pack_road_source.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/fake_map_packs.dart';
import 'support/session_fakes.dart';

/// The real thing: the tunnel test and the urban canyon driven through the
/// streets of a real offline map archive, wherever one is available.
///
/// Delhi NCR ships with the app (`assets/maps/packs/`, git-ignored, so the test
/// skips on a checkout without it). More archives are read from the folder in
/// `MAP_PACK_DIR` - `adb pull` a phone's `files/offline_maps/*.pmtiles` there -
/// so the same checks run for Mumbai, Pune or anywhere else the app has maps.
class _Place {
  const _Place(this.pack, this.name, this.lat, this.lon);
  final String pack;
  final String name;
  final double lat;
  final double lon;
}

const _places = [
  _Place('delhi-ncr', 'Delhi, Dwarka', 28.5921, 77.0460),
  _Place('delhi-ncr', 'Delhi, Connaught Place', 28.6315, 77.2167),
  _Place('delhi-ncr', 'Delhi, Karol Bagh', 28.6519, 77.1909),
  _Place('mumbai', 'Mumbai, MHB Colony', 19.1307, 72.8606),
  _Place('mumbai', 'Mumbai, Bandra', 19.0596, 72.8295),
  _Place('mumbai', 'Mumbai, Andheri', 19.1136, 72.8697),
  _Place('pune', 'Pune, Shaniwar Wada', 18.5195, 73.8553),
  _Place('pune', 'Pune, Kothrud', 18.5074, 73.8077),
  _Place('pune', 'Pune, Baner', 18.5590, 73.7868),
];

File? _packFile(String id) {
  final dirs = [
    'assets/maps/packs',
    if (Platform.environment['MAP_PACK_DIR'] != null)
      Platform.environment['MAP_PACK_DIR']!,
  ];
  for (final dir in dirs) {
    final file = File('$dir/$id.pmtiles');
    if (file.existsSync()) return file;
  }
  return null;
}

/// Frame layout: [ax, ay, az, gx, gy, gz, t, mx, my, mz, pressure, altitude].
List<double> _frame(double t) =>
    [0, 0, 9.81, 0, 0, 0, t, 0, 30, 0, double.nan, double.nan];

double _metres(double lat0, double lon0, double lat1, double lon1) {
  final dLat = (lat1 - lat0) * 111320;
  final dLon = (lon1 - lon0) * 111320 * math.cos(lat0 * math.pi / 180);
  return math.sqrt(dLat * dLat + dLon * dLon);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sources = <String, PackRoadGraphSource>{};

  Future<PackRoadGraphSource?> sourceFor(String id) async {
    final cached = sources[id];
    if (cached != null) return cached;
    final file = _packFile(id);
    if (file == null) return null;
    final maps = OfflineMapService(
      locator: FakeMapPackLocator({
        '$id.pmtiles': PackLocation(
          path: file.path,
          offset: 0,
          length: file.lengthSync(),
          origin: PackOrigin.sideloaded,
        ),
      }),
    );
    await maps.load();
    return sources[id] = PackRoadGraphSource(maps);
  }

  for (final place in _places) {
    final skip = _packFile(place.pack) == null
        ? '${place.pack}.pmtiles not on this machine'
        : null;

    test('${place.name}: the tunnel test never leaves the drawn streets',
        skip: skip, timeout: const Timeout(Duration(minutes: 3)), () async {
      SharedPreferences.setMockInitialValues({});
      final source = (await sourceFor(place.pack))!;
      final coverage = await source.roadsAround(place.lat, place.lon);
      expect(coverage, isNotNull, reason: 'roads read from the archive');
      final graph = coverage!.graph;
      final nearest =
          graph.nearby(place.lat, place.lon, radiusM: 400, limit: 1);
      expect(nearest, isNotEmpty, reason: 'a street near ${place.name}');
      final start = nearest.first;

      final sensors = FakeSensors();
      final gateway = FakeLocationGateway();
      final hardware = FakeHardware();
      final now = DateTime(2026, 9, 20, 12);
      final controller = LiveSessionController(
        sensors: sensors,
        alignment: VehicleAlignmentEngine(),
        hardware: hardware,
        speedEstimator: FakeSpeed(),
        telemetry: FakeTelemetry(),
        location: LiveLocationService(gateway: gateway, clock: () => now),
        clock: () => now,
        autoTick: false,
        haptics: Haptics(hardware, pause: (_) async {}),
        roads: source,
      );
      addTearDown(controller.dispose);

      await controller.start();
      gateway.fixController.add(GnssFix(
        latitude: start.lat,
        longitude: start.lon,
        altitude: 10,
        accuracy: 5,
        speed: 12.5,
      ));
      await settle();
      controller.tick();

      // The controller reads the roads in the background; wait for them.
      controller.startTunnelTest();
      for (var i = 0; i < 300 && !controller.isOnRoad; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        controller.tick();
      }
      expect(controller.isOnRoad, isTrue, reason: 'locked onto a street');

      var t = 100.0;
      var worst = 0.0;
      var travelled = 0.0;
      var prevLat = controller.latitude;
      var prevLon = controller.longitude;
      // 600 frames of 0.1 s at 12.5 m/s: 750 m of driving.
      for (var i = 0; i < 600; i++) {
        t += 0.1;
        sensors.frames.add(_frame(t));
        await settle();
        controller.tick();
        final lat = controller.latitude, lon = controller.longitude;
        travelled += _metres(prevLat, prevLon, lat, lon);
        prevLat = lat;
        prevLon = lon;
        final near = graph.nearby(lat, lon, radiusM: 50, limit: 1);
        final off = near.isEmpty ? double.infinity : near.first.perpendicularM;
        worst = math.max(worst, off);
      }

      printOnFailure('${place.name}: travelled ${travelled.toStringAsFixed(0)}'
          ' m, worst distance from a street ${worst.toStringAsFixed(2)} m');
      expect(worst, lessThan(0.5), reason: 'never off the drawn street');
      expect(travelled, greaterThan(300),
          reason: 'kept moving along the streets, did not stall');
    });

    test('${place.name}: the urban canyon keeps to the street too',
        skip: skip, timeout: const Timeout(Duration(minutes: 3)), () async {
      SharedPreferences.setMockInitialValues({});
      final source = (await sourceFor(place.pack))!;
      final graph = (await source.roadsAround(place.lat, place.lon))!.graph;
      final start = graph.nearby(place.lat, place.lon, radiusM: 400, limit: 1);
      expect(start, isNotEmpty);

      final sensors = FakeSensors();
      final gateway = FakeLocationGateway();
      final hardware = FakeHardware();
      final now = DateTime(2026, 9, 20, 12);
      final controller = LiveSessionController(
        sensors: sensors,
        alignment: VehicleAlignmentEngine(),
        hardware: hardware,
        speedEstimator: FakeSpeed(),
        telemetry: FakeTelemetry(),
        location: LiveLocationService(gateway: gateway, clock: () => now),
        clock: () => now,
        autoTick: false,
        haptics: Haptics(hardware, pause: (_) async {}),
        roads: source,
      );
      addTearDown(controller.dispose);

      await controller.start();
      // A standing receiver, like the emulator's: it never reports movement.
      GnssFix standing() => GnssFix(
            latitude: start.first.lat,
            longitude: start.first.lon,
            altitude: 10,
            accuracy: 5,
            speed: 0,
          );
      gateway.fixController.add(standing());
      await settle();
      controller.tick();

      // The controller reads the roads in the background; wait for them.
      controller.startUrbanCanyon();
      for (var i = 0; i < 300 && !controller.isOnRoad; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        controller.tick();
      }
      expect(controller.isOnRoad, isTrue, reason: 'locked onto a street');

      var t = 100.0;
      var worst = 0.0;
      for (var i = 0; i < 400; i++) {
        t += 0.1;
        sensors.frames.add(_frame(t));
        await settle();
        if (i % 10 == 9) {
          gateway.fixController.add(standing());
          await settle();
        }
        controller.tick();
        final near = graph.nearby(controller.latitude, controller.longitude,
            radiusM: 50, limit: 1);
        final off = near.isEmpty ? double.infinity : near.first.perpendicularM;
        worst = math.max(worst, off);
      }

      final moved = _metres(start.first.lat, start.first.lon,
          controller.latitude, controller.longitude);
      printOnFailure('${place.name}: ${moved.toStringAsFixed(0)} m from the '
          'start, worst distance from a street ${worst.toStringAsFixed(2)} m');
      expect(worst, lessThan(0.5));
      expect(moved, greaterThan(50), reason: 'the simulated drive progressed');
    });
  }
}
