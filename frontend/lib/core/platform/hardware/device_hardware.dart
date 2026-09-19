/// Phone hardware services the session needs beyond the IMU: thermal reading
/// and haptics.
abstract class DeviceHardware {
  void start();
  void stop();

  double get currentTemperature;
  double get thermalBiasCorrection;
  Stream<double> get temperatureStream;

  Future<void> vibrate({int durationMs = 200, int amplitude = 255});
  Future<void> triggerOutageAlarmVibration();
  Future<void> triggerRoadAnomalyVibration(bool isPothole);

  /// Holds the screen awake, or releases it.
  ///
  /// Needed because the app stops sensors and GPS when it is backgrounded, and
  /// a screen timeout backgrounds it — so a recorded drive would simply stop
  /// partway. Only held while something actually needs it.
  Future<void> setKeepScreenOn(bool on);
}
