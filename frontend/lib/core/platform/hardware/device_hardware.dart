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
}
