import 'ml_speed_estimator.dart';

class LocalTfliteRunner {
  final MlSpeedEstimator _estimator = MlSpeedEstimator();

  Future<void> load() async {
    await _estimator.initialize();
  }

  List<double> run(List<double> input) {
    if (input.length >= 8) {
      final speed = _estimator.addImuFrame(
        ax: input[0],
        ay: input[1],
        az: input[2],
        gx: input[3],
        gy: input[4],
        gz: input[5],
        pitch: input[6],
        roll: input[7],
      );
      return [speed, _estimator.confidence];
    }
    return [0.0, 0.90];
  }
}

