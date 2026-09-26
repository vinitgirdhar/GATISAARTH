import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/route/planned_route.dart';
import 'package:gatisaarth/core/nav/route/route_tracker.dart';

import 'support/road_follower_fixtures.dart' show pointAt;

/// A straight ~1000 m route heading due east.
PlannedRoute _straightRoute() => PlannedRoute(
      polyline: [...pointAt(0, 0), ...pointAt(0, 1000)],
      maneuvers: const [
        RouteManeuver(kind: ManeuverKind.depart, atM: 0, lat: 0, lon: 0),
        RouteManeuver(kind: ManeuverKind.arrive, atM: 1000, lat: 0, lon: 0),
      ],
      durationS: 100,
    );

/// East 500 m, then a left turn north for 500 m (bearing 90 -> 0, a -90 deg
/// turn) — with a maneuver recorded at the bend.
PlannedRoute _bentRoute() => PlannedRoute(
      polyline: [...pointAt(0, 0), ...pointAt(0, 500), ...pointAt(500, 500)],
      maneuvers: const [
        RouteManeuver(kind: ManeuverKind.depart, atM: 0, lat: 0, lon: 0),
        RouteManeuver(kind: ManeuverKind.left, atM: 500, lat: 0, lon: 0),
        RouteManeuver(kind: ManeuverKind.arrive, atM: 1000, lat: 0, lon: 0),
      ],
      durationS: 100,
    );

/// A rectangular loop that returns exactly to its own start point, so a
/// point near the start is equally close (0 m) to the route's beginning and
/// to its end.
PlannedRoute _loopRoute() => PlannedRoute(
      polyline: [
        ...pointAt(0, 0),
        ...pointAt(1000, 0),
        ...pointAt(1000, 1000),
        ...pointAt(0, 1000),
        ...pointAt(0, 0),
      ],
      maneuvers: const [
        RouteManeuver(kind: ManeuverKind.depart, atM: 0, lat: 0, lon: 0),
        RouteManeuver(kind: ManeuverKind.arrive, atM: 4000, lat: 0, lon: 0),
      ],
      durationS: 400,
    );

void main() {
  group('RouteTracker dead reckoning', () {
    test('straight advance moves along-track and reports heading', () {
      final t = RouteTracker(_straightRoute());
      final start = pointAt(0, 0);
      expect(t.lockAt(start[0], start[1], headingDeg: 90), isTrue);
      expect(t.isLocked, isTrue);

      final p = t.advance(100);
      expect(p, isNotNull);
      expect(p!.alongM, closeTo(100, 0.5));
      expect(p.headingDeg, closeTo(90, 1));
      expect(t.hasDiverged, isFalse);
    });

    test('yaw matching the route bend causes no divergence', () {
      final t = RouteTracker(_bentRoute());
      final start = pointAt(0, 0);
      expect(t.lockAt(start[0], start[1], headingDeg: 90), isTrue);

      // The route itself turns -90 deg (east -> north) between 400 m and
      // 1000 m; feeding exactly that turn explains it entirely.
      t.addYaw(-90);
      t.advance(700);

      expect(t.hasDiverged, isFalse);
    });

    test('yaw the straight route cannot explain causes divergence', () {
      final t = RouteTracker(_straightRoute());
      final start = pointAt(0, 0);
      expect(t.lockAt(start[0], start[1], headingDeg: 90), isTrue);

      t.addYaw(90); // a real turn; the route stays dead straight
      t.advance(100);

      expect(t.hasDiverged, isTrue);
    });

    test('divergence persists until release or a fresh lock', () {
      final t = RouteTracker(_straightRoute());
      final start = pointAt(0, 0);
      t.lockAt(start[0], start[1], headingDeg: 90);
      t.addYaw(90);
      t.advance(100);
      expect(t.hasDiverged, isTrue);

      t.addYaw(0);
      t.advance(50);
      expect(t.hasDiverged, isTrue, reason: 'stays diverged without a reset');

      t.release();
      expect(t.hasDiverged, isFalse);
    });

    test('advance stops at the destination and reports arrived', () {
      final t = RouteTracker(_straightRoute());
      final start = pointAt(0, 0);
      t.lockAt(start[0], start[1], headingDeg: 90);

      final p = t.advance(5000);
      expect(p!.alongM, closeTo(1000, 1e-6));
      expect(t.progress.arrived, isTrue);

      // A further advance cannot overshoot the end.
      final p2 = t.advance(10);
      expect(p2!.alongM, closeTo(1000, 1e-6));
    });

    test('lockAt fails far from the route', () {
      final t = RouteTracker(_straightRoute());
      final far = pointAt(5000, 0);
      expect(t.lockAt(far[0], far[1]), isFalse);
      expect(t.isLocked, isFalse);
    });

    test('lockAt fails when heading disagrees with the route direction', () {
      final t = RouteTracker(_straightRoute());
      final onRoute = pointAt(0, 500);
      // The route heads east (90 deg); pointing south disagrees by 180 deg.
      expect(t.lockAt(onRoute[0], onRoute[1], headingDeg: 180), isFalse);
      expect(t.isLocked, isFalse);
      expect(t.lockAt(onRoute[0], onRoute[1], headingDeg: 90), isTrue);
    });
  });

  group('RouteTracker observation', () {
    test('observe projects onto the route and advances progress', () {
      final t = RouteTracker(_straightRoute());
      final p = pointAt(0, 200);
      final perp = t.observe(p[0], p[1]);
      expect(perp, closeTo(0, 0.5));
      expect(t.progress.alongM, closeTo(200, 0.5));
      expect(t.progress.offRouteM, closeTo(0, 0.5));
    });

    test('off-route after N consecutive bad observations, then recovers', () {
      final config = const RouteConfig(offRouteM: 20, offRouteObservations: 3);
      final t = RouteTracker(_straightRoute(), config: config);
      final badPoint = pointAt(100, 200); // 100 m off the route

      for (var i = 0; i < 2; i++) {
        t.observe(badPoint[0], badPoint[1]);
        expect(t.isOffRoute, isFalse, reason: 'not yet $i+1 consecutive');
      }
      t.observe(badPoint[0], badPoint[1]);
      expect(t.isOffRoute, isTrue);

      final goodPoint = pointAt(0, 300);
      t.observe(goodPoint[0], goodPoint[1]);
      expect(t.isOffRoute, isFalse, reason: 'a good fix resets the streak');
    });

    test('does not jump onto a spatially-close but far-away loop stretch', () {
      const config = RouteConfig(
        observeWindowBackM: 50,
        observeWindowForwardM: 100,
        offRouteM: 30,
      );
      final t = RouteTracker(_loopRoute(), config: config);
      final onFirstLeg = pointAt(500, 0);
      // Lock progress onto the middle of the first leg (500 m in).
      expect(t.lockAt(onFirstLeg[0], onFirstLeg[1], headingDeg: 0), isTrue);

      // The loop returns exactly to (0, 0) at the very end (alongM ~ 4000),
      // which is far outside the observe window around alongM 500 — the
      // query point below is exactly on the route's start/end coincidence.
      final query = pointAt(0, 0);
      t.observe(query[0], query[1]);

      expect(t.progress.alongM, lessThan(700),
          reason: 'must resolve near the current leg, not the loop closure');
    });
  });

  group('RouteTracker progress', () {
    test('next maneuver and distance update as the vehicle advances', () {
      final t = RouteTracker(_bentRoute());
      final start = pointAt(0, 0);
      t.lockAt(start[0], start[1], headingDeg: 90);

      t.advance(400);
      var progress = t.progress;
      expect(progress.next?.kind, ManeuverKind.left);
      expect(progress.distanceToNextM, closeTo(100, 0.5));

      t.advance(200); // now at 600 m, past the bend (500) + maneuverPassedM
      progress = t.progress;
      expect(progress.next?.kind, ManeuverKind.arrive);
      expect(progress.distanceToNextM, closeTo(400, 0.5));
    });
  });
}
