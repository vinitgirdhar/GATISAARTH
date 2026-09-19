import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';
import 'package:gatisaarth/core/nav/replay/drive_recorder.dart';
import 'package:gatisaarth/core/nav/replay/replay_engine.dart';

import 'support/drive_simulator.dart';

/// One rung of the ablation ladder (§40).
class Ablation {
  const Ablation(this.label, this.features);

  final String label;
  final FeatureFlags features;
}

/// A, B, C... each adds one thing to the one before, so the difference between
/// two rows is attributable to exactly one component.
///
/// The neural-velocity rung of §40 is absent, not skipped silently: the model
/// asset in this repository is a 130-byte Git-LFS pointer, so there is nothing
/// to ablate. It reappears here the day a real model loads.
const ablations = <Ablation>[
  Ablation('A raw inertial', FeatureFlags.rawInertial),
  Ablation(
    'B + GNSS velocity',
    FeatureFlags(
      zeroVelocityUpdate: false,
      zeroAngularRateUpdate: false,
      nonHolonomicConstraint: false,
      magnetometerHeading: false,
      mapHeading: false,
      adaptiveGnssCovariance: false,
    ),
  ),
  Ablation(
    'C + NHC',
    FeatureFlags(
      zeroVelocityUpdate: false,
      zeroAngularRateUpdate: false,
      magnetometerHeading: false,
      mapHeading: false,
      adaptiveGnssCovariance: false,
    ),
  ),
  Ablation(
    'D + ZUPT/ZARU',
    FeatureFlags(
      magnetometerHeading: false,
      mapHeading: false,
      adaptiveGnssCovariance: false,
    ),
  ),
  Ablation(
    'E + adaptive GNSS R',
    FeatureFlags(magnetometerHeading: false, mapHeading: false),
  ),
  Ablation('F complete (no map, no AI)', FeatureFlags()),
];

/// Records one drive with a GNSS outage, and returns the log plus the ground
/// truth distance travelled during the outage.
({List<String> lines, double outageDistanceM}) recordOutageDrive({
  double outageSeconds = 60,
  int seed = 42,
}) {
  final sink = MemoryLogSink();
  final recorder = DriveRecorder(sink: sink);
  recorder.start(const DriveMeta(
    sessionId: 'ablation',
    startedAtMs: 0,
    vehicle: 'car',
    mountDescription: 'tilted console',
  ));

  final sim = DriveSimulator(mount: PhoneMount.tilted(), seed: seed);
  var nextGnssUs = 0;
  var gnssOn = true;

  void drive(List<DriveSegment> segments) {
    for (final segment in segments) {
      final steps = (segment.seconds * sim.imuHz).round();
      for (var i = 0; i < steps; i++) {
        final frame = sim.step(segment);
        recorder.recordImu(
          monotonicUs: frame.truth.monotonicUs,
          accel: frame.accelPhone,
          gyro: frame.gyroPhone,
        );
        recorder.recordTruth(
          monotonicUs: frame.truth.monotonicUs,
          latitude: frame.truth.latitude,
          longitude: frame.truth.longitude,
        );
        if (frame.truth.monotonicUs >= nextGnssUs) {
          nextGnssUs = frame.truth.monotonicUs + 1000000;
          if (gnssOn) {
            recorder.recordGnss(sim.gnss());
          } else {
            recorder.recordGnssLost(frame.truth.monotonicUs);
          }
        }
      }
    }
  }

  drive(calibrationDrive());
  drive(const [
    DriveSegment(seconds: 10, longitudinalAccel: 1.5),
    DriveSegment(seconds: 5),
  ]);

  final distanceAtLoss = sim.truth.distanceM;
  gnssOn = false;
  recorder.recordMarker(
      monotonicUs: sim.truth.monotonicUs, label: 'gnss lost');
  final profile = <DriveSegment>[
    const DriveSegment(seconds: 8),
    const DriveSegment(seconds: 4, yawRate: 0.12),
    const DriveSegment(seconds: 6),
    const DriveSegment(seconds: 4, longitudinalAccel: -2.5),
    const DriveSegment(seconds: 4),
    const DriveSegment(seconds: 4, longitudinalAccel: 2.5),
  ];
  final profileSeconds = profile.fold<double>(0, (a, s) => a + s.seconds);
  for (var i = 0; i < (outageSeconds / profileSeconds).ceil(); i++) {
    drive(profile);
  }
  recorder.stop();

  return (
    lines: sink.lines,
    outageDistanceM: sim.truth.distanceM - distanceAtLoss,
  );
}

void main() {
  group('ablation ladder', () {
    test('each component is measured over several drives, not asserted', () {
      // One drive is an anecdote. Differences of a few tenths of a percent
      // between neighbouring rungs are noise on a single seed, so every rung
      // is run over the same set of drives and averaged (§40).
      const seeds = [11, 23, 42, 71, 97];
      final drives = [
        for (final seed in seeds)
          recordOutageDrive(outageSeconds: 60, seed: seed),
      ];

      final meanDrift = <String, double>{};

      // ignore: avoid_print
      print('\nSIMULATED ablation: 60 s GNSS outage, ${seeds.length} drives, '
          '${drives.first.outageDistanceM.toStringAsFixed(0)} m each');
      // ignore: avoid_print
      print('  configuration               mean drift    worst     best');

      for (final ablation in ablations) {
        final drifts = <double>[];
        for (final drive in drives) {
          final summary = ReplayEngine.fromLines(
            drive.lines,
            config: NavConfig(features: ablation.features),
          ).runToEnd();
          expect(summary.hasGroundTruth, isTrue);
          drifts.add(100 * summary.finalErrorM! / drive.outageDistanceM);
        }
        drifts.sort();
        final mean = drifts.reduce((a, b) => a + b) / drifts.length;
        meanDrift[ablation.label] = mean;

        // ignore: avoid_print
        print('  ${ablation.label.padRight(28)}'
            '${mean.toStringAsFixed(2).padLeft(7)}%'
            '${drifts.last.toStringAsFixed(2).padLeft(9)}%'
            '${drifts.first.toStringAsFixed(2).padLeft(9)}%');
      }

      expect(meanDrift, hasLength(ablations.length));

      // The claim the whole system rests on: the constraints help. Measured
      // here rather than asserted in a README.
      final raw = meanDrift['A raw inertial']!;
      final complete = meanDrift['F complete (no map, no AI)']!;
      expect(complete, lessThan(raw / 5),
          reason: 'the complete system must clearly beat raw propagation');

      // Non-holonomic is the single biggest lever, and that ordering is a
      // claim worth failing CI over if it ever stops being true.
      expect(meanDrift['C + NHC']!, lessThan(meanDrift['B + GNSS velocity']!));
    });

    test('the same ablation replayed twice gives the same number', () {
      // Without this, no comparison between rungs means anything.
      final drive = recordOutageDrive(outageSeconds: 30);
      const config = NavConfig(features: FeatureFlags());
      final first =
          ReplayEngine.fromLines(drive.lines, config: config).runToEnd();
      final second =
          ReplayEngine.fromLines(drive.lines, config: config).runToEnd();
      expect(second.finalErrorM, first.finalErrorM);
      expect(second.maxErrorM, first.maxErrorM);
    });

    test('turning off a constraint changes the answer — the flags are real',
        () {
      final drive = recordOutageDrive(outageSeconds: 60);
      final withNhc = ReplayEngine.fromLines(
        drive.lines,
        config: const NavConfig(features: FeatureFlags()),
      ).runToEnd();
      final withoutNhc = ReplayEngine.fromLines(
        drive.lines,
        config: const NavConfig(
          features: FeatureFlags(nonHolonomicConstraint: false),
        ),
      ).runToEnd();
      expect(withoutNhc.finalErrorM, isNot(withNhc.finalErrorM));
    });

    test('the neural velocity rung is absent because the model is', () {
      // Pins the honest state (§83): no model file, so no ablation row, and
      // the flag stays off.
      expect(NavConfig.defaults.features.neuralVelocity, isFalse);
      expect(NavConfig.defaults.ai.enabled, isFalse);
      expect(
        ablations.any((a) => a.label.toLowerCase().contains('neural')),
        isFalse,
      );
    });
  });
}
