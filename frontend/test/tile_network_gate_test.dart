import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/maps/offline_tile_provider.dart';

void main() {
  late DateTime now;
  late TileNetworkGate gate;

  void advance(Duration d) => now = now.add(d);

  setUp(() {
    now = DateTime.utc(2026, 1, 1);
    gate = TileNetworkGate(clock: () => now);
  });

  test('is open initially', () {
    expect(gate.canAttempt, isTrue);
  });

  test('closes for 60 s after a failure', () {
    gate.recordFailure();

    expect(gate.canAttempt, isFalse);
    advance(const Duration(seconds: 59, milliseconds: 999));
    expect(gate.canAttempt, isFalse);
  });

  test('reopens once 60 s have passed', () {
    gate.recordFailure();
    advance(const Duration(seconds: 60));

    expect(gate.canAttempt, isTrue);
  });

  test('a success re-opens it immediately', () {
    gate.recordFailure();
    gate.recordSuccess();

    expect(gate.canAttempt, isTrue);
  });

  test('repeated failures restart the cooldown from the latest one only', () {
    gate.recordFailure();
    advance(const Duration(seconds: 30));
    gate.recordFailure(); // reopens at t=90 s, not later

    advance(const Duration(seconds: 59, milliseconds: 999));
    expect(gate.canAttempt, isFalse);
    advance(const Duration(milliseconds: 1));
    expect(gate.canAttempt, isTrue);
  });

  test('a clock that jumps backwards does not keep it closed', () {
    gate.recordFailure();
    advance(const Duration(hours: -1));

    expect(gate.canAttempt, isTrue);
  });

  test('closes again after re-opening if the next attempt fails', () {
    gate.recordFailure();
    advance(TileNetworkGate.cooldown);
    expect(gate.canAttempt, isTrue);

    gate.recordFailure();
    expect(gate.canAttempt, isFalse);
  });
}
