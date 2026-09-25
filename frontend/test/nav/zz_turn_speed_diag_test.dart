import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/replay/replay_engine.dart';

/// Local diagnostic: how accurate the coordinated-turn speed is against the
/// VBOX speed on real IO-VNBD trips while GNSS is live (bias and RMS over
/// every graded turn). Skipped unless IOVNBD_LOG_DIR is set.
///
///     IOVNBD_LOG_DIR=ml/data/processed/drive_logs_vehicle \
///         flutter test test/nav/zz_turn_speed_diag_test.dart
void main() {
  final dir = Platform.environment['IOVNBD_LOG_DIR'];
  test('turn speed diagnostics',
      skip: dir == null ? 'local only' : false,
      timeout: const Timeout(Duration(minutes: 20)), () {
    for (final name in const [
      'S_Driver_A__S1__S1.jsonl',
      'S_Driver_A__S3c__S3c.jsonl',
      'Vta_Driver_E__Vta16__Vta16.jsonl',
      'Vw_Driver_E__Vw11__Vw11.jsonl',
    ]) {
      final lines = File('$dir/$name').readAsLinesSync();
      final replay = ReplayEngine.fromLines(lines,
          config: const NavConfig(
              features: FeatureFlags(turnSpeed: true),
              turnSpeed: TurnSpeedConfig(validationWindow: 100000)));
      while (replay.stepOnce() != null) {}
      final d = replay.engine.turnSpeedDiagnostics;
      // ignore: avoid_print
      print('$name observed=${d.observed} pairs=${d.validationPairs} '
          'bias=${d.validationBiasMps?.toStringAsFixed(2)} '
          'rms=${d.validationRmsMps?.toStringAsFixed(2)} trusted=${d.trusted}');
    }
  });
}
