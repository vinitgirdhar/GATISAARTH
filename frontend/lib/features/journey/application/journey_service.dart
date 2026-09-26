import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:path_provider/path_provider.dart';

import '../../../core/nav/map/road_graph.dart';
import '../../../core/nav/map/tile_roads.dart' show TileRoadLine, buildRoadGraph;
import '../../../core/nav/math/nav_math.dart' show NavMath;
import '../../../core/nav/nav_config.dart' show RouteConfig;
import '../../../core/nav/route/planned_route.dart';
import '../../../core/nav/route/route_planner.dart';
import '../../../core/platform/maps/map_download_service.dart' show describeDownloadError;
import '../../../core/platform/maps/offline_catalog.dart';
import '../../../core/platform/maps/offline_map_service.dart';
import '../../../core/platform/maps/pack_installer.dart';
import '../../../core/platform/maps/pack_road_source.dart';
import '../../../core/platform/maps/place_search.dart';
import '../../navigation_ui/presentation/controllers/live_session_controller.dart';
import '../domain/journey.dart';

/// Where [JourneyService.plan] is.
enum JourneyStage {
  idle,
  checkingMaps,
  downloadingMap,
  readingRoads,
  planning,
  saving,
  ready,
  failed,
}

/// A route planner function, matching [planRoute]'s own signature: tests
/// inject one so they never depend on the other agent's real implementation.
typedef JourneyPlannerFn = PlannedRoute? Function(
  RoadGraph graph, {
  required double fromLat,
  required double fromLon,
  required double toLat,
  required double toLon,
  VehicleAccess vehicle,
  RouteConfig config,
});

/// Reads every road line inside a lat/lon box, matching
/// [PackRoadGraphSource.linesInBox]'s own signature.
typedef CorridorLinesReader = Future<({List<TileRoadLine> lines, String packId})?>
    Function({
  required double south,
  required double west,
  required double north,
  required double east,
  int maxTiles,
});

/// The straight-line distance limits a journey may be planned between.
const double _minCorridorDistanceM = 50;
const double _maxCorridorDistanceM = 80000;

/// Padding around the raw from/to box: the greater of a flat minimum and a
/// share of the trip length, so a short hop still gets a usable margin to
/// route (and reroute) within.
const double _minPaddingM = 1500;
const double _paddingFraction = 0.25;

const double _metresPerDegree = 111320;

/// A sustained off-route condition does not replan more often than this.
const Duration _rerouteMinInterval = Duration(seconds: 20);

/// Fixed id: a phone only ever has one corridor pack cut for the journey in
/// progress, so the next journey's download simply replaces the old file.
const String _corridorPackId = 'journey-corridor';

/// Plans a journey, caches everything it needs on the phone, and hands the
/// route to the live session.
///
/// [plan]: resolves "Your location" from the session, checks an installed
/// pack (maxZoom >= 13) covers the whole corridor (both ends plus a margin);
/// if none does and the phone is online, cuts a corridor pack out of the
/// Protomaps build with [PackInstaller] ([stage] = downloadingMap,
/// [downloadProgress] 0..1) and registers it with the map service; reads the
/// corridor's roads, plans the route off the UI thread, saves the journey JSON
/// to the app's support folder and exposes it as [preview]. Offline with no
/// covering pack: fails with a clear [error]. Never throws.
///
/// [start] makes the preview the [active] journey: persists it and calls
/// `session.startRoute`. [end] clears it. [restore] (app start) reloads a saved
/// active journey (re-registering its corridor pack) and resumes it.
///
/// While active and GNSS is live, a sustained `session.isOffRoute` re-plans
/// from the current position to the same destination (at most every 20 s).
class JourneyService extends ChangeNotifier {
  JourneyService({
    required this.maps,
    required this.session,
    PackInstaller? installer,
    Future<Directory> Function()? folder,
    Future<bool> Function()? isOnline,
    JourneyPlannerFn? planner,
    CorridorLinesReader? linesInBox,
    DateTime Function()? clock,
  })  : installer = installer ?? PackInstaller(),
        _folder = folder ?? _defaultFolder,
        _isOnline = isOnline ?? _probeInternet,
        _planner = planner ?? planRoute,
        _usesIsolate = planner == null,
        _linesReader = linesInBox,
        _clock = clock ?? DateTime.now {
    session.addListener(_onSessionChanged);
  }

  final OfflineMapService maps;
  final LiveSessionController session;
  final PackInstaller installer;

  final Future<Directory> Function() _folder;
  final Future<bool> Function() _isOnline;
  final JourneyPlannerFn _planner;

  /// False when a test injected its own [_planner]: a test double cannot
  /// safely cross an isolate boundary, so planning then runs in place.
  final bool _usesIsolate;
  final CorridorLinesReader? _linesReader;
  final DateTime Function() _clock;

  late final PlaceSearch places = PlaceSearch(maps);
  late final PackRoadGraphSource _roadSource = PackRoadGraphSource(maps);

  JourneyStage _stage = JourneyStage.idle;
  double? _downloadProgress;
  String? _error;
  Journey? _preview;
  Journey? _active;
  bool _isRerouting = false;
  DateTime? _lastPlanAt;
  bool _disposed = false;

  JourneyStage get stage => _stage;
  double? get downloadProgress => _downloadProgress;
  String? get error => _error;
  Journey? get preview => _preview;
  Journey? get active => _active;
  bool get isRerouting => _isRerouting;

  // -------------------------------------------------------------- planning

  Future<Journey?> plan({
    required JourneyPlace from,
    required JourneyPlace to,
  }) async {
    _error = null;
    _downloadProgress = null;
    _stage = JourneyStage.checkingMaps;
    _notify();
    try {
      final resolvedFrom = _resolveCurrentLocation(from);
      if (resolvedFrom == null) return _fail('Waiting for your location');
      final resolvedTo = _resolveCurrentLocation(to);
      if (resolvedTo == null) return _fail('Waiting for your location');

      final box = _corridorBox(resolvedFrom, resolvedTo);
      if (box.distanceM > _maxCorridorDistanceM) {
        return _fail(
          'Route too long for an offline journey; pick a destination under '
          '80 km away.',
        );
      }
      if (box.distanceM < _minCorridorDistanceM) {
        return _fail('That destination is too close to route to.');
      }

      var pack = _packCoveringCorridor(box);
      String? corridorPackId;
      CorridorBox? corridorPackBox;
      if (pack == null) {
        if (!await _isOnline()) {
          return _fail(_noCoverageMessage);
        }
        final downloaded = await _downloadCorridor(box);
        if (downloaded == null) return null; // _downloadCorridor set _error
        pack = _packCoveringCorridor(box);
        if (pack == null) return _fail('The downloaded map does not cover this route.');
        corridorPackId = downloaded.id;
        corridorPackBox = CorridorBox(
          south: box.south,
          west: box.west,
          north: box.north,
          east: box.east,
          maxZoom: downloaded.maxZoom,
        );
      }

      _stage = JourneyStage.readingRoads;
      _downloadProgress = null;
      _notify();
      final read = await _readLines(box);
      if (read == null) return _fail(_noCoverageMessage);

      _stage = JourneyStage.planning;
      _notify();
      final route = await _computeRoute(
        lines: read.lines,
        region: read.packId,
        from: resolvedFrom,
        to: resolvedTo,
      );
      if (route == null) return _fail('No drivable route found between these places.');

      _stage = JourneyStage.saving;
      _notify();
      final journey = Journey(
        from: resolvedFrom,
        to: resolvedTo,
        route: route,
        createdAt: _clock(),
        corridorPackId: corridorPackId,
        corridorPackBox: corridorPackBox,
      );
      await _writeJourney(journey, 'preview.json');
      _lastPlanAt = _clock();
      _preview = journey;
      _stage = JourneyStage.ready;
      _notify();
      return journey;
    } catch (e, st) {
      debugPrint('[Journey] plan failed: $e\n$st');
      return _fail('Could not plan this journey.');
    }
  }

  static const String _noCoverageMessage =
      'No offline map covers this route. Connect to the internet once so '
      "the route's map can be downloaded, or download the region in "
      'Profile > Offline Maps.';

  Journey? _fail(String message) {
    _error = message;
    _stage = JourneyStage.failed;
    _downloadProgress = null;
    debugPrint('[Journey] plan failed: $message');
    _notify();
    return null;
  }

  /// Cuts and registers the corridor pack. Returns the pack on success, or
  /// null after setting [error] (a failed download).
  Future<OfflinePack?> _downloadCorridor(_Box box) async {
    _stage = JourneyStage.downloadingMap;
    _downloadProgress = 0;
    _notify();
    final corridorPack = OfflinePack(
      id: _corridorPackId,
      name: 'Journey route',
      south: box.south,
      west: box.west,
      north: box.north,
      east: box.east,
      maxZoom: 15,
      approxBytes: _estimateBytes(box),
      detail: true,
    );
    try {
      await installer.install(
        corridorPack,
        onProgress: (f) {
          _downloadProgress = f;
          _notify();
        },
      );
    } catch (e) {
      debugPrint('[Journey] corridor download failed: $e');
      _fail(describeDownloadError(e));
      return null;
    }
    maps.addPacks([corridorPack]);
    await maps.load();
    return corridorPack;
  }

  /// Rough guess for the progress bar's denominator only; the extraction's
  /// own byte count is what actually lands on disk.
  int _estimateBytes(_Box box) {
    final areaDeg2 = (box.north - box.south) * (box.east - box.west);
    final bytes = (areaDeg2 * 4.0e7).round();
    return bytes.clamp(200000, 30000000).toInt();
  }

  JourneyPlace? _resolveCurrentLocation(JourneyPlace place) {
    if (!place.isCurrentLocation) return place;
    if (session.uncertainty == null) return null;
    return JourneyPlace(
      name: place.name,
      lat: session.latitude,
      lon: session.longitude,
      isCurrentLocation: true,
    );
  }

  _Box _corridorBox(JourneyPlace from, JourneyPlace to) {
    final distanceM = NavMath.horizontalDistance(
      lat0: from.lat,
      lon0: from.lon,
      lat1: to.lat,
      lon1: to.lon,
    );
    final south0 = math.min(from.lat, to.lat);
    final north0 = math.max(from.lat, to.lat);
    final west0 = math.min(from.lon, to.lon);
    final east0 = math.max(from.lon, to.lon);
    final paddingM = math.max(_minPaddingM, _paddingFraction * distanceM);
    final midLatRad = (south0 + north0) / 2 * math.pi / 180;
    final latPad = paddingM / _metresPerDegree;
    final lonPad =
        paddingM / (_metresPerDegree * math.cos(midLatRad).abs().clamp(0.01, 1.0));
    return _Box(
      south0 - latPad,
      west0 - lonPad,
      north0 + latPad,
      east0 + lonPad,
      distanceM,
    );
  }

  /// The best installed pack (maxZoom >= 13) whose own box contains the
  /// whole corridor, or null.
  InstalledPack? _packCoveringCorridor(_Box box) {
    final sw = LatLng(box.south, box.west);
    final ne = LatLng(box.north, box.east);
    InstalledPack? best;
    for (final p in maps.installed) {
      if (p.provider.maximumZoom < 13) continue;
      if (!p.pack.contains(sw) || !p.pack.contains(ne)) continue;
      if (best == null || p.provider.maximumZoom > best.provider.maximumZoom) {
        best = p;
      }
    }
    return best;
  }

  Future<({List<TileRoadLine> lines, String packId})?> _readLines(_Box box) {
    final reader = _linesReader ?? _roadSource.linesInBox;
    return reader(
      south: box.south,
      west: box.west,
      north: box.north,
      east: box.east,
    );
  }

  /// Builds the graph and plans the route. The default planner runs off the
  /// UI thread; an injected test planner runs in place (it cannot cross an
  /// isolate boundary).
  Future<PlannedRoute?> _computeRoute({
    required List<TileRoadLine> lines,
    required String region,
    required JourneyPlace from,
    required JourneyPlace to,
  }) {
    if (!_usesIsolate) {
      final graph = buildRoadGraph(lines, region: region);
      if (graph == null) return Future.value(null);
      return Future.value(_planner(
        graph,
        fromLat: from.lat,
        fromLon: from.lon,
        toLat: to.lat,
        toLon: to.lon,
      ));
    }
    return compute(_planCorridorRoute, (
      lines: lines,
      region: region,
      fromLat: from.lat,
      fromLon: from.lon,
      toLat: to.lat,
      toLon: to.lon,
    ));
  }

  // ------------------------------------------------------ start/end/restore

  Future<void> start(Journey journey) async {
    await _writeJourney(journey, 'active.json');
    _active = journey;
    _preview = null;
    _lastPlanAt = _clock();
    session.startRoute(journey.route);
    _notify();
  }

  Future<void> end() async {
    session.endRoute();
    await _deleteFile('active.json');
    _active = null;
    _notify();
  }

  Future<void> restore() async {
    final journey = await _readJourney('active.json');
    if (journey == null) return;
    final id = journey.corridorPackId;
    final box = journey.corridorPackBox;
    if (id != null && box != null) {
      maps.addPacks([
        OfflinePack(
          id: id,
          name: 'Journey route',
          south: box.south,
          west: box.west,
          north: box.north,
          east: box.east,
          maxZoom: box.maxZoom,
          approxBytes: 0,
          detail: true,
        ),
      ]);
      await maps.load();
    }
    _active = journey;
    _lastPlanAt = _clock();
    session.startRoute(journey.route);
    _notify();
  }

  void clearPreview() {
    if (_preview == null) return;
    _preview = null;
    _notify();
  }

  // ------------------------------------------------------------- reroute

  void _onSessionChanged() {
    final current = _active;
    if (current == null || _isRerouting) return;
    if (!session.hasLiveGnss || !session.isOffRoute) return;
    final last = _lastPlanAt;
    if (last != null && _clock().difference(last) < _rerouteMinInterval) return;
    unawaited(_reroute(current));
  }

  /// Never downloads (installed packs only) and never throws: a failed
  /// reroute leaves the driver on the route they already have.
  Future<void> _reroute(Journey current) async {
    _isRerouting = true;
    _notify();
    try {
      final from = JourneyPlace(
        name: 'Your location',
        lat: session.latitude,
        lon: session.longitude,
        isCurrentLocation: true,
      );
      final box = _corridorBox(from, current.to);
      if (box.distanceM > _maxCorridorDistanceM ||
          box.distanceM < _minCorridorDistanceM) {
        return;
      }
      if (_packCoveringCorridor(box) == null) return;
      final read = await _readLines(box);
      if (read == null) return;
      final route = await _computeRoute(
        lines: read.lines,
        region: read.packId,
        from: from,
        to: current.to,
      );
      if (route == null) return;
      _lastPlanAt = _clock();
      final updated = current.copyWith(route: route);
      await _writeJourney(updated, 'active.json');
      _active = updated;
      session.startRoute(route);
    } catch (e) {
      debugPrint('[Journey] reroute failed: $e');
    } finally {
      _isRerouting = false;
      _notify();
    }
  }

  // ----------------------------------------------------------------- files

  Future<void> _writeJourney(Journey journey, String name) async {
    final dir = await _folder();
    await dir.create(recursive: true);
    await File('${dir.path}/$name').writeAsString(jsonEncode(journey.toJson()));
  }

  Future<Journey?> _readJourney(String name) async {
    try {
      final dir = await _folder();
      final file = File('${dir.path}/$name');
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) return null;
      return Journey.fromJson(raw);
    } catch (e) {
      debugPrint('[Journey] could not read $name: $e');
      return null;
    }
  }

  Future<void> _deleteFile(String name) async {
    try {
      final dir = await _folder();
      final file = File('${dir.path}/$name');
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[Journey] could not delete $name: $e');
    }
  }

  // --------------------------------------------------------------- support

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_onSessionChanged);
    super.dispose();
  }

  static Future<Directory> _defaultFolder() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/journeys');
  }

  static Future<bool> _probeInternet() async {
    try {
      final hosts = await InternetAddress.lookup('build.protomaps.com')
          .timeout(const Duration(seconds: 3));
      return hosts.isNotEmpty && hosts.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

@immutable
class _Box {
  const _Box(this.south, this.west, this.north, this.east, this.distanceM);

  final double south, west, north, east;
  final double distanceM;
}

/// The default (non-test) planning path, run inside a background isolate via
/// [compute]: pure and free of anything test-only, unlike an injected
/// [JourneyPlannerFn].
PlannedRoute? _planCorridorRoute(
  ({
    List<TileRoadLine> lines,
    String region,
    double fromLat,
    double fromLon,
    double toLat,
    double toLon,
  }) req,
) {
  final graph = buildRoadGraph(req.lines, region: req.region);
  if (graph == null) return null;
  return planRoute(
    graph,
    fromLat: req.fromLat,
    fromLon: req.fromLon,
    toLat: req.toLat,
    toLon: req.toLon,
  );
}

/// Makes the one [JourneyService] reachable from any screen.
class JourneyScope extends InheritedNotifier<JourneyService> {
  const JourneyScope({
    super.key,
    required JourneyService service,
    required super.child,
  }) : super(notifier: service);

  static JourneyService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<JourneyScope>()?.notifier;

  static JourneyService of(BuildContext context) {
    final service = maybeOf(context);
    assert(service != null, 'No JourneyScope above this context');
    return service!;
  }
}
