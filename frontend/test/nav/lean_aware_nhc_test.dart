import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/motion/motion_classifier.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';

void main() {
  test('a car keeps its tight constraint whatever the roll rate', () {
    final m = MotionClassifier(vehicleClass: VehicleClass.car);
    expect(m.nhcLateralSigmaFor(rollRateRad: 0.8),
        NavConfig.defaults.ekf.nhcSigmaCar);
  });

  test('an upright, steady bike keeps the base two-wheeler sigma', () {
    final m = MotionClassifier(vehicleClass: VehicleClass.twoWheeler);
    expect(m.nhcLateralSigmaFor(),
        closeTo(NavConfig.defaults.ekf.nhcSigmaTwoWheeler, 1e-12));
  });

  test('rolling into a lean widens it by mount height × roll rate', () {
    final m = MotionClassifier(vehicleClass: VehicleClass.twoWheeler);
    const ekf = EkfConfig();
    final sigma = m.nhcLateralSigmaFor(rollRateRad: -0.5);
    final swing = ekf.twoWheelerMountHeightM * 0.5;
    expect(sigma * sigma,
        closeTo(ekf.nhcSigmaTwoWheeler * ekf.nhcSigmaTwoWheeler + swing * swing,
            1e-9));
  });

  test('a walker has no side-slip constraint at all', () {
    final m = MotionClassifier(vehicleClass: VehicleClass.pedestrian);
    expect(m.nhcLateralSigmaFor(rollRateRad: 0.3), double.infinity);
  });

  test('off in every shipped config until a two-wheeler drive shows it helps',
      () {
    expect(NavConfig.defaults.features.leanAwareNhc, isFalse);
    expect(NavConfig.live.features.leanAwareNhc, isFalse);
  });
}
