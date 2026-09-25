/// Source of raw motion frames for a live session.
///
/// Frame layout (see `MobileSensorDriver`):
/// `[ax, ay, az, gx, gy, gz, tSeconds, mx, my, mz, pressureHpa, pressureAltM]`.
abstract class HardwareSensorInterface {
  /// One frame per accelerometer sample.
  Stream<List<double>> get imuStream;

  /// Starts every sensor; calling it twice is harmless.
  void start();

  /// Stops every sensor (the app is backgrounded or the session ends).
  void stop();
}
