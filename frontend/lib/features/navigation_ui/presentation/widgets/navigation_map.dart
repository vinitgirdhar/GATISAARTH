import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../../core/nav/route/planned_route.dart';
import '../../../../core/platform/maps/map_download_service.dart';
import '../../../../core/platform/maps/offline_map_service.dart';
import '../../../../core/platform/maps/offline_tile_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/geo_format.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';
import '../controllers/track_trail.dart';
import 'basemap_layers.dart';
import 'fusion_confidence_badge.dart';
import 'map_controls.dart';
import 'map_follow.dart';
import 'vehicle_puck.dart';

/// What a finger may do to the map.
enum MapGestures {
  /// Nothing: a live preview.
  none,

  /// Pinch and double-tap zoom only. For a map inside a scrolling page, where a
  /// drag has to scroll the page.
  zoomOnly,

  /// Pan, pinch, rotate, double-tap zoom. Dragging leaves follow mode.
  full,
}

/// Live map: the vehicle, the track it has taken, and the position uncertainty
/// drawn to scale.
///
/// The camera follows the vehicle the way a phone navigation app does: it
/// glides between the 10 Hz position updates instead of jumping, zooms out as
/// speed rises, can turn with the heading, and lets go the moment the user
/// drags the map (the recentre button brings it back).
class NavigationMap extends StatefulWidget {
  const NavigationMap({
    super.key,
    required this.navigationState,
    required this.marginMeters,
    this.trail = const [],
    this.roadCorridors = const [],
    this.height = 260,
    this.gestures = MapGestures.none,
    this.expand = false,
    this.bottomInset = 12,
    this.actions = const [],
    this.onClearTrail,
    this.bottomStatus,
    this.initialFollow = FollowMode.north,
    this.controller,
    this.clock = DateTime.now,
    this.route,
    this.routeAlongM,
  });

  final NavigationStateModel navigationState;

  /// Modelled position uncertainty in metres; null while there is no fix.
  final double? marginMeters;

  /// The path travelled, oldest segment first (see [TrackTrail.segments]).
  final List<TrailSegment> trail;

  /// A journey route to draw under the trail and puck, or null.
  final PlannedRoute? route;

  /// How far along [route] the vehicle has travelled; the stretch before this
  /// is drawn as already-driven (greyed, thinner). Null draws it all ahead.
  final double? routeAlongM;

  /// Ranked offline-map hypotheses shown only when the session supplies them.
  final List<RoadCorridorModel> roadCorridors;

  final double height;
  final MapGestures gestures;

  /// Fill whatever the parent gives it, edge to edge (no card margin, corners
  /// or shadow), instead of being a fixed-[height] card. [height] is ignored.
  final bool expand;

  /// Gap between the bottom edge and the coordinates pill. Raise it when the
  /// map runs underneath a sheet that would otherwise cover the pill.
  final double bottomInset;

  /// Extra controls, stacked above the map's own ones (e.g. "fullscreen").
  final List<Widget> actions;

  /// Shows a "Clear track" chip while there is a track and this is set.
  final VoidCallback? onClearTrail;

  /// Short contextual status shown beside Clear track, above coordinates.
  final Widget? bottomStatus;

  final FollowMode initialFollow;

  /// Lets a test (or another widget) read and drive the camera. When null the
  /// map owns its controller.
  final MapController? controller;

  /// Time source for the zoom's hysteresis; a test supplies its own.
  final DateTime Function() clock;

  @override
  State<NavigationMap> createState() => _NavigationMapState();
}

class _NavigationMapState extends State<NavigationMap>
    with SingleTickerProviderStateMixin {
  late final MapController _map = widget.controller ?? MapController();
  final BundledOfflineTileProvider _raster = BundledOfflineTileProvider();
  late final Ticker _ticker = createTicker(_onFrame);

  bool _ready = false;
  late FollowMode _follow = widget.initialFollow;
  bool _autoZoom = true;
  bool _camLocked = true;
  bool _freeAnimating = false;
  Duration? _lastFrame;
  double _mapHeight = 400;

  // Everything below eases; the ticker runs only while something is moving.
  // The vehicle's drawn position (the controller already eases it at 10 Hz;
  // this smooths it to the display's frame rate).
  late final Ease _lat;
  late final Ease _lon;
  late final AngleEase _heading;
  // The camera.
  late final Ease _camLat;
  late final Ease _camLon;
  late final Ease _zoom;
  late final AngleEase _rotation;
  late final Ease _lookahead;

  bool _hadFix = false;
  DateTime _lastZoomChange = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final s = widget.navigationState;
    _lat = Ease(s.latitude, tau: 0.10, epsilon: 1e-9);
    _lon = Ease(s.longitude, tau: 0.10, epsilon: 1e-9);
    _heading = AngleEase(s.heading, tau: 0.25);
    _camLat = Ease(s.latitude, tau: 0.22, epsilon: 1e-8);
    _camLon = Ease(s.longitude, tau: 0.22, epsilon: 1e-8);
    _zoom = Ease(MapZoom.street, tau: 0.35, epsilon: 0.002);
    _rotation = AngleEase(0, tau: 0.30);
    _lookahead = Ease(0, tau: 0.35, epsilon: 0.5);
    _hadFix = widget.marginMeters != null;
  }

  @override
  void didUpdateWidget(covariant NavigationMap old) {
    super.didUpdateWidget(old);
    final s = widget.navigationState;
    final hasFix = widget.marginMeters != null;

    _lat.target = s.latitude;
    _lon.target = s.longitude;
    final jumped =
        _metres(_lat.value, _lon.value, s.latitude, s.longitude) > 300;
    if (jumped || (!_hadFix && hasFix)) {
      // The first fix, or a teleport (a location fix on an emulator): do not
      // glide across the country.
      _lat.snap();
      _lon.snap();
      _camLat.value = _camLat.target = s.latitude;
      _camLon.value = _camLon.target = s.longitude;
      _camLocked = true;
    }
    _hadFix = hasFix;
    _heading.aim(s.heading);
    _retarget();
    _wake();
  }

  @override
  void dispose() {
    _ticker.dispose();
    if (widget.controller == null) _map.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- targets

  double get _speed => widget.navigationState.speed;

  /// Points the camera's targets at what the current mode wants.
  void _retarget() {
    if (_follow == FollowMode.free) {
      _lookahead.target = 0;
      return;
    }
    _camLat.target = _lat.target;
    _camLon.target = _lon.target;
    _lookahead.target =
        _follow == FollowMode.heading ? headingLookaheadPx(_mapHeight) : 0;
    if (_follow == FollowMode.north) {
      _rotation.aim(0);
    } else if (_speed >= 1.0 || !_hadFix) {
      // Standing still, the compass wanders a few degrees: keep the last
      // orientation rather than swinging the whole map with it.
      _rotation.aim(-widget.navigationState.heading);
    }
    if (_autoZoom) {
      final wanted = autoZoomForSpeed(_speed);
      final now = widget.clock();
      // Hysteresis: do not breathe the zoom with every km/h.
      if ((wanted - _zoom.target).abs() >= 0.2 &&
          now.difference(_lastZoomChange) > const Duration(seconds: 1)) {
        _zoom.target = wanted;
        _lastZoomChange = now;
      }
    }
  }

  void _wake() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      for (final e in [
        _lat,
        _lon,
        _heading,
        _camLat,
        _camLon,
        _zoom,
        _rotation,
        _lookahead
      ]) {
        e.snap();
      }
      _applyCamera();
      if (mounted) setState(() {});
      return;
    }
    if (!_ticker.isActive) {
      _lastFrame = null;
      _ticker.start();
    }
  }

  // ---------------------------------------------------------------- frames

  void _onFrame(Duration elapsed) {
    final last = _lastFrame;
    _lastFrame = elapsed;
    final dt = last == null
        ? 1 / 60
        : ((elapsed - last).inMicroseconds / 1e6).clamp(0.0, 0.05);

    final moving = <bool>[
      _lat.step(dt),
      _lon.step(dt),
      _heading.step(dt),
      _zoom.step(dt),
      _rotation.step(dt),
      _lookahead.step(dt),
      if (_follow != FollowMode.free && !_camLocked) ...[
        _camLat.step(dt),
        _camLon.step(dt),
      ],
    ].contains(true);

    _applyCamera();
    setState(() {});
    if (!moving && !_freeAnimating) {
      _ticker.stop();
      _lastFrame = null;
    }
    if (!moving) _freeAnimating = false;
  }

  void _applyCamera() {
    if (!_ready) return;
    final camera = _map.camera;
    if (_follow == FollowMode.free) {
      if (!_freeAnimating) return;
      _map.moveAndRotate(camera.center, _zoom.value, _rotation.value);
      return;
    }

    // Follow: the camera centre is the vehicle. Once the camera has caught up
    // with it (after a recentre) it is locked to the drawn position, so the
    // puck never trembles against the map.
    final target = LatLng(_lat.value, _lon.value);
    if (_camLocked) {
      _camLat.value = _camLat.target = target.latitude;
      _camLon.value = _camLon.target = target.longitude;
    } else {
      _camLat.target = target.latitude;
      _camLon.target = target.longitude;
      if (_metres(
              _camLat.value, _camLon.value, target.latitude, target.longitude) <
          0.5) {
        _camLocked = true;
      }
    }
    final center = LatLng(_camLat.value, _camLon.value);
    final offsetPx = _lookahead.value;
    if (offsetPx < 0.5) {
      _map.moveAndRotate(center, _zoom.value, _rotation.value);
    } else {
      _map.rotate(_rotation.value);
      _map.move(center, _zoom.value, offset: Offset(0, offsetPx));
    }
  }

  // ---------------------------------------------------------------- events

  void _onMapEvent(MapEvent event) {
    switch (event.source) {
      case MapEventSource.mapController:
      case MapEventSource.nonRotatedSizeChange:
      case MapEventSource.interactiveFlagsChanged:
      case MapEventSource.tap:
      case MapEventSource.secondaryTap:
      case MapEventSource.longPress:
        return;
      case MapEventSource.dragStart:
      case MapEventSource.onDrag:
        if (_follow != FollowMode.free) _setFollow(FollowMode.free);
        _syncFromCamera(event.camera);
      default:
        // Pinch, double-tap zoom, fling, wheel. Following continues: the next
        // frame re-centres on the vehicle; the user's zoom is respected.
        _syncFromCamera(event.camera);
        if (_follow != FollowMode.free) {
          _autoZoom = false;
          _wake();
        }
    }
  }

  /// Copies the camera's state into the eases so the next glide starts from
  /// where the user left the map, not from where the code last put it.
  void _syncFromCamera(MapCamera camera) {
    _zoom.value = _zoom.target = camera.zoom;
    _rotation.value = _rotation.target = camera.rotation;
    if (mounted) setState(() {});
  }

  void _setFollow(FollowMode mode) {
    if (_follow == mode) return;
    final camera = _ready ? _map.camera : null;
    setState(() => _follow = mode);
    if (mode == FollowMode.free) return;
    if (camera != null) {
      // Glide from wherever the user left the map.
      _camLat.value = camera.center.latitude;
      _camLon.value = camera.center.longitude;
      _zoom.value = camera.zoom;
      _rotation.value = camera.rotation;
    }
    _camLocked = false;
    _autoZoom = true;
    _lastZoomChange = DateTime.fromMillisecondsSinceEpoch(0);
    _retarget();
    _wake();
  }

  void _onFollowTap() {
    _setFollow(switch (_follow) {
      FollowMode.free => FollowMode.north,
      FollowMode.north => FollowMode.heading,
      FollowMode.heading => FollowMode.north,
    });
    if (_follow == FollowMode.north && _rotation.target != 0) _retarget();
  }

  void _zoomBy(double delta) {
    if (!_ready) return;
    // Two quick taps add up: build on where the zoom is heading, not on where
    // the camera happens to be this instant.
    final from = _zoom.settled ? _map.camera.zoom : _zoom.target;
    _zoom.value = _map.camera.zoom;
    _zoom.target = (from + delta).clamp(MapZoom.min, MapZoom.max);
    _autoZoom = false;
    _freeAnimating = _follow == FollowMode.free;
    _wake();
  }

  void _pointNorth() {
    if (!_ready) return;
    if (_follow == FollowMode.heading) {
      _setFollow(FollowMode.north);
      return;
    }
    _rotation.value = _map.camera.rotation;
    _rotation.aim(0);
    _freeAnimating = _follow == FollowMode.free;
    _wake();
  }

  // ----------------------------------------------------------------- build

  static Color _modeColor(FusionMode mode) => switch (mode) {
        FusionMode.gnssLocked => AppColors.primary,
        FusionMode.gnssDegraded => AppColors.gnssDegraded,
        FusionMode.deadReckoning => AppColors.deadReckoning,
        FusionMode.reacquiring => AppColors.reacquiring,
      };

  int get _flags => switch (widget.gestures) {
        MapGestures.none => InteractiveFlag.none,
        MapGestures.zoomOnly =>
          InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
        MapGestures.full => _follow == FollowMode.free
            ? InteractiveFlag.all
            : InteractiveFlag.drag |
                InteractiveFlag.pinchZoom |
                InteractiveFlag.doubleTapZoom,
      };

  @override
  Widget build(BuildContext context) {
    final state = widget.navigationState;
    final margin = widget.marginMeters;
    final hasFix = margin != null;
    final dark = AppColors.isDark;
    final service = OfflineMapsScope.maybeOf(context);
    final radius = widget.expand ? BorderRadius.zero : AppRadius.cardRadius;
    final color = _modeColor(state.fusionMode);
    final estimated = state.fusionMode == FusionMode.deadReckoning;

    final drawn = LatLng(_lat.value, _lon.value);
    final rotation = _ready ? _map.camera.rotation : _rotation.value;

    return RepaintBoundary(
      child: Semantics(
        label: 'Map. ${state.fusionMode.label}. '
            '${formatLatitude(state.latitude)}, '
            '${formatLongitude(state.longitude)}',
        child: Container(
          height: widget.expand ? null : widget.height,
          margin: widget.expand
              ? EdgeInsets.zero
              : const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color: BasemapThemes.loadingColor(dark: dark),
            borderRadius: radius,
            boxShadow: widget.expand ? null : AppShadow.raised,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: LayoutBuilder(
              builder: (context, box) {
                _mapHeight = box.maxHeight.isFinite ? box.maxHeight : 400;
                return Stack(
                  children: [
                    FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        initialCenter: LatLng(state.latitude, state.longitude),
                        initialZoom: MapZoom.street,
                        minZoom: MapZoom.min,
                        maxZoom: MapZoom.max,
                        backgroundColor: BasemapThemes.loadingColor(dark: dark),
                        interactionOptions: InteractionOptions(flags: _flags),
                        onMapReady: () {
                          _ready = true;
                          _retarget();
                          _applyCamera();
                          // Start any glide the first targets ask for (the speed
                          // zoom), without waiting for the next position.
                          _wake();
                          if (mounted) setState(() {});
                        },
                        onMapEvent: _onMapEvent,
                      ),
                      children: [
                        Basemap(
                          service: service,
                          rasterProvider: _raster,
                          dark: dark,
                        ),
                        if (widget.route != null)
                          _RouteLayer(
                            route: widget.route!,
                            alongM: widget.routeAlongM,
                            dark: dark,
                          ),
                        if (widget.roadCorridors.isNotEmpty)
                          _RoadCorridorLayer(corridors: widget.roadCorridors),
                        if (widget.trail.isNotEmpty)
                          _TrackLayer(segments: widget.trail, dark: dark),
                        if (hasFix && margin >= 4)
                          CircleLayer(circles: [
                            CircleMarker(
                              point: drawn,
                              radius: margin,
                              useRadiusInMeter: true,
                              color: color.withValues(alpha: 0.10),
                              borderColor: color.withValues(alpha: 0.40),
                              borderStrokeWidth: 1,
                            ),
                          ]),
                        if (hasFix)
                          MarkerLayer(rotate: true, markers: [
                            Marker(
                              point: drawn,
                              width: VehiclePuck.extent,
                              height: VehiclePuck.extent,
                              child: IgnorePointer(
                                child: VehiclePuck(
                                  color: color,
                                  headingDegrees: _heading.value + rotation,
                                  estimated: estimated,
                                ),
                              ),
                            ),
                          ]),
                      ],
                    ),
                    ..._overlays(context, service, state, margin, rotation),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _overlays(
    BuildContext context,
    OfflineMapService? service,
    NavigationStateModel state,
    double? margin,
    double rotation,
  ) {
    final coverage = _ready
        ? BasemapCoverage.of(
            installed: service?.installed ?? const [],
            viewport: _map.camera.visibleBounds,
            zoom: _map.camera.zoom,
          )
        : const BasemapCoverage(base: [], detail: [], needsRaster: true);
    final center =
        _ready ? _map.camera.center : LatLng(state.latitude, state.longitude);
    final outside = outsideOfflineRegions(service, center);
    final downloads = MapDownloadsScope.maybeOf(context);
    final downloading = downloads != null && downloads.isBusy;
    final showControls = widget.gestures != MapGestures.none;
    final tallEnough = _mapHeight >= 300;

    return [
      Positioned(
        top: 12,
        left: 12,
        right: showControls ? 68 : 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FrostedPill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _modeColor(state.fusionMode),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(state.fusionMode.label, style: _pillStyle),
                ],
              ),
            ),
            if (widget.roadCorridors.length > 1) ...[
              const SizedBox(height: 6),
              _FrostedPill(
                child: Text(
                  '${widget.roadCorridors.length} possible roads',
                  style: _pillStyle,
                ),
              ),
            ],
            if (downloading) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/offline-maps'),
                child: _FrostedPill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: math.max(0.04, downloads.overallFraction),
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Downloading maps · '
                          '${(downloads.overallFraction * 100).round()}%',
                          style: _pillStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (outside) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/offline-maps'),
                child: _FrostedPill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded,
                          size: 13, color: AppColors.warning),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Outside offline maps',
                          style: _pillStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      if (showControls)
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final action in widget.actions) ...[
                action,
                const SizedBox(height: 8),
              ],
              if (rotation.abs() > 1) ...[
                CompassButton(
                  rotationDegrees: rotation,
                  onTap: _pointNorth,
                ),
                const SizedBox(height: 8),
              ],
              if (tallEnough) ...[
                MapZoomButtons(
                  onZoomIn: () => _zoomBy(1),
                  onZoomOut: () => _zoomBy(-1),
                  canZoomIn: !_ready || _map.camera.zoom < MapZoom.max - 0.01,
                  canZoomOut: !_ready || _map.camera.zoom > MapZoom.min + 0.01,
                ),
                const SizedBox(height: 8),
              ],
              FollowButton(mode: _follow, onTap: _onFollowTap),
            ],
          ),
        ),
      if ((widget.onClearTrail != null && widget.trail.isNotEmpty) ||
          widget.bottomStatus != null)
        Positioned(
          left: 12,
          right: 12,
          bottom: widget.bottomInset + 38,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.onClearTrail != null && widget.trail.isNotEmpty) ...[
                GestureDetector(
                  onTap: widget.onClearTrail,
                  child: _FrostedPill(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timeline_rounded,
                            size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 5),
                        Text('Clear track', style: _pillStyle),
                      ],
                    ),
                  ),
                ),
                if (widget.bottomStatus != null) const SizedBox(width: 8),
              ],
              if (widget.bottomStatus != null)
                Expanded(
                  child: _FrostedPill(child: widget.bottomStatus!),
                ),
            ],
          ),
        ),
      Positioned(
        right: 14,
        bottom: widget.bottomInset + (widget.bottomStatus == null ? 40 : 88),
        child: IgnorePointer(
          child: Text(
            basemapAttribution(coverage),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary.withValues(alpha: 0.55),
              shadows: [
                Shadow(
                  color: AppColors.surface.withValues(alpha: 0.9),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      Positioned(
        bottom: widget.bottomInset,
        left: 12,
        right: 12,
        child: _FrostedPill(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '${formatLatitude(state.latitude)}, '
                  '${formatLongitude(state.longitude)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _pillStyle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                margin == null ? 'No fix yet' : '±${margin.round()} m',
                style: TextStyle(
                  color: margin == null
                      ? AppColors.textSecondary
                      : FusionConfidenceBadge.colorFor(state.confidence),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  static double _metres(double lat1, double lon1, double lat2, double lon2) {
    const perDegree = 111320.0;
    final dLat = (lat2 - lat1) * perDegree;
    final dLon = (lon2 - lon1) * perDegree * math.cos(lat1 * math.pi / 180);
    return math.sqrt(dLat * dLat + dLon * dLon);
  }

  /// A getter, not a `static final`: `AppColors.textPrimary` depends on the
  /// brightness, and a cached style kept the first mode's colour for good
  /// (white text on a white chip after a switch to light).
  static TextStyle get _pillStyle => TextStyle(
        color: AppColors.textPrimary.withValues(alpha: 0.85),
        fontSize: 11,
        fontWeight: FontWeight.w600,
      );
}

/// A journey route: the stretch ahead in the accent colour with a light
/// casing (like [_TrackLayer]'s solid segments), the already-driven stretch
/// behind it thinner and greyed, plus a destination pin at the route's end.
class _RouteLayer extends StatelessWidget {
  const _RouteLayer({required this.route, required this.alongM, required this.dark});

  final PlannedRoute route;
  final double? alongM;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (var i = 0; i < route.pointCount; i++)
        LatLng(route.latAt(i), route.lonAt(i)),
    ];
    if (points.length < 2) return const SizedBox.shrink();

    // Nearest vertex to the travelled distance — exact enough for a line's
    // colour split; the geometry itself does not need sub-segment precision.
    var splitIndex = 0;
    final along = alongM;
    if (along != null) {
      final cum = route.cumM;
      while (splitIndex < cum.length - 1 && cum[splitIndex] < along) {
        splitIndex++;
      }
    }
    final drivenPoints = points.sublist(0, splitIndex + 1);
    final remainingPoints = points.sublist(splitIndex);
    final casing =
        dark ? const Color(0xCC1C1C1E) : Colors.white.withValues(alpha: 0.9);

    return Stack(children: [
      PolylineLayer(polylines: [
        if (remainingPoints.length >= 2)
          Polyline(
            points: remainingPoints,
            strokeWidth: 6,
            borderStrokeWidth: 1.8,
            borderColor: casing,
            color: AppColors.primary,
          ),
        if (drivenPoints.length >= 2)
          Polyline(
            points: drivenPoints,
            strokeWidth: 3.5,
            color: AppColors.textSecondary.withValues(alpha: 0.55),
          ),
      ]),
      MarkerLayer(markers: [
        Marker(
          point: points.last,
          width: 30,
          height: 40,
          alignment: Alignment.topCenter,
          child: IgnorePointer(
            child: Icon(Icons.location_on_rounded,
                color: AppColors.primary, size: 34),
          ),
        ),
      ]),
    ]);
  }
}

/// The track: solid where a satellite fix backed the position, dashed and red
/// where it was dead-reckoned, with a light casing so it reads on any map.
class _RoadCorridorLayer extends StatelessWidget {
  const _RoadCorridorLayer({required this.corridors});

  final List<RoadCorridorModel> corridors;

  @override
  Widget build(BuildContext context) => PolylineLayer(
        polylines: [
          for (var index = 0; index < corridors.length; index++)
            Polyline(
              points: [
                for (var i = 0;
                    i + 1 < corridors[index].polyline.length;
                    i += 2)
                  LatLng(
                    corridors[index].polyline[i],
                    corridors[index].polyline[i + 1],
                  ),
              ],
              color: AppColors.warning.withValues(
                alpha: (0.9 - index * 0.2).clamp(0.35, 0.9),
              ),
              strokeWidth: (7.0 - index * 1.5).clamp(3.0, 7.0),
              borderColor: AppColors.surface.withValues(alpha: 0.65),
              borderStrokeWidth: 1,
            ),
        ],
      );
}

class _TrackLayer extends StatelessWidget {
  const _TrackLayer({required this.segments, required this.dark});

  final List<TrailSegment> segments;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final casing =
        dark ? const Color(0xCC1C1C1E) : Colors.white.withValues(alpha: 0.9);
    return PolylineLayer(
      polylines: [
        for (final segment in segments)
          Polyline(
            points: segment.points,
            strokeWidth: 5.5,
            borderStrokeWidth: 1.6,
            borderColor: casing,
            color: segment.kind == TrailKind.gnss
                ? AppColors.primary
                : AppColors.deadReckoning,
            pattern: segment.kind == TrailKind.gnss
                ? const StrokePattern.solid()
                : StrokePattern.dashed(segments: const [9, 7]),
          ),
      ],
    );
  }
}

/// Floating map chip. Deliberately a near-opaque surface with a soft shadow
/// rather than a live backdrop blur: blurring a moving map every frame is
/// costly on low-power GPUs, and the look is nearly identical.
class _FrostedPill extends StatelessWidget {
  const _FrostedPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.control),
        boxShadow: AppShadow.card,
      ),
      child: child,
    );
  }
}
