import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../domain/imu_feature_window.dart';
import '../../domain/speed_estimator.dart';

/// On-device speed model: a float32 TFLite temporal-convolution network
/// (`ml/src/training/train_speed_v4.py`) that predicts vehicle speed (m/s) and
/// its log-variance from 13 IMU features.
///
/// The model was trained on 10 Hz data, so callers must feed one frame per
/// 0.1 s of raw accelerometer data (gravity included). The window therefore
/// covers 2 s.
class MlSpeedEstimator implements SpeedEstimator {
  static final MlSpeedEstimator _instance = MlSpeedEstimator._internal();
  factory MlSpeedEstimator() => _instance;
  MlSpeedEstimator._internal();

  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  bool _isLoading = false;
  bool _initialized = false;

  // Window size: 20 samples at 10 Hz (2 s temporal context)
  static const int windowSize = ImuFeatureWindow.size;
  static const int numFeatures = ImuFeatureWindow.features;

  /// The 13-feature, 20-frame window (shared with the other on-device models).
  final ImuFeatureWindow _window = ImuFeatureWindow();

  double _latestEstimatedSpeed = 0.0;
  double _latestConfidence = 0.0;
  int _latestInferenceLatencyMs = 0;

  // The last neural inference's raw outputs, for the navigation engine's AI
  // gate. Never set by the heuristic fallback.
  double _latestModelSpeed = 0.0;
  double _latestSigma = 0.0;
  double _latestFeatureZ = 0.0;
  int _neuralRuns = 0;

  // Normalization parameters from training dataset (model_metadata.json)
  static const List<double> scalerMean = ImuFeatureWindow.mean;
  static const List<double> scalerScale = ImuFeatureWindow.scale;

  @override
  double get estimatedSpeed => _latestEstimatedSpeed;
  @override
  double get confidence => _latestConfidence;
  @override
  int get latencyMs => _latestInferenceLatencyMs;

  /// True once the *neural* model has run. The heuristic fallback does not
  /// count: it is never presented as AI.
  @override
  bool get hasModelInference => _neuralRuns > 0;
  @override
  bool get isModelLoaded => _isModelLoaded;
  @override
  bool get isReady => _initialized;

  @override
  double get modelSpeed => _latestModelSpeed;
  @override
  double get sigma => _latestSigma;
  @override
  double get featureZMax => _latestFeatureZ;
  @override
  int get windowsFed => _window.fed;
  @override
  int get neuralInferenceCount => _neuralRuns;

  @override
  Future<void> initialize() async {
    if (_isModelLoaded || _isLoading) return;
    _isLoading = true;

    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/speed_estimator.tflite',
        options: options,
      );
      _isModelLoaded = true;
      debugPrint(
          '[MlSpeedEstimator] TFLite Speed Estimator model loaded successfully.');
    } catch (e) {
      debugPrint(
          '[MlSpeedEstimator] TFLite model not loaded, using the rule-based fallback: $e');
      _isModelLoaded = false;
    } finally {
      _isLoading = false;
      _initialized = true;
    }
  }

  /// Processes one 10 Hz frame and updates the estimated speed.
  /// [ax, ay, az] in m/s^2 (gravity included), [gx, gy, gz] in rad/s,
  /// [pitch, roll] in radians.
  @override
  double addImuFrame({
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required double pitch,
    required double roll,
  }) {
    _window.add(
      ax: ax,
      ay: ay,
      az: az,
      gx: gx,
      gy: gy,
      gz: gz,
      pitch: pitch,
      roll: roll,
    );

    // Run inference once we have enough temporal context
    if (_window.length >= windowSize) {
      _runInference();
    }

    return _latestEstimatedSpeed;
  }

  void _runInference() {
    final frames = _window.frames;

    // 1. Strict Zero-Velocity Update (ZUPT) Detection over temporal window
    double sumNormA = 0.0;
    double sumNormG = 0.0;

    for (final sample in frames) {
      sumNormA += ImuFeatureWindow.physical(sample, 6);
      sumNormG += ImuFeatureWindow.physical(sample, 7);
    }

    final meanNormA = sumNormA / frames.length;
    final meanNormG = sumNormG / frames.length;

    double varianceNormA = 0.0;
    for (final sample in frames) {
      final normA = ImuFeatureWindow.physical(sample, 6);
      varianceNormA += (normA - meanNormA) * (normA - meanNormA);
    }
    final stdNormA = sqrt(varianceNormA / frames.length);

    final interpreter = _interpreter;
    if (interpreter != null && _isModelLoaded) {
      try {
        final stopwatch = Stopwatch()..start();
        // Prepare tensor [1, 20, 13]
        final input = List.generate(
          1,
          (_) => List.generate(
            windowSize,
            (t) =>
                t < frames.length ? frames[t] : List.filled(numFeatures, 0.0),
          ),
        );

        final output = List.generate(
            1, (_) => List.filled(2, 0.0)); // [speed, log_variance]
        interpreter.run(input, output);
        stopwatch.stop();

        final rawSpeed = output[0][0];
        final variance = exp(output[0][1].clamp(-5.0, 5.0));
        final sigma = sqrt(variance);

        // When physical stillness is present, clamp to 0.0 with 98% confidence
        final isStationary = stdNormA < 0.40 && meanNormG < 0.25;
        if (isStationary) {
          _latestEstimatedSpeed = 0.0;
          _latestConfidence = 0.98;
        } else {
          _latestEstimatedSpeed = rawSpeed.clamp(0.0, 45.0);
          // Calibrated operational confidence using Gaussian Error Tolerance CDF:
          // P(|error| <= deltaV) = erf(deltaV / (sqrt(2) * sigma))
          // Operational tolerance: deltaV = 2.2 m/s (8.0 km/h)
          const double deltaV = 2.2;
          double conf = _erf(deltaV / (sqrt(2) * sigma));

          // Apply soft attenuation if features sit in the tail of the training distribution (zMax > 3.5)
          final zMax = _window.zMax;
          if (zMax > 3.5) {
            final penalty = exp(-0.5 * (zMax - 3.5));
            conf *= penalty;
          }
          _latestConfidence = conf.clamp(0.05, 0.99);
        }

        _latestInferenceLatencyMs =
            max(1, (stopwatch.elapsedMicroseconds / 1000).round());
        // The raw heads, without the stillness gate above: what the engine's AI
        // speed gate wants (a smooth cruise is not a stop).
        _latestModelSpeed = rawSpeed;
        _latestSigma = sigma;
        _latestFeatureZ = _window.zMax;
        _neuralRuns++;
        return;
      } catch (e) {
        debugPrint('[MlSpeedEstimator] inference failed, using fallback: $e');
      }
    }
    _latestEstimatedSpeed = _kinematicFallbackSpeed(frames, stdNormA);
    _latestConfidence = (stdNormA < 0.32 && meanNormG < 0.22) ? 0.99 : 0.85;
    _latestInferenceLatencyMs = 1;
  }

  /// Rule-based fallback used only when the TFLite model is unavailable. It is
  /// a heuristic, not a neural estimate, and is never reported as one.
  double _kinematicFallbackSpeed(List<List<double>> frames, double stdNormA) {
    if (frames.isEmpty || stdNormA < 0.32) return 0.0;

    double dynamicForwardEnergy = 0.0;

    for (final sample in frames) {
      final ax = ImuFeatureWindow.physical(sample, 0);
      final pitch = ImuFeatureWindow.physical(sample, 11);

      // Remove gravity projection: a_dyn_x = ax - g * sin(pitch)
      final gravityForward = 9.81 * sin(pitch);
      final dynamicAx = (ax - gravityForward).abs();

      if (dynamicAx > 0.35) {
        dynamicForwardEnergy += dynamicAx;
      }
    }

    final avgDynamicForward = dynamicForwardEnergy / frames.length;

    if (avgDynamicForward < 0.25 && stdNormA < 0.40) {
      return 0.0;
    }

    // Dynamic forward speed proportional to real physical kinetic energy
    final speed =
        (avgDynamicForward * 3.2 + (stdNormA - 0.32) * 1.8).clamp(0.0, 35.0);
    return speed > 0.3 ? speed : 0.0;
  }

  @override
  void reset() {
    _window.reset();
    _latestEstimatedSpeed = 0.0;
  }

  /// Numerical approximation of the error function erf(x)
  /// with maximum error < 1.5e-7 (Abramowitz and Stegun 7.1.26).
  static double _erf(double x) {
    final sign = x < 0 ? -1.0 : 1.0;
    final a = x.abs();
    const p = 0.3275911;
    const a1 = 0.254829592;
    const a2 = -0.284496736;
    const a3 = 1.421413741;
    const a4 = -1.453152027;
    const a5 = 1.061405429;
    final t = 1.0 / (1.0 + p * a);
    final y =
        1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-a * a);
    return sign * y;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
  }
}
