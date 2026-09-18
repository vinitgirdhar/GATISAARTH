import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../domain/speed_estimator.dart';

/// GatiSaarth Edge AI Speed Estimator
/// Uses PyTorch -> ONNX -> INT8 Quantized TFLite Neural Network
/// (1D-CNN + Residual Blocks + Bidirectional GRU + Heteroscedastic Head)
/// to predict instantaneous vehicle speed (m/s) from 13 IMU kinematic features.
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

  // Window size: 20 samples at 10 Hz (2 s temporal context)
  static const int windowSize = 20;
  static const int numFeatures = 13;

  final List<List<double>> _rollingWindow = [];
  double _lastAx = 0.0;
  double _lastAy = 0.0;
  double _lastAz = 9.81;

  double _latestEstimatedSpeed = 0.0;
  double _latestConfidence = 0.0;
  int _latestInferenceLatencyMs = 0;
  int _modelRuns = 0;

  // Normalization parameters from training dataset (model_metadata.json)
  static const List<double> scalerMean = [
    -0.006436917204641048,
    0.0015932520408620627,
    9.813988583580786,
    0.00029069510777557627,
    -2.6694672256006832e-05,
    -0.0005267534435531443,
    9.864373398724725,
    0.06743461390520612,
    0.0011695408378255905,
    0.0008564605232577426,
    0.0005478108230194564,
    -0.0006498998805616586,
    0.0001259820234195228,
  ];

  static const List<double> scalerScale = [
    0.9300446514524384,
    0.35982188347774474,
    0.12516862631115197,
    0.015818761262360623,
    0.015782822736439495,
    0.0725727892130425,
    0.13393944396405216,
    0.031940192383929776,
    0.668776417256872,
    0.40920679044616004,
    0.75133715827334,
    0.09464653315412107,
    0.0379910512759541,
  ];

  @override
  double get estimatedSpeed => _latestEstimatedSpeed;
  @override
  double get confidence => _latestConfidence;
  @override
  int get latencyMs => _latestInferenceLatencyMs;
  @override
  bool get hasModelInference => _modelRuns > 0;
  @override
  bool get isModelLoaded => _isModelLoaded;

  @override
  Future<void> initialize() async {
    if (_isModelLoaded || _isLoading) return;
    _isLoading = true;

    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/speed_estimator_int8.tflite',
        options: options,
      );
      _isModelLoaded = true;
      debugPrint('[MlSpeedEstimator] TFLite Speed Estimator model loaded successfully.');
    } catch (e) {
      debugPrint('[MlSpeedEstimator] TFLite model not loaded, using the rule-based fallback: $e');
      _isModelLoaded = false;
    } finally {
      _isLoading = false;
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
    final normA = sqrt(ax * ax + ay * ay + az * az);
    final normG = sqrt(gx * gx + gy * gy + gz * gz);
    final dax = ax - _lastAx;
    final day = ay - _lastAy;
    final daz = az - _lastAz;

    _lastAx = ax;
    _lastAy = ay;
    _lastAz = az;

    // Construct 13-feature vector
    final rawFeatures = [
      ax,
      ay,
      az,
      gx,
      gy,
      gz,
      normA,
      normG,
      dax,
      day,
      daz,
      pitch,
      roll,
    ];

    // Standardize features
    final normalized = List<double>.generate(numFeatures, (i) {
      final scale = scalerScale[i] == 0 ? 1.0 : scalerScale[i];
      return (rawFeatures[i] - scalerMean[i]) / scale;
    });

    _rollingWindow.add(normalized);
    if (_rollingWindow.length > windowSize) {
      _rollingWindow.removeAt(0);
    }

    // Run inference once we have enough temporal context
    if (_rollingWindow.length >= 10) {
      _runInference();
    }

    return _latestEstimatedSpeed;
  }

  void _runInference() {
    // 1. Strict Zero-Velocity Update (ZUPT) Detection over temporal window
    double sumNormA = 0.0;
    double sumNormG = 0.0;

    for (final sample in _rollingWindow) {
      final normA = (sample[6] * scalerScale[6]) + scalerMean[6];
      final normG = (sample[7] * scalerScale[7]) + scalerMean[7];
      sumNormA += normA;
      sumNormG += normG;
    }

    final meanNormA = sumNormA / _rollingWindow.length;
    final meanNormG = sumNormG / _rollingWindow.length;

    double varianceNormA = 0.0;
    for (final sample in _rollingWindow) {
      final normA = (sample[6] * scalerScale[6]) + scalerMean[6];
      varianceNormA += (normA - meanNormA) * (normA - meanNormA);
    }
    final stdNormA = sqrt(varianceNormA / _rollingWindow.length);

    // Stationary Gate: when phone is resting on a desk or held still in hand:
    // Standard deviation of acceleration magnitude is small (<0.32 m/s^2)
    // and gyroscope angular velocity is low (<0.22 rad/s)
    if (stdNormA < 0.32 && meanNormG < 0.22) {
      _latestEstimatedSpeed = 0.0;
      return;
    }

    final interpreter = _interpreter;
    if (interpreter != null && _isModelLoaded) {
      try {
        final stopwatch = Stopwatch()..start();
        // Prepare tensor [1, 20, 13]
        final input = List.generate(
          1,
          (_) => List.generate(
            windowSize,
            (t) => t < _rollingWindow.length
                ? _rollingWindow[t]
                : List.filled(numFeatures, 0.0),
          ),
        );

        final output = List.generate(1, (_) => List.filled(2, 0.0)); // [speed, log_variance]
        interpreter.run(input, output);
        stopwatch.stop();

        final rawSpeed = output[0][0];
        final variance = exp(output[0][1].clamp(-5.0, 5.0));

        // When dynamic motion is present, scale model prediction with physical variance
        if (stdNormA > 0.45 || meanNormG > 0.30) {
          _latestEstimatedSpeed = rawSpeed.clamp(0.0, 45.0);
        } else {
          _latestEstimatedSpeed = 0.0;
        }
        _latestConfidence = (1.0 / (1.0 + variance)).clamp(0.70, 0.99);
        _latestInferenceLatencyMs =
            max(1, (stopwatch.elapsedMicroseconds / 1000).round());
        _modelRuns++;
        return;
      } catch (e) {
        debugPrint('[MlSpeedEstimator] inference failed, using fallback: $e');
      }
    }
    _latestEstimatedSpeed = _kinematicFallbackSpeed(stdNormA);
  }

  /// Rule-based fallback used only when the TFLite model is unavailable. It is
  /// a heuristic, not a neural estimate, and is never reported as one.
  double _kinematicFallbackSpeed(double stdNormA) {
    if (_rollingWindow.isEmpty || stdNormA < 0.32) return 0.0;

    double dynamicForwardEnergy = 0.0;

    for (final sample in _rollingWindow) {
      final ax = (sample[0] * scalerScale[0]) + scalerMean[0];
      final pitch = (sample[11] * scalerScale[11]) + scalerMean[11];

      // Remove gravity projection: a_dyn_x = ax - g * sin(pitch)
      final gravityForward = 9.81 * sin(pitch);
      final dynamicAx = (ax - gravityForward).abs();

      if (dynamicAx > 0.35) {
        dynamicForwardEnergy += dynamicAx;
      }
    }

    final avgDynamicForward = dynamicForwardEnergy / _rollingWindow.length;

    if (avgDynamicForward < 0.25 && stdNormA < 0.40) {
      return 0.0;
    }

    // Dynamic forward speed proportional to real physical kinetic energy
    final speed = (avgDynamicForward * 3.2 + (stdNormA - 0.32) * 1.8).clamp(0.0, 35.0);
    return speed > 0.3 ? speed : 0.0;
  }

  @override
  void reset() {
    _rollingWindow.clear();
    _latestEstimatedSpeed = 0.0;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
  }
}
