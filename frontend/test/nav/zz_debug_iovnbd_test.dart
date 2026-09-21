import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/replay/replay_engine.dart';

void main() {
  test('debug: engine on a real IO-VNBD log', skip: Platform.environment['DRIVE_LOG'] == null ? 'set DRIVE_LOG to run the local replay diagnostic' : false, () {
    final path = Platform.environment['DRIVE_LOG']!;
    final lines = File(path).readAsLinesSync().take(400000);
    final replay = ReplayEngine.fromLines(lines);
    var nextPrint = 0;
    final modes = <String, int>{};
    final errs = <double>[];
    dynamic lastSnap;
    double? truthSpeed;
    while (true) {
      final step = replay.stepOnce();
      if (step == null) break;
      if (step.record.type.name == 'truth') truthSpeed = step.record.speedMps;
      final us = step.record.monotonicUs;
      if (step.snapshot != null) {
        lastSnap = step.snapshot;
        modes.update(step.snapshot!.mode.toString(), (v) => v + 1, ifAbsent: () => 1);
      }
      if (step.errorM != null) errs.add(step.errorM!);
      if (us >= nextPrint && step.snapshot != null) {
        nextPrint = us + 30000000;
        final s = step.snapshot!;
        if (Platform.environment['VERBOSE'] == '1') print('t=${((us - 5000000) / 1e6).toStringAsFixed(0)}s mode=${s.mode} '
            'cal=${s.isMountCalibrated} conf=${s.alignmentConfidence?.toStringAsFixed(2)} '
            'ev=${replay.engine.alignmentEvents} smp=${replay.engine.alignmentSamples} '
            'v=${s.speedMps?.toStringAsFixed(1)} truthV=${truthSpeed?.toStringAsFixed(1)} '
            'err=${step.errorM?.toStringAsFixed(1)} lead=${s.canLeadPosition}');
      }
      if (us > 5000000 + 900e6) break;
    }
    errs.sort();
    print('SUMMARY modes=$modes calibrated=${lastSnap?.isMountCalibrated} events=${replay.engine.alignmentEvents} '
        'meanErr=${errs.isEmpty ? null : (errs.reduce((a, b) => a + b) / errs.length).toStringAsFixed(1)} '
        'p95=${errs.isEmpty ? null : errs[(errs.length * 0.95).floor()].toStringAsFixed(1)}');
  });
}
