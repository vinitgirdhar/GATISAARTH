import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/ai/ai_types.dart';
import 'package:gatisaarth/core/nav/sensors/sensor_sample.dart' show DataSource;
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';
import 'package:gatisaarth/core/nav/replay/ai_record_feed.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';
import 'package:gatisaarth/core/nav/replay/drive_recorder.dart';
import 'package:gatisaarth/core/nav/replay/replay_engine.dart';

import '../support/ai_injection.dart';
import '../support/drive_simulator.dart';

const _on = AiConfig(enabled: true);
const _speedOnly = AiConfig(
    enabled: true, disturbanceAdaptation: false, fusionTrust: false);

/// A calibration drive, a cruise, a bend and another cruise: about 4.5 minutes,
/// with the mount known after the first two and the vehicle moving after.
List<DriveSegment> _cruise() => const [
      DriveSegment(seconds: 8, longitudinalAccel: 1.6),
      DriveSegment(seconds: 40),
      DriveSegment(seconds: 5, yawRate: 0.1),
      DriveSegment(seconds: 50),
    ];

/// The moment (us) GNSS goes away in the drives below: 30 s into the cruise.
int _blackoutUs(List<DriveRecord> log) {
  final marker = log.firstWhere((r) => r.type == DriveRecordType.marker);
  return marker.monotonicUs + 38 * 1000000;
}

ReplayEngine _replay(List<DriveRecord> log, AiConfig ai) =>
    ReplayEngine(records: log, config: NavConfig(ai: ai));

void main() {
  late List<DriveRecord> good;
  late int blackout;

  setUpAll(() {
    good = simulateDriveLogWithAi(
        setup: calibrationDrive(), segments: _cruise(), truth: true);
    blackout = _blackoutUs(good);
  });

  group('the AI off is the engine it always was', () {
    test('ai records in a log are ignored by default: same answer to the bit',
        () {
      final withAi = _replay(good, const AiConfig())..runToEnd();
      final without = _replay(withoutAi(good), const AiConfig())..runToEnd();
      final a = withAi.engine.snapshot!;
      final b = without.engine.snapshot!;
      expect(a.latitude, b.latitude);
      expect(a.longitude, b.longitude);
      expect(a.speedMps, b.speedMps);
      expect(a.headingDeg, b.headingDeg);
      expect(a.horizontalSigmaM, b.horizontalSigmaM);
      expect(a.speedSigmaMps, b.speedSigmaMps);
      expect(a.aiDiagnostics.enabled, isFalse);
      expect(identical(a.aiDiagnostics, AiDiagnostics.off), isTrue);
    });

    test('enabled but with every part switched off is still the same engine',
        () {
      const nothing = AiConfig(
          enabled: true,
          speedMeasurement: false,
          disturbanceAdaptation: false,
          fusionTrust: false);
      final a = _replay(good, const AiConfig())..runToEnd();
      final b = _replay(good, nothing)..runToEnd();
      final sa = a.engine.snapshot!;
      final sb = b.engine.snapshot!;
      expect(sb.latitude, sa.latitude);
      expect(sb.longitude, sa.longitude);
      expect(sb.speedSigmaMps, sa.speedSigmaMps);
      expect(sb.horizontalSigmaM, sa.horizontalSigmaM);
    });

    test('it says so: the subsystem row reads "disabled", never a number', () {
      final r = _replay(good, const AiConfig())..runToEnd();
      final s = r.engine.snapshot!;
      expect(s.ai.available, isFalse);
      expect(s.ai.source, DataSource.unavailable);
      expect(s.ai.detail, 'Neural velocity disabled');
      expect(s.aiDiagnostics.summary, 'AI fusion off');
    });

    test('a disabled engine still answers every call, and says why', () {
      final e = NavigationEngine();
      final d = e.onAiSpeed(const AiSpeedObservation(
          speedMps: 5, sigmaMps: 0.5, monotonicUs: 1));
      expect(d.reason, AiRejectReason.disabled);
      e.onDisturbance(DisturbanceEstimate.calm);
      e.onFusionConfidence(const FusionConfidence(gnssTrust: 0.5));
      expect(e.aiDiagnostics.enabled, isFalse);
    });
  });

  group('P1: the neural forward speed in the loop', () {
    test('while GNSS is healthy it is not applied: it grades the model', () {
      final r = _replay(good, _speedOnly)..runTo(blackout - 1);
      final d = r.engine.aiDiagnostics;
      expect(d.speedApplied, 0);
      expect(d.speedValidatedOnly, greaterThan(100));
      expect(d.validated, isTrue);
      expect(d.validationRmseMps, lessThan(1.0));
      expect(d.validationBiasMps!.abs(), lessThan(0.3));
    });

    test('before the mount is known the engine cannot use it, and says so', () {
      final r = _replay(good, _speedOnly)..runTo(20 * 1000000);
      final d = r.engine.aiDiagnostics;
      expect(d.speedApplied, 0);
      expect(d.speedRejected[AiRejectReason.notReady], greaterThan(50));
    });

    test('in a blackout it is applied, and the answer is better for it', () {
      final blacked = blackoutFrom(good, blackout);
      final off = _replay(blacked, const AiConfig())..runToEnd();
      final on = _replay(blacked, _speedOnly)..runToEnd();
      final d = on.engine.aiDiagnostics;
      expect(d.speedApplied, greaterThan(100));
      expect(d.speedRejectedTotal, lessThan(d.speedApplied));
      expect(on.summary().finalErrorM!, lessThan(off.summary().finalErrorM!));
      // ...and the filter's own claim of how well it knows its speed.
      expect(on.engine.snapshot!.speedSigmaMps!,
          lessThan(off.engine.snapshot!.speedSigmaMps!));
    });

    test('it is credited in the position accounting once it is doing work', () {
      final blacked = blackoutFrom(good, blackout);
      final on = _replay(blacked, _speedOnly);
      var best = 0.0;
      while (on.stepOnce() != null) {
        best = math.max(best, on.engine.snapshot?.contribution.ai ?? 0);
      }
      expect(best, greaterThan(0));
      expect(on.engine.snapshot!.ai.available, isTrue);
      expect(on.engine.snapshot!.ai.source, DataSource.estimated);
      expect(on.engine.snapshot!.ai.detail, contains('used'));
    });

    test('every refusal has a reason the diagnostics carry', () {
      Map<AiRejectReason, int> reasons(AiModelProfile model) {
        final log = blackoutFrom(
            simulateDriveLogWithAi(
                setup: calibrationDrive(), segments: _cruise(), model: model),
            blackout);
        final r = _replay(log, _speedOnly)..runToEnd();
        expect(r.engine.aiDiagnostics.speedApplied, 0,
            reason: 'a bad model must never be applied');
        return r.engine.aiDiagnostics.speedRejected;
      }

      expect(reasons(AiModelProfile.good.copyWith(biasMps: 4)),
          containsPair(AiRejectReason.unvalidated, greaterThan(100)));
      expect(reasons(AiModelProfile.good.copyWith(featureZ: 9)),
          containsPair(AiRejectReason.offDistribution, greaterThan(100)));
      expect(reasons(AiModelProfile.good.copyWith(latencyMs: 60)),
          containsPair(AiRejectReason.latency, greaterThan(100)));
    });

    test('a refused model leaves the filter exactly as it would have been: no '
        'streak, no covariance widened, the same answer to the bit', () {
      final biased = blackoutFrom(
          simulateDriveLogWithAi(
              setup: calibrationDrive(),
              segments: _cruise(),
              model: AiModelProfile.good.copyWith(biasMps: 4),
              truth: true),
          blackout);
      final off = _replay(withoutAi(biased), const AiConfig())..runToEnd();
      final on = _replay(biased, _speedOnly)..runToEnd();
      final a = off.engine.snapshot!;
      final b = on.engine.snapshot!;
      expect(b.latitude, a.latitude);
      expect(b.longitude, a.longitude);
      expect(b.speedSigmaMps, a.speedSigmaMps);
      expect(b.horizontalSigmaM, a.horizontalSigmaM);
      expect(on.engine.filter.rejectStreakFor('ai_forward_speed'), 0);
      expect(on.engine.filter.rejectStreakFor('forward_speed'), 0);
      expect(on.summary().finalErrorM, off.summary().finalErrorM);
    });

    test('the speed switch turns the speed off and nothing else', () {
      final blacked = blackoutFrom(good, blackout);
      final r = _replay(
          blacked, const AiConfig(enabled: true, speedMeasurement: false))
        ..runToEnd();
      final d = r.engine.aiDiagnostics;
      expect(d.speedActive, isFalse);
      expect(d.speedApplied, 0);
      expect(d.speedRejected[AiRejectReason.disabled], greaterThan(100));
      expect(d.disturbanceActive, isTrue);
    });

    test('a model that is good and then goes bad mid-outage is caught by the '
        'physics gate, for as long as the INS can contradict it', () {
      // The first 20 s of the blackout are honest; then a +6 m/s bias. Once
      // the INS has drifted (a few seconds without help) its own uncertainty is
      // wide enough to admit anything: a limit of gating on physics alone, and
      // the reason the model is graded against GNSS before an outage at all.
      final base = simulateDriveLogWithAi(
          setup: calibrationDrive(), segments: _cruise());
      final until = blackout + 20 * 1000000;
      final tampered = [
        for (final r in blackoutFrom(base, blackout))
          if (r.type == DriveRecordType.ai &&
              r.monotonicUs > until &&
              r.aiSpeed != null)
            DriveRecord.ai(
              monotonicUs: r.monotonicUs,
              speed: AiSpeedObservation(
                speedMps: r.aiSpeed!.speedMps + 6,
                sigmaMps: r.aiSpeed!.sigmaMps,
                monotonicUs: r.monotonicUs,
                latencyMs: r.aiSpeed!.latencyMs,
                featureZMax: r.aiSpeed!.featureZMax,
                windowsFed: r.aiSpeed!.windowsFed,
              ),
            )
          else
            r,
      ];
      final r = _replay(tampered, _speedOnly)..runToEnd();
      final d = r.engine.aiDiagnostics;
      expect(d.speedApplied, greaterThan(100));
      expect(d.speedRejected[AiRejectReason.physicsDisagreement],
          greaterThan(30));
    });
  });

  group('the log is the run', () {
    test('a live run and the replay of its recording agree to the bit, ai '
        'lines included', () {
      final sink = MemoryLogSink();
      final recorder = DriveRecorder(sink: sink)
        ..start(const DriveMeta(sessionId: 'ai', startedAtMs: 0));
      final config = NavConfig(ai: _on);
      final live = NavigationEngine(config: config);
      for (final r in blackoutFrom(good, blackout)) {
        switch (r.type) {
          case DriveRecordType.imu:
            recorder.recordImu(
                monotonicUs: r.monotonicUs, accel: r.accel!, gyro: r.gyro!);
            live.onImu(
                accelPhone: r.accel!,
                gyroPhone: r.gyro!,
                monotonicUs: r.monotonicUs);
          case DriveRecordType.gnss:
            recorder.recordGnss(r.fix!);
            live.onGnss(r.fix!);
          case DriveRecordType.gnssLost:
            recorder.recordGnssLost(r.monotonicUs);
            live.onGnssLost(r.monotonicUs);
          case DriveRecordType.ai:
            recorder.recordAi(
                monotonicUs: r.monotonicUs,
                speed: r.aiSpeed,
                disturbance: r.disturbance,
                fusion: r.fusion);
            feedAiRecord(live, r);
          default:
        }
      }
      recorder.stop();
      expect(recorder.counts['ai'], greaterThan(1000));

      final replay = ReplayEngine.fromLines(sink.lines, config: config)
        ..runToEnd();
      expect(replay.skippedLines, 0);
      final a = live.snapshot!;
      final b = replay.engine.snapshot!;
      expect(b.latitude, a.latitude);
      expect(b.longitude, a.longitude);
      expect(b.speedMps, a.speedMps);
      expect(b.horizontalSigmaM, a.horizontalSigmaM);
      expect(replay.engine.aiDiagnostics.speedApplied,
          live.aiDiagnostics.speedApplied);
      expect(replay.engine.aiDiagnostics.speedRejected,
          live.aiDiagnostics.speedRejected);
    });
  });

  group('P2: what is shaking the phone changes what the filter believes', () {
    /// A blackout drive where, from the start, the model [feed] tells the engine
    /// every 100 ms what the vibration models say.
    NavigationEngine runWith(DisturbanceEstimate? Function(int us) feed,
        {AiConfig ai = const AiConfig(enabled: true, speedMeasurement: false)}) {
      final e = NavigationEngine(config: NavConfig(ai: ai));
      var nextUs = 0;
      for (final r in blackoutFrom(good, blackout)) {
        switch (r.type) {
          case DriveRecordType.imu:
            e.onImu(
                accelPhone: r.accel!,
                gyroPhone: r.gyro!,
                monotonicUs: r.monotonicUs);
            if (r.monotonicUs >= nextUs) {
              nextUs = r.monotonicUs + 100000;
              final d = feed(r.monotonicUs);
              if (d != null) e.onDisturbance(d);
            }
          case DriveRecordType.gnss:
            e.onGnss(r.fix!);
          case DriveRecordType.gnssLost:
            e.onGnssLost(r.monotonicUs);
          default:
        }
      }
      return e;
    }

    DisturbanceEstimate shaken(int us, {double v = 0.8, double q = 0.5}) =>
        DisturbanceEstimate(
          vibrationScore: v,
          vibrationClass: DisturbanceClass.high,
          motionQuality: q,
          monotonicUs: us,
        );

    test('a high vibration score widens what the filter admits about its '
        'speed, by about the process-noise factor', () {
      final calm = runWith((us) => shaken(us, v: 0, q: 1));
      final rough = runWith((us) => shaken(us));
      // (1 + 1.5 * 0.8) / 0.5 = 4.4 on the variance: about 2.1 on the sigma.
      final ratio = rough.snapshot!.speedSigmaMps! / calm.snapshot!.speedSigmaMps!;
      expect(ratio, inInclusiveRange(1.5, 2.4));
      expect(rough.aiDiagnostics.processNoiseScale, closeTo(4.4, 1e-9));
      expect(rough.aiDiagnostics.measurementNoiseScale, closeTo(5.2, 1e-9));
    });

    test('the model estimate replaces the statistical one while it is fresh, '
        'and the statistical one takes over when it goes stale', () {
      final e = NavigationEngine(config: NavConfig(ai: _on));
      expect(e.aiDiagnostics.disturbance?.source, EstimateSource.statistical);
      e.onDisturbance(shaken(1000000));
      // Nothing has been fed yet, so "now" is 0: the estimate is from the future
      // and still counts as fresh.
      expect(e.aiDiagnostics.disturbance?.source, EstimateSource.model);
    });

    test('the disturbance switch really switches it: no scaling reaches the '
        'filter with it off', () {
      final off = runWith((us) => shaken(us),
          ai: const AiConfig(
              enabled: true,
              speedMeasurement: false,
              disturbanceAdaptation: false));
      expect(off.aiDiagnostics.processNoiseScale, 1.0);
      expect(off.aiDiagnostics.measurementNoiseScale, 1.0);
      expect(off.aiDiagnostics.disturbance, isNull);
    });
  });
}
