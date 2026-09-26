import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:gatisaarth/core/theme/app_theme.dart';
import 'package:gatisaarth/features/navigation_engine/domain/entities/navigation_state.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/track_trail.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/map_controls.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/map_follow.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/navigation_map.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/vehicle_puck.dart';

import 'support/load_fonts.dart';

const _delhi = LatLng(28.639, 77.0661);
const _mumbai = LatLng(19.076, 72.8777);

NavigationStateModel _state({
  LatLng at = _delhi,
  double heading = 0,
  double speed = 0,
  FusionMode mode = FusionMode.gnssLocked,
}) =>
    NavigationStateModel(
      latitude: at.latitude,
      longitude: at.longitude,
      heading: heading,
      speed: speed,
      confidence: 0.9,
      fusionMode: mode,
    );

/// The map inside a fixed box, as the Map tab hosts it. Rebuilt with [state] so
/// a test can move the vehicle by pumping a new one.
Widget _host(
  NavigationStateModel state, {
  double? margin = 5,
  List<TrailSegment> trail = const [],
  MapController? controller,
  MapGestures gestures = MapGestures.full,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 411,
            height: 700,
            child: NavigationMap(
              navigationState: state,
              marginMeters: margin,
              trail: trail,
              expand: true,
              gestures: gestures,
              controller: controller,
              clock: () => _now,
            ),
          ),
        ),
      ),
    );

/// The map's clock: moves with the frames, so its 1 s zoom hysteresis can be
/// stepped through without waiting.
DateTime _now = DateTime(2026, 9, 20, 12);

/// Runs the camera's ticker for [ms] milliseconds in 16 ms frames.
Future<void> _run(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    _now = _now.add(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('it draws the vehicle only once there is a fix', (tester) async {
    await tester.pumpWidget(_host(_state(), margin: null));
    await _run(tester, 200);
    expect(find.byType(VehiclePuck), findsNothing);
    expect(find.text('No fix yet'), findsOneWidget);

    await tester.pumpWidget(_host(_state(), margin: 5));
    await _run(tester, 200);
    expect(find.byType(VehiclePuck), findsOneWidget);
    expect(find.text('±5 m'), findsOneWidget);
  });

  testWidgets('the accuracy is drawn to scale, as a circle in metres',
      (tester) async {
    await tester.pumpWidget(_host(_state(), margin: 40));
    await _run(tester, 200);
    final layer = tester.widget<CircleLayer>(find.byType(CircleLayer));
    expect(layer.circles.single.useRadiusInMeter, isTrue);
    expect(layer.circles.single.radius, 40);
  });

  testWidgets('a tiny margin draws no circle (it would hide under the dot)',
      (tester) async {
    await tester.pumpWidget(_host(_state(), margin: 2));
    await _run(tester, 200);
    expect(find.byType(CircleLayer), findsNothing);
  });

  testWidgets('the follow button cycles north up, heading up, north up',
      (tester) async {
    await tester.pumpWidget(_host(_state()));
    await _run(tester, 200);
    expect(find.byIcon(Icons.gps_fixed_rounded), findsOneWidget);

    await tester.tap(find.byType(FollowButton));
    await _run(tester, 400);
    expect(find.byIcon(Icons.navigation_rounded), findsOneWidget);

    await tester.tap(find.byType(FollowButton));
    await _run(tester, 400);
    expect(find.byIcon(Icons.gps_fixed_rounded), findsOneWidget);
  });

  testWidgets('dragging the map lets go of the vehicle, recentre takes it back',
      (tester) async {
    final controller = MapController();
    await tester.pumpWidget(_host(_state(), controller: controller));
    await _run(tester, 300);
    final start = controller.camera.center;

    await tester.drag(find.byType(FlutterMap), const Offset(-150, 0));
    await _run(tester, 300);
    expect(find.byIcon(Icons.gps_not_fixed_rounded), findsOneWidget,
        reason: 'the map is free now');
    expect(controller.camera.center.longitude,
        isNot(closeTo(start.longitude, 1e-5)));

    // The vehicle moves on; a free map does not follow it.
    final free = controller.camera.center;
    await tester.pumpWidget(_host(_state(at: const LatLng(28.6395, 77.0668)),
        controller: controller));
    await _run(tester, 400);
    expect(controller.camera.center.latitude, closeTo(free.latitude, 1e-6));

    await tester.tap(find.byType(FollowButton));
    await _run(tester, 1500);
    expect(controller.camera.center.latitude, closeTo(28.6395, 1e-4));
    expect(controller.camera.center.longitude, closeTo(77.0668, 1e-4));
    expect(find.byIcon(Icons.gps_fixed_rounded), findsOneWidget);
  });

  testWidgets('heading up turns the map so the direction of travel is up',
      (tester) async {
    final controller = MapController();
    await tester.pumpWidget(
        _host(_state(heading: 90, speed: 10), controller: controller));
    await _run(tester, 300);
    await tester.tap(find.byType(FollowButton)); // -> heading up
    await _run(tester, 2500);

    // East is up: the map is turned 90 degrees anticlockwise.
    expect(controller.camera.rotation, closeTo(-90, 1.5));
    // The compass appears, and tapping it goes back to north up.
    expect(find.byType(CompassButton), findsOneWidget);
    await tester.tap(find.byType(CompassButton));
    await _run(tester, 2500);
    expect(controller.camera.rotation, closeTo(0, 1.5));
    expect(find.byType(CompassButton), findsNothing);
  });

  testWidgets('standing still, a wandering compass does not swing the map',
      (tester) async {
    final controller = MapController();
    await tester.pumpWidget(
        _host(_state(heading: 90, speed: 10), controller: controller));
    await _run(tester, 200);
    await tester.tap(find.byType(FollowButton));
    await _run(tester, 2500);
    final turned = controller.camera.rotation;

    // The vehicle stops and the magnetometer wanders by 40 degrees.
    await tester.pumpWidget(
        _host(_state(heading: 130, speed: 0), controller: controller));
    await _run(tester, 1500);
    expect(controller.camera.rotation, closeTo(turned, 1));
  });

  testWidgets('the zoom buttons zoom by one level and stop at the limits',
      (tester) async {
    final controller = MapController();
    await tester.pumpWidget(_host(_state(), controller: controller));
    await _run(tester, 2000); // the opening glide to the parked zoom is done
    final before = controller.camera.zoom;

    await tester.tap(find.byIcon(Icons.add_rounded));
    await _run(tester, 1500);
    expect(controller.camera.zoom, closeTo(before + 1, 0.05));

    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await _run(tester, 2500);
    expect(controller.camera.zoom, closeTo(before - 1, 0.1));
  });

  testWidgets('speed zooms the map out', (tester) async {
    final controller = MapController();
    await tester.pumpWidget(_host(_state(speed: 0),
        controller: controller, gestures: MapGestures.zoomOnly));
    await _run(tester, 1500);
    final parked = controller.camera.zoom;
    expect(parked, closeTo(autoZoomForSpeed(0), 0.2));

    await tester.pumpWidget(_host(_state(speed: 25),
        controller: controller, gestures: MapGestures.zoomOnly));
    await _run(tester, 3000);
    expect(controller.camera.zoom, lessThan(parked - 1));
    expect(controller.camera.zoom, closeTo(autoZoomForSpeed(25), 0.3));
  });

  testWidgets(
      'the first fix, or a teleport, jumps instead of gliding across '
      'the country', (tester) async {
    final controller = MapController();
    await tester
        .pumpWidget(_host(_state(), margin: null, controller: controller));
    await _run(tester, 200);

    await tester.pumpWidget(
        _host(_state(at: _mumbai), margin: 5, controller: controller));
    await _run(tester, 160); // ten frames: a glide would not be there yet
    expect(controller.camera.center.latitude, closeTo(_mumbai.latitude, 0.01));
    expect(
        controller.camera.center.longitude, closeTo(_mumbai.longitude, 0.01));
  });

  testWidgets('the track is drawn solid for GNSS and dashed for dead reckoning',
      (tester) async {
    final trail = TrackTrail(minStepMeters: 1)
      ..add(28.6390, 77.0661, TrailKind.gnss)
      ..add(28.6395, 77.0661, TrailKind.gnss)
      ..add(28.6400, 77.0661, TrailKind.deadReckoning)
      ..add(28.6405, 77.0661, TrailKind.deadReckoning);
    await tester.pumpWidget(_host(_state(), trail: trail.segments));
    await _run(tester, 300);

    final lines =
        tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines;
    expect(lines, hasLength(2));
    expect(lines[0].pattern.segments, isNull, reason: 'solid');
    expect(lines[1].pattern.segments, isNotNull, reason: 'dashed');
  });

  testWidgets('clear track appears with a track and calls back',
      (tester) async {
    var cleared = 0;
    final trail = TrackTrail(minStepMeters: 1)
      ..add(28.6390, 77.0661, TrailKind.gnss)
      ..add(28.6395, 77.0661, TrailKind.gnss);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 411,
          height: 700,
          child: NavigationMap(
            navigationState: _state(),
            marginMeters: 5,
            trail: trail.segments,
            expand: true,
            gestures: MapGestures.full,
            onClearTrail: () => cleared++,
          ),
        ),
      ),
    ));
    await _run(tester, 200);
    await tester.tap(find.text('Clear track'));
    expect(cleared, 1);
  });

  testWidgets('bottom status shares a row with Clear track above coordinates',
      (tester) async {
    final trail = TrackTrail(minStepMeters: 1)
      ..add(28.6390, 77.0661, TrailKind.gnss)
      ..add(28.6395, 77.0661, TrailKind.gnss);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 420,
          child: NavigationMap(
            navigationState: _state(),
            marginMeters: 5,
            trail: trail.segments,
            expand: true,
            gestures: MapGestures.full,
            onClearTrail: () {},
            bottomStatus: const Text(
              'GNSS restored · validating the returned fix',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    ));
    await _run(tester, 200);

    final clear = tester.getRect(find.text('Clear track'));
    final restored = tester.getRect(
      find.text('GNSS restored · validating the returned fix'),
    );
    final coordinates = tester.getRect(find.textContaining('28.639'));
    expect(restored.left, greaterThan(clear.right));
    expect(restored.bottom, lessThan(coordinates.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a static preview has no controls', (tester) async {
    await tester.pumpWidget(_host(_state(), gestures: MapGestures.none));
    await _run(tester, 200);
    expect(find.byType(FollowButton), findsNothing);
    expect(find.byType(MapZoomButtons), findsNothing);
  });

  testWidgets('the attribution names OpenStreetMap', (tester) async {
    await tester.pumpWidget(_host(_state()));
    await _run(tester, 200);
    expect(find.textContaining('OpenStreetMap'), findsWidgets);
  });

  testWidgets('a dead-reckoned puck is drawn as estimated', (tester) async {
    await tester.pumpWidget(_host(_state(mode: FusionMode.deadReckoning)));
    await _run(tester, 200);
    expect(
        tester.widget<VehiclePuck>(find.byType(VehiclePuck)).estimated, isTrue);
  });

  testWidgets('the chips stay readable when the brightness changes',
      (tester) async {
    // The chip text used a `static final` style, so it kept whichever colour it
    // met first: white on a white chip after a switch to light.
    addTearDown(() => AppColors.isDark = false);
    Color chipText() =>
        tester.widget<Text>(find.text('GNSS locked')).style!.color!;

    AppColors.isDark = true;
    await tester.pumpWidget(_host(_state()));
    await _run(tester, 200);
    expect(chipText().computeLuminance(), greaterThan(0.5));

    AppColors.isDark = false;
    await tester.pumpWidget(_host(_state()));
    await _run(tester, 200);
    expect(chipText().computeLuminance(), lessThan(0.5));
  });
}
