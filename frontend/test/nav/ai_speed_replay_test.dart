import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_benchmark.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_report.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

import 'support/ai_injection.dart';
import 'support/drive_simulator.dart';
import 'support/reference_drive.dart';

/// The replay evidence for the AI in the navigation loop (P1-P3).
///
/// **What this is.** The same simulated drive is scored by the outage benchmark
/// with the AI path off and on, with model outputs *injected* around the
/// simulator's true speed ([AiModelProfile]: a bias, a noise level, a claimed
/// sigma, a latency, an input-distribution score). So it proves properties of
/// the mechanism - the gate rejects a bad model, a good one shortens the drift,
/// a refused one changes nothing - **not** how accurate any real model is, and
/// the drive is simulated, so none of these numbers is a field measurement.
/// `AiConfig.enabled` stays false in `NavConfig.defaults`; this is the evidence
/// its doc comment asks for, and it is on synthetic data only.
///
/// Every row is deterministic (fixed seeds, no clock), so a failure here is a
/// regression, never noise.

const _speedOnly = NavConfig(
    ai: AiConfig(
        enabled: true, disturbanceAdaptation: false, fusionTrust: false));
const _allOn = NavConfig(ai: AiConfig(enabled: true));

const _city = OutageBenchmarkConfig(
    durationsS: [10, 30, 60], strideS: 60, maxStarts: 4);
const _cruise = OutageBenchmarkConfig(
    durationsS: [60, 90, 120], strideS: 60, maxStarts: 4);

double _median(OutageReport r, int seconds) =>
    r.forDuration(seconds)!.engine.medianM;

double _p95(OutageReport r, int seconds) =>
    r.forDuration(seconds)!.engine.p95M;

String _row(String name, OutageReport r, List<int> durations) {
  final cells = [
    for (final d in durations)
      '${d}s ${_median(r, d).toStringAsFixed(1).padLeft(6)}'
          ' (p95 ${_p95(r, d).toStringAsFixed(0).padLeft(4)})',
  ];
  return '  ${name.padRight(30)} ${cells.join('  ')}';
}

void main() {
  group('the reference city drive: bends, stops, pulling away', () {
    late List<DriveRecord> offLog;
    late OutageReport off;
    final rows = <String>[];

    OutageReport score(
      AiModelProfile model,
      NavConfig engine, {
      String? name,
    }) {
      final log = simulateDriveLogWithAi(
        setup: referenceSetupDrive(),
        segments: referenceCityDrive(),
        model: model,
      );
      final report =
          OutageBenchmark.run(log, config: _city, engineConfig: engine);
      if (name != null) rows.add(_row(name, report, _city.durationsS));
      return report;
    }

    setUpAll(() {
      offLog = simulateDriveLogWithAi(
        setup: referenceSetupDrive(),
        segments: referenceCityDrive(),
        inject: false,
      );
      off = OutageBenchmark.run(offLog, config: _city);
      rows.add(_row('AI off (baseline)', off, _city.durationsS));
    });

    tearDownAll(() {
      // ignore: avoid_print
      print('\nSIMULATED reference city drive, median error at the end of a GNSS '
          'outage (m), core only:\n${rows.join('\n')}');
    });

    test('the drive is the one every other test uses: the injected log is the '
        'reference log plus ai lines, nothing else changed', () {
      final reference =
          simulateDriveLog(setup: referenceSetupDrive(), segments: referenceCityDrive());
      final injected = simulateDriveLogWithAi(
          setup: referenceSetupDrive(), segments: referenceCityDrive());
      expect(withoutAi(injected).map((r) => r.toJsonLine()).toList(),
          reference.map((r) => r.toJsonLine()).toList());
      expect(aiRecordsOf(injected), isNotEmpty);
    });

    test('a good model shortens the drift, and the gain is large past 30 s',
        () {
      final on = score(AiModelProfile.good, _allOn, name: 'good model, P1+P2+P3');
      expect(on.durations.map((d) => d.durationS), off.durations.map((d) => d.durationS));
      // Never worse at any length, clearly better where drift has time to grow.
      for (final d in _city.durationsS) {
        expect(_median(on, d), lessThanOrEqualTo(_median(off, d) + 0.5),
            reason: 'median at $d s');
      }
      expect(_median(on, 30), lessThan(_median(off, 30) * 0.5));
      expect(_median(on, 60), lessThan(_median(off, 60) * 0.5));
      expect(_p95(on, 60), lessThan(_p95(off, 60) * 0.5));
      // The claim about its own uncertainty is honest too.
      expect(on.forDuration(60)!.engineCovered, on.forDuration(60)!.n);
    });

    test('...and it is the speed measurement that does it', () {
      final p1 = score(AiModelProfile.good, _speedOnly,
          name: 'good model, P1 only');
      expect(_median(p1, 60), lessThan(_median(off, 60) * 0.5));
    });

    test('a noisy model that says so is still worth having', () {
      final noisy = score(
          AiModelProfile.good.copyWith(noiseMps: 0.9, reportedSigmaMps: 0.9),
          _speedOnly,
          name: 'noisy (0.9) but honest, P1');
      expect(_median(noisy, 60), lessThan(_median(off, 60) * 0.6));
    });

    group('a bad model changes nothing at all (P1: the gate is the filter\'s '
        'only defence)', () {
      final bad = <String, AiModelProfile>{
        'biased +4 m/s': AiModelProfile.good.copyWith(biasMps: 4),
        'biased -0.4 m/s': AiModelProfile.good.copyWith(biasMps: -0.4),
        'off-distribution input': AiModelProfile.good.copyWith(featureZ: 9),
        'slow (60 ms)': AiModelProfile.good.copyWith(latencyMs: 60),
        'overconfident, noisy':
            AiModelProfile.good.copyWith(noiseMps: 1.5, reportedSigmaMps: 0.1),
      };
      for (final entry in bad.entries) {
        test(entry.key, () {
          final r = score(entry.value, _speedOnly, name: '${entry.key}, P1');
          for (final d in _city.durationsS) {
            // Not "no worse": identical. A refused observation never reaches
            // the filter, so the result is the AI-off result to the last digit.
            expect(_median(r, d), _median(off, d), reason: 'median at $d s');
            expect(_p95(r, d), _p95(off, d), reason: 'p95 at $d s');
          }
        });
      }
    });

    test('with every part on, a bad model still does not make it worse (the '
        'disturbance scaling is the only difference)', () {
      for (final model in [
        AiModelProfile.good.copyWith(biasMps: 4),
        AiModelProfile.good.copyWith(featureZ: 9),
      ]) {
        final r = score(model, _allOn);
        for (final d in _city.durationsS) {
          expect(_median(r, d), lessThanOrEqualTo(_median(off, d) * 1.15 + 1.0),
              reason: 'median at $d s with $model');
        }
      }
    });

    test('the disturbance scaling alone (informational, no claim): it moves '
        'the numbers, in either direction, by no more than a few metres', () {
      final p2 = score(
          AiModelProfile.good,
          const NavConfig(
              ai: AiConfig(
                  enabled: true, speedMeasurement: false, fusionTrust: false)),
          name: 'P2 only (statistical fallback)');
      for (final d in _city.durationsS) {
        expect(_median(p2, d), lessThan(_median(off, d) * 1.5 + 2.0),
            reason: 'median at $d s');
      }
    });

    test('a bias inside what validation allows is used, and is not free: the '
        'honest limit of the gate', () {
      // 0.2 m/s is below the 0.3 the model may be off by against the GNSS
      // speed, so it validates; it then costs about bias x time of along-track
      // error, which is why the limit is small.
      final r = score(AiModelProfile.good.copyWith(biasMps: 0.2), _speedOnly,
          name: 'biased +0.2 m/s (allowed), P1');
      expect(_median(r, 60), lessThan(_median(off, 60)));
    });
  });

  group('quiet cruise: the failure this measurement exists to prevent', () {
    /// Constant speed on a straight road, a very quiet IMU, a small forward
    /// accelerometer bias, then GNSS is lost. Without help the filter's speed
    /// estimate slides down on the unobservable tilt/bias error until the IMU
    /// looks like a parked vehicle and the zero-velocity update pins it at zero
    /// (found first on a real winding route with simulated sensors: 10 m/s to 0
    /// after ~80 s, ~550 m of error).
    List<DriveRecord> quiet(AiModelProfile model, {bool inject = true}) =>
        simulateDriveLogWithAi(
          setup: referenceSetupDrive(),
          segments: const [
            DriveSegment(seconds: 8, longitudinalAccel: 1.6),
            DriveSegment(seconds: 500),
          ],
          accelNoise: 0.01,
          model: model,
          inject: inject,
        );

    late OutageReport off;
    final rows = <String>[];

    OutageReport score(List<DriveRecord> log, NavConfig engine, String name) {
      final r = OutageBenchmark.run(log, config: _cruise, engineConfig: engine);
      rows.add(_row(name, r, _cruise.durationsS));
      return r;
    }

    setUpAll(() {
      off = score(quiet(AiModelProfile.good, inject: false),
          const NavConfig(), 'AI off (baseline)');
    });

    tearDownAll(() {
      // ignore: avoid_print
      print('\nSIMULATED quiet cruise, 12.8 m/s straight, biased accelerometer, '
          'median error (m):\n${rows.join('\n')}');
    });

    test('without the AI the core loses its speed and the position with it',
        () {
      // Hold-velocity would be within tens of metres on a straight road.
      expect(_median(off, 90), greaterThan(200));
      expect(_median(off, 120), greaterThan(300));
      expect(_median(off, 120), greaterThan(_median(off, 60)));
    });

    test('with a good model the speed is held and the drift stays small', () {
      final on = score(quiet(AiModelProfile.good), _speedOnly, 'good model, P1');
      expect(_median(on, 60), lessThan(20));
      expect(_median(on, 90), lessThan(40));
      expect(_median(on, 120), lessThan(60));
      expect(_median(on, 120), lessThan(_median(off, 120) / 10));
      expect(_p95(on, 120), lessThan(_p95(off, 120) / 10));
    });

    test('with everything on it is at least as good', () {
      final on = score(quiet(AiModelProfile.good), _allOn, 'good model, P1+P2+P3');
      expect(_median(on, 120), lessThan(_median(off, 120) / 10));
    });

    test('a refused model leaves it exactly as it was: not better, and above '
        'all not worse', () {
      final r = score(quiet(AiModelProfile.good.copyWith(biasMps: 4)),
          _speedOnly, 'biased +4 m/s, P1');
      for (final d in _cruise.durationsS) {
        expect(_median(r, d), _median(off, d));
      }
    });
  });
}
