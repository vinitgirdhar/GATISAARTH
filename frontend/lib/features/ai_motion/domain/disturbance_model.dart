import '../../../core/nav/ai/ai_types.dart';

/// The vibration and motion-quality models, seen from the session: a window of
/// 10 Hz IMU frames in, a [DisturbanceEstimate] out.
///
/// It only ever returns what a neural model produced. While the model assets
/// are placeholders (or fail), [addFrame] returns null and the engine's own
/// statistical estimator carries on: a fallback that is never presented as AI.
abstract class DisturbanceModel {
  Future<void> initialize();

  /// True when both models loaded and are running.
  bool get isModelLoaded;

  /// Why they are not, in a line ("vibration: placeholder (Git-LFS pointer)"),
  /// or "loaded".
  String get statusDetail;

  /// Feeds one 10 Hz frame (accelerometer raw, gravity included) and returns a
  /// fresh estimate stamped [monotonicUs], or null when there is none (models
  /// not loaded, window not warm, or inference failed).
  DisturbanceEstimate? addFrame({
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required double pitch,
    required double roll,
    required int monotonicUs,
  });

  void reset();
}
