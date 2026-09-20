import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/track_trail.dart';

/// ~1 m of latitude.
const double _m = 1 / 111320.0;

void main() {
  test('points closer than the step are dropped', () {
    final t = TrackTrail(minStepMeters: 4);
    expect(t.add(28.0, 77.0, TrailKind.gnss), isTrue);
    expect(t.add(28.0 + 2 * _m, 77.0, TrailKind.gnss), isFalse);
    expect(t.add(28.0 + 5 * _m, 77.0, TrailKind.gnss), isTrue);
    expect(t.length, 2);
  });

  test('a single point draws nothing yet', () {
    final t = TrackTrail()..add(28.0, 77.0, TrailKind.gnss);
    expect(t.segments, isEmpty);
    expect(t.isEmpty, isFalse);
  });

  test('a change of source starts a new segment that joins the old one', () {
    final t = TrackTrail(minStepMeters: 4)
      ..add(28.0, 77.0, TrailKind.gnss)
      ..add(28.0 + 10 * _m, 77.0, TrailKind.gnss)
      ..add(28.0 + 20 * _m, 77.0, TrailKind.deadReckoning)
      ..add(28.0 + 30 * _m, 77.0, TrailKind.deadReckoning)
      ..add(28.0 + 40 * _m, 77.0, TrailKind.gnss);

    final s = t.segments;
    expect(s.map((e) => e.kind), [
      TrailKind.gnss,
      TrailKind.deadReckoning,
      TrailKind.gnss,
    ]);
    // Each run starts exactly where the previous one ended: no gap.
    expect(s[1].points.first, s[0].points.last);
    expect(s[2].points.first, s[1].points.last);
  });

  test('the trail is capped and drops its oldest points', () {
    final t = TrackTrail(minStepMeters: 4, maxPoints: 50);
    for (var i = 0; i < 400; i++) {
      t.add(28.0 + i * 6 * _m, 77.0, TrailKind.gnss);
    }
    expect(t.length, lessThanOrEqualTo(50));
    final pts = t.segments.single.points;
    // The newest point is the one just added.
    expect(pts.last.latitude, closeTo(28.0 + 399 * 6 * _m, 1e-9));
  });

  test('segments are stable until the trail changes, then a new object', () {
    final t = TrackTrail(minStepMeters: 4)
      ..add(28.0, 77.0, TrailKind.gnss)
      ..add(28.0 + 10 * _m, 77.0, TrailKind.gnss);
    final first = t.segments;
    expect(identical(first, t.segments), isTrue);
    t.add(28.0 + 20 * _m, 77.0, TrailKind.gnss);
    expect(identical(first, t.segments), isFalse);
  });

  test('clear empties the trail and notifies', () {
    final t = TrackTrail(minStepMeters: 4)
      ..add(28.0, 77.0, TrailKind.gnss)
      ..add(28.0 + 10 * _m, 77.0, TrailKind.gnss);
    var notified = 0;
    t.addListener(() => notified++);
    t.clear();
    expect(t.isEmpty, isTrue);
    expect(t.segments, isEmpty);
    expect(notified, 1);
    t.clear(); // already empty: no second notification
    expect(notified, 1);
  });
}
