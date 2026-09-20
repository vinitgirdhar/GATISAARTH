import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';

import 'support/session_fakes.dart';

void main() {
  late FakeHardware hardware;
  late DateTime now;
  late Haptics haptics;

  setUp(() {
    hardware = FakeHardware();
    now = DateTime(2026, 9, 20, 12);
    haptics = Haptics(hardware, clock: () => now, pause: (_) async {});
  });

  test('a GNSS outage is a double pulse', () async {
    await haptics.fire(HapticEvent.outageStarted);
    expect(hardware.vibrations, [250, 350]);
  });

  test('start is one short tick and stop is two', () async {
    await haptics.fire(HapticEvent.recordingStarted);
    expect(hardware.vibrations, [60]);
    now = now.add(const Duration(seconds: 5));
    await haptics.fire(HapticEvent.recordingStopped);
    expect(hardware.vibrations, [60, 60, 60]);
  });

  test('nothing vibrates when the user has switched haptics off', () async {
    haptics.enabled = false;
    await haptics.fire(HapticEvent.outageStarted);
    await haptics.fire(HapticEvent.recordingStarted);
    await haptics.fire(HapticEvent.recordingStopped);
    expect(hardware.vibrations, isEmpty);
  });

  test('a flapping GNSS signal cannot buzz the phone repeatedly', () async {
    await haptics.fire(HapticEvent.outageStarted);
    now = now.add(const Duration(seconds: 30));
    await haptics.fire(HapticEvent.outageStarted); // too soon
    expect(hardware.vibrations.length, 2);

    now = now.add(const Duration(seconds: 20)); // 50 s since the first
    await haptics.fire(HapticEvent.outageStarted);
    expect(hardware.vibrations.length, 4);
  });

  test('a double-tapped Record button ticks once', () async {
    await haptics.fire(HapticEvent.recordingStarted);
    now = now.add(const Duration(milliseconds: 300));
    await haptics.fire(HapticEvent.recordingStarted);
    expect(hardware.vibrations, [60]);
  });

  test('an outage alert stays silent while a drive is being recorded',
      () async {
    await haptics.fire(HapticEvent.outageStarted, recording: true);
    expect(hardware.vibrations, isEmpty);
    // ...and the cool-down was not spent on the alert that never fired.
    await haptics.fire(HapticEvent.outageStarted);
    expect(hardware.vibrations, [250, 350]);
  });

  test('the recording ticks are not silenced by recording', () async {
    await haptics.fire(HapticEvent.recordingStopped, recording: true);
    expect(hardware.vibrations, [60, 60]);
  });
}
