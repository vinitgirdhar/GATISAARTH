import 'device_hardware.dart';

/// The only moments the app may vibrate the phone. Adding one is a product
/// decision, not a convenience: a phone that buzzes freely is a phone that
/// cannot be trusted to buzz when it matters.
enum HapticEvent {
  /// Navigation just fell back to dead reckoning because GNSS was lost. The
  /// rider is not looking at the screen; this is the one alert that is.
  outageStarted,

  /// A drive recording began. Confirms a tap the user often cannot see.
  recordingStarted,

  /// A drive recording ended and the file is closed.
  recordingStopped,
}

/// The vibration policy, in one place. Nothing else in the app calls the
/// phone's vibrator.
///
/// What is deliberately *not* here: bump and pothole detection (false alarms
/// on any rough road or in a hand, and a shaking phone shakes its own
/// accelerometer), button taps (the OS already gives touch feedback), and
/// recovery of GNSS (good news can wait for the screen).
class Haptics {
  Haptics(
    this._hardware, {
    DateTime Function()? clock,
    Future<void> Function(Duration)? pause,
  })  : _clock = clock ?? DateTime.now,
        _pause = pause ?? Future<void>.delayed;

  final DeviceHardware _hardware;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _pause;

  /// The user's switch (Profile > Haptic alerts). Off means nothing vibrates.
  bool enabled = true;

  /// Minimum gap between two of the same event. GNSS flaps in urban canyons,
  /// and a double-tapped Record button must not buzz twice.
  static const Map<HapticEvent, Duration> _cooldown = {
    HapticEvent.outageStarted: Duration(seconds: 45),
    HapticEvent.recordingStarted: Duration(milliseconds: 1500),
    HapticEvent.recordingStopped: Duration(milliseconds: 1500),
  };

  final Map<HapticEvent, DateTime> _lastFired = {};

  /// Fires [event] if the policy allows it. [recording] says a drive is being
  /// recorded right now: a vibrating phone corrupts the accelerometer trace it
  /// is recording, so an outage alert (which lands exactly where dead
  /// reckoning is being measured) stays silent then. The start and stop ticks
  /// are outside the recorded stretch.
  Future<void> fire(HapticEvent event, {bool recording = false}) async {
    if (!enabled) return;
    if (recording && event == HapticEvent.outageStarted) return;

    final now = _clock();
    final last = _lastFired[event];
    if (last != null && now.difference(last) < _cooldown[event]!) return;
    _lastFired[event] = now;

    switch (event) {
      case HapticEvent.outageStarted:
        await _hardware.vibrate(durationMs: 250, amplitude: 255);
        await _pause(const Duration(milliseconds: 150));
        await _hardware.vibrate(durationMs: 350, amplitude: 255);
      case HapticEvent.recordingStarted:
        await _hardware.vibrate(durationMs: 60, amplitude: 160);
      case HapticEvent.recordingStopped:
        await _hardware.vibrate(durationMs: 60, amplitude: 160);
        await _pause(const Duration(milliseconds: 120));
        await _hardware.vibrate(durationMs: 60, amplitude: 160);
    }
  }
}
