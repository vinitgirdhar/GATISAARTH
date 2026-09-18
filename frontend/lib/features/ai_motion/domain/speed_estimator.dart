/// Estimates vehicle speed from a stream of IMU frames.
abstract class SpeedEstimator {
  Future<void> initialize();

  /// Feed one sensor frame; returns the latest speed estimate in m/s.
  /// Accelerations in m/s², rates in rad/s, angles in radians.
  double addImuFrame({
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required double pitch,
    required double roll,
  });

  double get estimatedSpeed;

  /// Model-reported confidence and latency of the last *neural* inference.
  /// Only meaningful once [hasModelInference] is true.
  double get confidence;
  int get latencyMs;

  /// True once the neural model has actually run (not the stationary gate or
  /// the heuristic fallback).
  bool get hasModelInference;

  /// True when the neural model file was found and loaded. When false the
  /// estimator uses a rule-based fallback.
  bool get isModelLoaded;

  /// Drop the temporal window (used when the estimator has been idle).
  void reset();
}
