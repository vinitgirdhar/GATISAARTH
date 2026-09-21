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

  /// True once the initialization attempt has finished (either loaded or fallback active).
  bool get isReady;

  /// Drop the temporal window (used when the estimator has been idle).
  void reset();

  /// What the navigation engine's AI speed gate needs from the last **neural**
  /// inference. None of it is meaningful before [neuralInferenceCount] is above
  /// zero, and none of it ever comes from the heuristic fallback.
  ///
  /// [modelSpeed] is the model's raw speed head (m/s) *without* the stillness
  /// gate [estimatedSpeed] applies (that gate is variance-only and reads a
  /// smooth cruise as a stop, which is exactly what the AI measurement must not
  /// inherit). [sigma] is its predicted standard deviation, [featureZMax] the
  /// largest |z-score| of the input window, [windowsFed] the frames fed since
  /// the estimator last restarted.
  double get modelSpeed;
  double get sigma;
  double get featureZMax;
  int get windowsFed;

  /// Counts neural inferences (never fallback ones): a change means a new
  /// output to hand to the engine.
  int get neuralInferenceCount;
}
