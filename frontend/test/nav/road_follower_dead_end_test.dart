import 'package:flutter_test/flutter_test.dart';

import 'support/road_follower_fixtures.dart';

/// A real vehicle that runs out of map has left it, so the follower waits at
/// the end. A simulated drive (the tunnel test, the urban canyon) must keep
/// going: stopping at the end of the first cul-de-sac looks like a broken demo.
void main() {
  // One 100 m two-way street running east from the origin, nothing beyond.
  final stub = graphOf([
    road(1, [
      [0, 0],
      [0, 100],
    ]),
  ]);

  group('a dead end', () {
    test('stops a real drive at the end and says how far it got', () {
      final f = lockedAt(stub, 0, 80, heading: 90);
      expect(f.advance(50), closeTo(20, 0.01));
      expectAt(f, 0, 100);
      expect(f.advance(10), 0, reason: 'still waiting for more map');
    });

    test('turns a simulated drive round and drives back', () {
      final f = lockedAt(stub, 0, 80, heading: 90);
      expect(f.advance(50, reverseAtDeadEnd: true), closeTo(50, 0.01));
      expectAt(f, 0, 70);
      expectHeading(f, 270);
    });

    test('a simulated drive bounces for as long as it is asked to', () {
      final f = lockedAt(stub, 0, 10, heading: 90);
      var travelled = 0.0;
      for (var i = 0; i < 2000; i++) {
        travelled += f.advance(1, reverseAtDeadEnd: true);
      }
      expect(travelled, closeTo(2000, 0.5));
      final o = offsetOf(f.position!);
      expect(o.e, inInclusiveRange(-0.5, 100.5));
      expect(o.n, closeTo(0, 0.5));
    });

    test('cannot reverse on a one-way street, simulated or not', () {
      final oneWay = graphOf([
        road(
            1,
            [
              [0, 0],
              [0, 100],
            ],
            oneWay: true),
      ]);
      final f = lockedAt(oneWay, 0, 80, heading: 90);
      expect(f.advance(50, reverseAtDeadEnd: true), closeTo(20, 0.01));
      expectHeading(f, 90);
    });

    test('drives back out onto the road it came in from', () {
      // The stub joins a longer street at its west end.
      final g = graphOf([
        road(1, [
          [0, -300],
          [0, 0],
        ]),
        road(2, [
          [0, 0],
          [0, 100],
        ]),
      ]);
      final f = lockedAt(g, 0, 80, heading: 90);
      // 20 m to the dead end, 100 m back to the join, then on along road 1.
      expect(f.advance(220, reverseAtDeadEnd: true), closeTo(220, 0.01));
      expectAt(f, 0, -100);
      expectHeading(f, 270);
    });
  });
}
