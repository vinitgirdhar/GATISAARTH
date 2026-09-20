import 'package:gatisaarth/core/nav/benchmark/outage_benchmark.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

import 'drive_simulator.dart';

/// Turns a simulated drive into the same JSONL records a phone would record:
/// a header, phone-frame IMU at [DriveSimulator.imuHz], and a GNSS fix once a
/// second. No truth records - the benchmark scores against the fixes, exactly
/// as it must on a real drive that has no reference receiver.
///
/// [setup] is driving that exists only to calibrate the mount (the straight
/// accelerate/brake cycles a real driver gives the alignment). It is recorded,
/// then a [OutageBenchmark.startMarker] is dropped so scoring starts after it.
List<DriveRecord> simulateDriveLog({
  required List<DriveSegment> segments,
  List<DriveSegment> setup = const [],
  PhoneMount? mount,
  int seed = 42,
  double gnssAccuracy = 5,
  String deviceModel = 'simulator',
  String? vehicle,
}) {
  final sim = DriveSimulator(
    mount: mount ?? PhoneMount.tilted(),
    seed: seed,
    gnssAccuracy: gnssAccuracy,
  );
  final records = <DriveRecord>[
    DriveRecord(
      type: DriveRecordType.meta,
      monotonicUs: 0,
      meta: DriveMeta(
        sessionId: 'simulated-$seed',
        startedAtMs: 0,
        deviceModel: deviceModel,
        vehicle: vehicle,
        notes: 'Simulated drive. Not a field measurement.',
      ).toJson(),
    ),
  ];

  var nextGnssUs = 0;
  void drive(List<DriveSegment> list) {
    for (final segment in list) {
      final steps = (segment.seconds * sim.imuHz).round();
      for (var i = 0; i < steps; i++) {
        final frame = sim.step(segment);
        final us = frame.truth.monotonicUs;
        records.add(DriveRecord.imu(
          monotonicUs: us,
          accel: frame.accelPhone,
          gyro: frame.gyroPhone,
        ));
        if (us >= nextGnssUs) {
          nextGnssUs = us + 1000000;
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

/// The bundled reference drive, after the calibration set-up: two laps of
/// ordinary city driving - bends, a red light, hard stops, pulling away.
/// Simulated, and labelled as such wherever it is shown.
List<DriveSegment> referenceCityDrive() => const [
      // Lap A
      DriveSegment(seconds: 8, longitudinalAccel: 1.6),
      DriveSegment(seconds: 14),
      DriveSegment(seconds: 7, yawRate: 0.10),
      DriveSegment(seconds: 12),
      DriveSegment(seconds: 6, longitudinalAccel: -1.4),
      DriveSegment(seconds: 4, yawRate: -0.22),
      DriveSegment(seconds: 6, longitudinalAccel: 1.8),
      DriveSegment(seconds: 16),
      DriveSegment(seconds: 7, longitudinalAccel: -2.0),
      DriveSegment(seconds: 2, longitudinalAccel: -1.0),
      DriveSegment(seconds: 12),
      DriveSegment(seconds: 8, longitudinalAccel: 1.5),
      DriveSegment(seconds: 10),
      DriveSegment(seconds: 8, yawRate: -0.09),
      DriveSegment(seconds: 14),
      DriveSegment(seconds: 5, longitudinalAccel: -1.2),
      DriveSegment(seconds: 5, longitudinalAccel: 1.4),
      DriveSegment(seconds: 15),
      // Lap B
      DriveSegment(seconds: 6, longitudinalAccel: -1.6),
      DriveSegment(seconds: 5, yawRate: 0.25),
      DriveSegment(seconds: 7, longitudinalAccel: 2.0),
      DriveSegment(seconds: 18),
      DriveSegment(seconds: 9, yawRate: 0.07),
      DriveSegment(seconds: 12),
      DriveSegment(seconds: 7, longitudinalAccel: -2.4),
      DriveSegment(seconds: 9),
      DriveSegment(seconds: 10, longitudinalAccel: 1.3),
      DriveSegment(seconds: 12),
      DriveSegment(seconds: 6, yawRate: -0.12),
      DriveSegment(seconds: 10),
      DriveSegment(seconds: 6, longitudinalAccel: -1.0),
      DriveSegment(seconds: 6, longitudinalAccel: 1.2),
      DriveSegment(seconds: 20),
      DriveSegment(seconds: 8, longitudinalAccel: -1.8),
      DriveSegment(seconds: 6),
    ];

/// The mount-calibration drive that precedes [referenceCityDrive].
List<DriveSegment> referenceSetupDrive() => calibrationDrive();
