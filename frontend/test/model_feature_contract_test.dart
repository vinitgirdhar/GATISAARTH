import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/features/ai_motion/domain/imu_feature_window.dart';

void main() {
  test('phone scaler matches the real IO-VNBD training scaler', () {
    final scaler = jsonDecode(
        File('../ml/data/scalers/imu_feature_scaler.json').readAsStringSync());
    expect(ImuFeatureWindow.mean, scaler['mean']);
    expect(ImuFeatureWindow.scale, scaler['scale']);
  });

  test('causal jerk and tilt match the Python training contract', () {
    final window = ImuFeatureWindow();
    final first = window.add(
        ax: 1, ay: 2, az: 9.81, gx: 0, gy: 0, gz: 0, pitch: 0, roll: 0);
    expect(ImuFeatureWindow.physical(first, 8), closeTo(0, 1e-10));
    final next = window.add(
        ax: 2, ay: 1, az: 9.71, gx: 0, gy: 0, gz: 0, pitch: 0, roll: 0);
    expect(ImuFeatureWindow.physical(next, 8), closeTo(10, 1e-10));
    expect(ImuFeatureWindow.physical(next, 9), closeTo(-10, 1e-10));
    expect(ImuFeatureWindow.physical(next, 10), closeTo(-1, 1e-10));
    expect(ImuFeatureWindow.physical(next, 11),
        closeTo(atan2(2, sqrt(1 + 9.71 * 9.71)), 1e-10));
    expect(ImuFeatureWindow.physical(next, 12), closeTo(atan2(1, 9.71), 1e-10));
    window.reset();
    final reset =
        window.add(ax: 8, ay: 2, az: 9, gx: 0, gy: 0, gz: 0, pitch: 0, roll: 0);
    expect(ImuFeatureWindow.physical(reset, 8), closeTo(0, 1e-10));
  });
}
