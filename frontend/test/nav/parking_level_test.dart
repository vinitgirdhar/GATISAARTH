import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/sensors/parking_level.dart';

void main() {
  test('nothing is tracked before GNSS is lost', () {
    final t = ParkingLevelTracker();
    expect(t.update(-6), isNull);
  });

  test('driving down two ramps is B2, back up is the entry level', () {
    final t = ParkingLevelTracker()..markEntry(12.0);
    expect(t.update(12.4)!.label, 'Entry level');
    expect(t.update(8.9)!.label, 'B1');
    expect(t.update(5.8)!.level, -2);
    expect(t.current!.label, 'B2');
    expect(t.update(11.9)!.label, 'Entry level');
  });

  test('a wobble around half a floor never flips the level', () {
    final t = ParkingLevelTracker()..markEntry(0);
    for (final h in [-1.4, -1.7, -1.5, -1.8, -1.6]) {
      expect(t.update(h)!.level, 0);
    }
  });

  test('upper decks count up', () {
    final t = ParkingLevelTracker()..markEntry(0);
    expect(t.update(3.2)!.label, 'L1');
  });

  test('clear forgets the car park', () {
    final t = ParkingLevelTracker()..markEntry(0);
    t.update(-3.3);
    t.clear();
    expect(t.current, isNull);
    expect(t.isTracking, isFalse);
  });
}
