import '../../../core/nav/ai/ai_types.dart';
import 'disturbance_model.dart';
import 'speed_estimator.dart';

/// What the models have to say to the navigation engine right now.
class AiOutputs {
  const AiOutputs({this.speed, this.disturbance, this.fusion});

  static const AiOutputs none = AiOutputs();

  final AiSpeedObservation? speed;
  final DisturbanceEstimate? disturbance;
  final FusionConfidence? fusion;

  bool get isEmpty => speed == null && disturbance == null && fusion == null;
}

/// The seam between the on-device models and the engine's AI inputs (P1-P3).
///
/// After each model tick the session asks [poll] for whatever is *new*: a speed
/// observation for each fresh **neural** inference, and a disturbance estimate
/// (with the fusion confidence derived from it) for each fresh reading of the
/// vibration and motion-quality models. Only genuine model output ever comes
/// out: an estimator running its heuristic fallback, and a placeholder asset,
/// produce nothing. The session hands the result to the engine and to the drive
/// recorder, in that one place, so the two cannot disagree.
class AiEngineFeed {
  AiEngineFeed({required SpeedEstimator speed, DisturbanceModel? disturbance})
      : _speed = speed,
        _disturbance = disturbance;

  final SpeedEstimator _speed;
  final DisturbanceModel? _disturbance;

  int _lastInference = 0;
  DisturbanceEstimate? _pendingDisturbance;

  /// Feeds the disturbance models the same 10 Hz frame the speed model got and
  /// keeps their answer for the next [poll].
  void addFrame({
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required double pitch,
    required double roll,
    required int monotonicUs,
  }) {
    final estimate = _disturbance?.addFrame(
      ax: ax,
      ay: ay,
      az: az,
      gx: gx,
      gy: gy,
      gz: gz,
      pitch: pitch,
      roll: roll,
      monotonicUs: monotonicUs,
    );
    if (estimate != null) _pendingDisturbance = estimate;
  }

  /// New model outputs since the last call, stamped [monotonicUs] (the IMU time
  /// of the frame the engine has just processed).
  AiOutputs poll(int monotonicUs) {
    AiSpeedObservation? speed;
    final count = _speed.neuralInferenceCount;
    if (count != _lastInference) {
      _lastInference = count;
      if (_speed.hasModelInference && _speed.isModelLoaded) {
        speed = AiSpeedObservation(
          speedMps: _speed.modelSpeed,
          sigmaMps: _speed.sigma,
          monotonicUs: monotonicUs,
          latencyMs: _speed.latencyMs.toDouble(),
          featureZMax: _speed.featureZMax,
          windowsFed: _speed.windowsFed,
        );
      }
    }

    final pending = _pendingDisturbance;
    _pendingDisturbance = null;
    DisturbanceEstimate? disturbance;
    FusionConfidence? fusion;
    if (pending != null) {
      disturbance = DisturbanceEstimate(
        vibrationScore: pending.vibrationScore,
        vibrationClass: pending.vibrationClass,
        motionQuality: pending.motionQuality,
        monotonicUs: monotonicUs,
        shock: pending.shock,
      );
      // INS trust *is* the motion quality here (the model's own statement of how
      // far the inertial data can be believed); the engine uses it in place of
      // the quality in the process-noise factor, so it is not counted twice.
      // There is no GNSS anomaly model on the phone yet, so GNSS trust stays 1.
      fusion = FusionConfidence(
        insTrust: pending.motionQuality,
        monotonicUs: monotonicUs,
      );
    }
    if (speed == null && disturbance == null) return AiOutputs.none;
    return AiOutputs(speed: speed, disturbance: disturbance, fusion: fusion);
  }

  void reset() {
    _pendingDisturbance = null;
    _disturbance?.reset();
  }
}
