import 'dart:math' as math;

import 'package:gatisaarth/core/nav/ai/ai_types.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_benchmark.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

import 'accel_signals.dart' show gaussian;
import 'drive_simulator.dart';

/// The error character of a forward-speed model, injected around the
/// simulator's true speed. **Synthetic**: this is what makes the replay evidence
/// a statement about the mechanism (gate, noise scaling, filter), never about how
/// accurate any real model is.
class AiModelProfile {
  const AiModelProfile({
    this.biasMps = 0,
    this.noiseMps = 0.35,
    this.reportedSigmaMps = 0.45,
    this.latencyMs = 5,
    this.featureZ = 1.5,
    this.seed = 7,
    this.hz = 10,
    this.noiseGainWithVibration = 0,
  });

  /// A model whose reported sigma is honest and whose bias is zero.
  static const AiModelProfile good = AiModelProfile();

  /// The model's true error: a constant [biasMps] plus Gaussian noise of
  /// [noiseMps] (m/s). What it *claims* is [reportedSigmaMps].
  final double biasMps;
  final double noiseMps;
  final double reportedSigmaMps;

  /// What the gate is told about the inference and its input window.
  final double latencyMs;
  final double featureZ;
  final int seed;
  final int hz;

  /// Extra error std per unit of injected vibration (m/s per m/s^2 RMS): a model
  /// whose input window is corrupted by shaking is worse while it lasts.
  final double noiseGainWithVibration;

  AiModelProfile copyWith({
    double? biasMps,
    double? noiseMps,
    double? reportedSigmaMps,
    double? latencyMs,
    double? featureZ,
    double? noiseGainWithVibration,
  }) =>
      AiModelProfile(
        biasMps: biasMps ?? this.biasMps,
        noiseMps: noiseMps ?? this.noiseMps,
        reportedSigmaMps: reportedSigmaMps ?? this.reportedSigmaMps,
        latencyMs: latencyMs ?? this.latencyMs,
        featureZ: featureZ ?? this.featureZ,
        seed: seed,
        hz: hz,
        noiseGainWithVibration:
            noiseGainWithVibration ?? this.noiseGainWithVibration,
      );
}

/// A change to one phone-frame IMU sample: vibration, a shock, a bias that
/// drifts. Given the sample index and time, returns the accelerometer and gyro
/// to record instead.
typedef ImuDisturbance = ({Vector3 accel, Vector3 gyro}) Function(
    int index, int us, Vector3 accel, Vector3 gyro);

/// [simulateDriveLog] with model outputs injected into the log.
///
/// The IMU and GNSS records are **exactly** those [simulateDriveLog] writes for
/// the same arguments (the model draws its noise from its own generator, so the
/// simulator's random stream is untouched); each model output follows the IMU
/// line it describes, the order the live engine sees them in. [disturb] changes
/// the IMU after the simulator has produced it. [inject] false leaves the log
/// without `ai` records: the "AI off" drive. [truth] adds the simulator's true
/// position and speed once a second, so a ReplayEngine can score the run itself.
List<DriveRecord> simulateDriveLogWithAi({
  required List<DriveSegment> segments,
  List<DriveSegment> setup = const [],
  AiModelProfile model = AiModelProfile.good,
  bool inject = true,
  PhoneMount? mount,
  int seed = 42,
  double gnssAccuracy = 5,
  List<double> accelBias = const [0.08, -0.05, 0.06],
  List<double> gyroBias = const [0.002, -0.001, 0.004],
  double accelNoise = 0.04,
  ImuDisturbance? disturb,
  double Function(int us)? vibrationRmsAt,
  bool truth = false,
}) {
  final sim = DriveSimulator(
    mount: mount ?? PhoneMount.tilted(),
    seed: seed,
    gnssAccuracy: gnssAccuracy,
    accelBias: accelBias,
    gyroBias: gyroBias,
    accelNoise: accelNoise,
  );
  final rng = math.Random(model.seed);
  final records = <DriveRecord>[
    DriveRecord(
      type: DriveRecordType.meta,
      monotonicUs: 0,
      meta: DriveMeta(
        sessionId: 'simulated-$seed',
        startedAtMs: 0,
        deviceModel: 'simulator',
        notes: 'Simulated drive. Not a field measurement.',
      ).toJson(),
    ),
  ];

  final aiEveryUs = 1000000 ~/ model.hz;
  var nextGnssUs = 0;
  var nextAiUs = 0;
  var windows = 0;
  var index = 0;
  void drive(List<DriveSegment> list) {
    for (final segment in list) {
      final steps = (segment.seconds * sim.imuHz).round();
      for (var i = 0; i < steps; i++) {
        final frame = sim.step(segment);
        final us = frame.truth.monotonicUs;
        var accel = frame.accelPhone;
        var gyro = frame.gyroPhone;
        final changed = disturb?.call(index, us, accel, gyro);
        if (changed != null) {
          accel = changed.accel;
          gyro = changed.gyro;
        }
        index++;
        records.add(DriveRecord.imu(monotonicUs: us, accel: accel, gyro: gyro));
        if (inject && us >= nextAiUs) {
          nextAiUs = us + aiEveryUs;
          windows++;
          records.add(DriveRecord.ai(
            monotonicUs: us,
            speed: _prediction(
              model,
              rng,
              trueSpeed: frame.truth.speedMps,
              us: us,
              windows: windows,
              vibrationRms: vibrationRmsAt?.call(us) ?? 0,
            ),
          ));
        }
        if (us >= nextGnssUs) {
          nextGnssUs = us + 1000000;
          if (truth) {
            final t = frame.truth;
            records.add(DriveRecord.truth(
              monotonicUs: us,
              latitude: t.latitude,
              longitude: t.longitude,
              speedMps: t.speedMps,
            ));
          }
          records.add(DriveRecord.gnss(sim.gnss()));
        }
      }
    }
  }

  drive(setup);
  if (setup.isNotEmpty) {
    records.add(DriveRecord.marker(
      monotonicUs: sim.truth.monotonicUs,
      label: OutageBenchmark.startMarker,
    ));
  }
  drive(segments);
  return records;
}

AiSpeedObservation _prediction(
  AiModelProfile model,
  math.Random rng, {
  required double trueSpeed,
  required int us,
  required int windows,
  required double vibrationRms,
}) {
  final noise = model.noiseMps + model.noiseGainWithVibration * vibrationRms;
  final speed =
      math.max(0.0, trueSpeed + model.biasMps + noise * gaussian(rng));
  return AiSpeedObservation(
    speedMps: speed,
    sigmaMps: model.reportedSigmaMps,
    monotonicUs: us,
    latencyMs: model.latencyMs,
    featureZMax: model.featureZ,
    windowsFed: windows,
  );
}

/// The `ai` records of [records].
List<DriveRecord> aiRecordsOf(List<DriveRecord> records) =>
    [for (final r in records) if (r.type == DriveRecordType.ai) r];

/// [records] without their `ai` lines.
List<DriveRecord> withoutAi(List<DriveRecord> records) =>
    [for (final r in records) if (r.type != DriveRecordType.ai) r];

/// [records] with every GNSS fix from [fromUs] on replaced by a "GNSS lost"
/// record: a blackout that never ends.
List<DriveRecord> blackoutFrom(List<DriveRecord> records, int fromUs) => [
      for (final r in records)
        r.type == DriveRecordType.gnss && r.monotonicUs >= fromUs
            ? DriveRecord.gnssLost(r.monotonicUs)
            : r,
    ];
