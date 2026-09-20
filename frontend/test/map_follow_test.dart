import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/map_follow.dart';

void main() {
  group('autoZoomForSpeed', () {
    test('is closest when parked and never leaves the street range', () {
      expect(autoZoomForSpeed(0), 17.6);
      expect(autoZoomForSpeed(-3), 17.6);
      expect(autoZoomForSpeed(double.nan), 17.6);
      expect(autoZoomForSpeed(500), 15.4);
    });

    test('only ever zooms out as speed rises', () {
      var previous = autoZoomForSpeed(0);
      for (var v = 0.5; v <= 40; v += 0.5) {
        final z = autoZoomForSpeed(v);
        expect(z, lessThanOrEqualTo(previous + 1e-12), reason: 'at $v m/s');
        previous = z;
      }
    });

    test('is continuous: no step between neighbouring speeds', () {
      for (var v = 0.0; v < 40; v += 0.1) {
        expect(
          (autoZoomForSpeed(v + 0.1) - autoZoomForSpeed(v)).abs(),
          lessThan(0.06),
        );
      }
    });

    test('stays inside the map zoom limits', () {
      for (var v = 0.0; v <= 60; v += 1) {
        final z = autoZoomForSpeed(v);
        expect(z, inInclusiveRange(MapZoom.min, MapZoom.max));
      }
    });
  });

  group('shortestAngleDelta', () {
    test('goes the short way across north', () {
      expect(shortestAngleDelta(350, 10), closeTo(20, 1e-9));
      expect(shortestAngleDelta(10, 350), closeTo(-20, 1e-9));
    });

    test('is zero for equal angles, also a full turn apart', () {
      expect(shortestAngleDelta(90, 90), 0);
      expect(shortestAngleDelta(90, 450), closeTo(0, 1e-9));
      expect(shortestAngleDelta(-90, 270), closeTo(0, 1e-9));
    });

    test('a half turn is +180, not -180', () {
      expect(shortestAngleDelta(0, 180), 180);
      expect(shortestAngleDelta(180, 0), 180);
    });
  });

  group('Ease', () {
    test('converges to the target and reports when it has arrived', () {
      final e = Ease(0, tau: 0.2)..target = 10;
      var steps = 0;
      while (e.step(1 / 60)) {
        steps++;
        expect(steps, lessThan(600), reason: 'must arrive');
      }
      expect(e.value, 10);
      expect(e.settled, isTrue);
    });

    test('never overshoots', () {
      final e = Ease(0, tau: 0.1)..target = 5;
      for (var i = 0; i < 200; i++) {
        e.step(0.05);
        expect(e.value, lessThanOrEqualTo(5));
      }
    });

    test('does not depend on the frame rate', () {
      final coarse = Ease(0, tau: 0.3)..target = 100;
      final fine = Ease(0, tau: 0.3)..target = 100;
      coarse.step(0.3);
      for (var i = 0; i < 30; i++) {
        fine.step(0.01);
      }
      expect(coarse.value, closeTo(fine.value, 1e-9));
      // After one time constant, 1 - 1/e of the way there.
      expect(coarse.value, closeTo(100 * (1 - 0.36787944117), 1e-6));
    });

    test('snap jumps to the target at once', () {
      final e = Ease(0, tau: 1)..target = 42;
      e.snap();
      expect(e.value, 42);
      expect(e.step(0.016), isFalse);
    });
  });

  group('AngleEase', () {
    test('turns through north the short way', () {
      final a = AngleEase(350, tau: 0.1)..aim(10);
      expect(a.target, closeTo(370, 1e-9));
      for (var i = 0; i < 300; i++) {
        a.step(0.02);
        expect(a.value, inInclusiveRange(350, 370));
      }
      expect(a.value, closeTo(370, 0.05));
    });

    test('keeps taking the short way after several turns', () {
      final a = AngleEase(0, tau: 0.05);
      for (final heading in [90.0, 180.0, 270.0, 359.0, 1.0]) {
        a.aim(heading);
        while (a.step(0.02)) {}
        expect(shortestAngleDelta(a.value, heading).abs(), lessThan(0.05));
      }
    });
  });

  test('the heading lookahead scales with the map and stays below half', () {
    expect(headingLookaheadPx(600), 120);
    expect(headingLookaheadPx(1000), lessThan(500));
  });
}
