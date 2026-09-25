/// Which phone this is, for the header of a drive log: results only mean
/// something next to the phone that produced them.
class DeviceInfo {
  const DeviceInfo({required this.model, required this.os});

  /// Manufacturer and model, e.g. "Google Pixel 9".
  final String model;

  /// e.g. "Android 15 (API 35)".
  final String os;
}

/// Phone hardware services the session needs beyond the IMU: a temperature
/// reading and haptics.
abstract class DeviceHardware {
  void start();
  void stop();

  /// Battery temperature in °C (the closest reading Android gives to the IMU's
  /// own), or null until the phone has reported one. Never a made-up default.
  double? get currentTemperature;
  Stream<double> get temperatureStream;

  /// One vibration. Only `Haptics` calls this: it holds the whole policy for
  /// when the phone may buzz.
  Future<void> vibrate({int durationMs = 200, int amplitude = 255});

  /// Holds the screen awake, or releases it.
  ///
  /// Needed because the app stops sensors and GPS when it is backgrounded, and
  /// a screen timeout backgrounds it — so a recorded drive would simply stop
  /// partway. Only held while something actually needs it.
  Future<void> setKeepScreenOn(bool on);

  /// The phone's model and OS, or null when the platform cannot say.
  Future<DeviceInfo?> deviceInfo();
}
