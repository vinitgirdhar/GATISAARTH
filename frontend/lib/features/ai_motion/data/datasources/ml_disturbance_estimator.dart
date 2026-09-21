import 'dart:math' as math;

import '../../../../core/nav/ai/ai_types.dart';
import '../../domain/disturbance_model.dart';
import '../../domain/imu_feature_window.dart';
import 'tflite_asset.dart';
import 'tflite_window_model.dart';

/// Vibration classifier and motion-quality model (`VibrationClassifierNet`,
/// `MotionQualityNet`, `ml/README.md`): the same 10 Hz `[1, 20, 13]` window and
/// scaler as the speed model, read by two small networks.
///
/// **The assets in the repository are still Git-LFS pointers**, so today this
/// loads nothing, says why ([statusDetail]) and returns null from [addFrame];
/// the engine then runs its own statistical estimate. Nothing here can throw at
/// the session: a missing, placeholder, corrupt or integer-quantised model, and
/// a model that starts failing mid-drive, all end the same way (null, and after
/// [maxConsecutiveFailures] the models are released).
///
/// Outputs, by tensor size, since a TFLite export does not promise an order:
/// the vibration model's 3-element output is `[LOW, NORMAL, HIGH]` (logits or
/// probabilities: softmaxed unless they already sum to one) and its 1-element
/// output the vibration score in [0, 1]; the motion-quality model's single
/// element is the quality in [0, 1].
class MlDisturbanceEstimator implements DisturbanceModel {
  MlDisturbanceEstimator({
    WindowModelLoader? loader,
    this.vibrationAsset = 'assets/models/vibration_classifier_int8.tflite',
    this.qualityAsset = 'assets/models/motion_quality_int8.tflite',
    this.minFrames = 10,
    this.maxConsecutiveFailures = 5,
  }) : _loader = loader ?? loadWindowModelFromAsset;

  final WindowModelLoader _loader;
  final String vibrationAsset;
  final String qualityAsset;

  /// Frames the window needs before the models are asked (1 s at 10 Hz, like
  /// the speed model).
  final int minFrames;
  final int maxConsecutiveFailures;

  final ImuFeatureWindow _window = ImuFeatureWindow();
  WindowModel? _vibration;
  WindowModel? _quality;
  AssetState _vibrationState = AssetState.missing;
  AssetState _qualityState = AssetState.missing;
  bool _initialised = false;
  int _failures = 0;
  int _estimates = 0;

  /// Inferences that produced an estimate, for the diagnostics.
  int get estimateCount => _estimates;

  /// Consecutive failed inferences; reset by a good one.
  int get consecutiveFailures => _failures;

  @override
  bool get isModelLoaded => _vibration != null && _quality != null;

  @override
  String get statusDetail {
    if (!_initialised) return 'not started';
    if (isModelLoaded) return 'loaded';
    return 'vibration: ${_vibrationState.label}; '
        'motion quality: ${_qualityState.label}';
  }

  @override
  Future<void> initialize() async {
    if (_initialised) return;
    _initialised = true;
    final vibration = await _loader(vibrationAsset);
    final quality = await _loader(qualityAsset);
    _vibrationState = vibration.state;
    _qualityState = quality.state;
    // All or nothing: one real model and one placeholder would mean a
    // vibration score with no quality (or the reverse), and inventing the
    // missing half is exactly what the statistical fallback exists to do.
    if (vibration.model != null && quality.model != null) {
      _vibration = vibration.model;
      _quality = quality.model;
    } else {
      vibration.model?.close();
      quality.model?.close();
    }
  }

  @override
  void reset() {
    _window.reset();
    _failures = 0;
  }

  @override
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
  }) {
    _window.add(
        ax: ax,
        ay: ay,
        az: az,
        gx: gx,
        gy: gy,
        gz: gz,
        pitch: pitch,
        roll: roll);
    final vibration = _vibration;
    final quality = _quality;
    if (vibration == null || quality == null) return null;
    if (_window.length < minFrames) return null;

    final frames = _window.frames;
    final estimate = _estimate(
      vibration.run(frames),
      quality.run(frames),
      monotonicUs,
    );
    if (estimate == null) {
      if (++_failures >= maxConsecutiveFailures) _release();
      return null;
    }
    _failures = 0;
    _estimates++;
    return estimate;
  }

  void _release() {
    _vibration?.close();
    _quality?.close();
    _vibration = null;
    _quality = null;
    _vibrationState = AssetState.invalid;
    _qualityState = AssetState.invalid;
  }

  /// Turns the two models' raw outputs into an estimate, or null when either
  /// gave nothing usable (no output, non-finite, wrong size).
  static DisturbanceEstimate? _estimate(
    List<List<double>>? vibrationOut,
    List<List<double>>? qualityOut,
    int monotonicUs,
  ) {
    final v = parseVibration(vibrationOut);
    final q = parseQuality(qualityOut);
    if (v == null || q == null) return null;
    return DisturbanceEstimate(
      vibrationScore: v.score,
      vibrationClass: v.vibrationClass,
      motionQuality: q,
      monotonicUs: monotonicUs,
      source: EstimateSource.model,
    );
  }

  /// The vibration model's outputs: the class and the score, or null.
  static ({DisturbanceClass vibrationClass, double score})? parseVibration(
      List<List<double>>? outputs) {
    if (outputs == null) return null;
    List<double>? classes;
    double? score;
    for (final out in outputs) {
      if (out.any((x) => !x.isFinite)) return null;
      if (out.length == 3) classes = _probabilities(out);
      if (out.length == 1) score = out.first.clamp(0.0, 1.0);
    }
    if (classes == null) return null;
    var best = 0;
    for (var i = 1; i < 3; i++) {
      if (classes[i] > classes[best]) best = i;
    }
    // No score head: the expected class, spread over [0, 1] (low 0, normal
    // 0.5, high 1). A class-only export still says how bad, more or less.
    score ??= (classes[1] * 0.5 + classes[2]).clamp(0.0, 1.0);
    return (vibrationClass: DisturbanceClass.values[best], score: score);
  }

  /// The motion-quality model's output in [0, 1], or null.
  static double? parseQuality(List<List<double>>? outputs) {
    if (outputs == null) return null;
    for (final out in outputs) {
      if (out.length == 1 && out.first.isFinite) {
        return out.first.clamp(0.0, 1.0);
      }
    }
    return null;
  }

  /// Class scores as probabilities: as given when they already are (non-negative
  /// and summing to one), softmaxed otherwise.
  static List<double> _probabilities(List<double> raw) {
    final sum = raw.fold(0.0, (a, b) => a + b);
    if (raw.every((x) => x >= 0) && (sum - 1).abs() < 1e-3) return raw;
    final top = raw.reduce(math.max);
    final exps = [for (final x in raw) math.exp(x - top)];
    final total = exps.fold(0.0, (a, b) => a + b);
    return [for (final e in exps) e / total];
  }
}
