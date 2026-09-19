import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_quality.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/model/nav_snapshot.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';
import 'package:gatisaarth/core/nav/replay/drive_recorder.dart';
import 'package:gatisaarth/core/nav/replay/replay_engine.dart';

import 'support/drive_simulator.dart';

/// Records a synthetic drive, returning the JSONL lines and the live engine's
/// final snapshot for comparison.
({List<String> lines, NavigationSnapshot live, DriveRecorder recorder})
    recordDrive({
  List<DriveSegment>? extra,
  bool withTruth = true,
  bool cutGnssAfter = false,
  int imuDecimation = 1,
}) {
  final sink = MemoryLogSink();
  final recorder = DriveRecorder(sink: sink, imuDecimation: imuDecimation);
  recorder.start(const DriveMeta(
    sessionId: 'test-session',
    startedAtMs: 1695000000000,
    deviceModel: 'Test Phone',
    vehicle: 'car',
    mountDescription: 'tilted console',
    configVersion: 1,
  ));

  final engine = NavigationEngine();
  final sim = DriveSimulator(mount: PhoneMount.tilted());
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
        engine.onImu(
          accelPhone: frame.accelPhone,
          gyroPhone: frame.gyroPhone,
          monotonicUs: frame.truth.monotonicUs,
        );
        if (withTruth && frame.truth.monotonicUs % 1000000 == 0) {
          recorder.recordTruth(
            monotonicUs: frame.truth.monotonicUs,
            latitude: frame.truth.latitude,
            longitude: frame.truth.longitude,
            headingDeg:
                NavMath.wrap360(frame.truth.headingRad * NavMath.radToDeg),
            speedMps: frame.truth.speedMps,
          );
        }
        if (frame.truth.monotonicUs >= nextGnssUs) {
          nextGnssUs = frame.truth.monotonicUs + 1000000;
          if (gnssOn) {
            final fix = sim.gnss();
            recorder.recordGnss(fix);
            engine.onGnss(fix);
          } else {
            recorder.recordGnssLost(frame.truth.monotonicUs);
            engine.onGnssLost(frame.truth.monotonicUs);
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
  if (cutGnssAfter) {
    recorder.recordMarker(
      monotonicUs: sim.truth.monotonicUs,
      label: 'tunnel entry',
    );
    gnssOn = false;
    drive(const [DriveSegment(seconds: 30)]);
    recorder.recordMarker(
      monotonicUs: sim.truth.monotonicUs,
      label: 'tunnel exit',
    );
  }
  if (extra != null) drive(extra);
  recorder.stop();

  return (
    lines: sink.lines,
    live: engine.snapshot!,
    recorder: recorder,
  );
}

void main() {
  group('DriveRecord encoding', () {
    test('an IMU record round-trips exactly, to the last bit', () {
      // Replay is only meaningful if the log is lossless. Rounding to
      // "sensible" decimals would make a replay a different experiment.
      final original = DriveRecord.imu(
        monotonicUs: 1234567890,
        accel: Vector3(0.12345678901234567, -9.806650000000001, 1e-9),
        gyro: Vector3(-0.0012345678, 3.14159265358979, 0),
        mag: Vector3(22.5, -3.25, 41.125),
        pressureHpa: 1013.2500000001,
        temperatureC: 31.456789,
      );
      final restored = DriveRecord.fromJsonLine(original.toJsonLine())!;

      expect(restored.accel!.x, original.accel!.x);
      expect(restored.accel!.y, original.accel!.y);
      expect(restored.accel!.z, original.accel!.z);
      expect(restored.gyro!.y, original.gyro!.y);
      expect(restored.mag!.z, original.mag!.z);
      expect(restored.pressureHpa, original.pressureHpa);
      expect(restored.temperatureC, original.temperatureC);
      expect(restored.monotonicUs, original.monotonicUs);
    });

    test('a GNSS record keeps every field, including the absent ones', () {
      const fix = GnssObservation(
        latitudeDeg: 28.613912345678,
        longitudeDeg: 77.209087654321,
        accuracyM: 4.75,
        monotonicUs: 999,
        altitudeM: 216.5,
        speedMps: 13.25,
        bearingDeg: 271.5,
        isMocked: true,
      );
      final restored =
          DriveRecord.fromJsonLine(DriveRecord.gnss(fix).toJsonLine())!.fix!;
      expect(restored.latitudeDeg, fix.latitudeDeg);
      expect(restored.longitudeDeg, fix.longitudeDeg);
      expect(restored.accuracyM, fix.accuracyM);
      expect(restored.bearingDeg, fix.bearingDeg);
      expect(restored.isMocked, isTrue);
      // Never stated, so never invented.
      expect(restored.satellitesUsed, isNull);
      expect(restored.verticalAccuracyM, isNull);
    });

    test('markers and truth round-trip', () {
      final marker = DriveRecord.fromJsonLine(
        DriveRecord.marker(monotonicUs: 42, label: 'pothole').toJsonLine(),
      )!;
      expect(marker.type, DriveRecordType.marker);
      expect(marker.label, 'pothole');

      final truth = DriveRecord.fromJsonLine(
        DriveRecord.truth(
          monotonicUs: 7,
          latitude: 1.5,
          longitude: 2.5,
          headingDeg: 90,
          speedMps: 11,
        ).toJsonLine(),
      )!;
      expect(truth.latitude, 1.5);
      expect(truth.headingDeg, 90);
    });

    test('a corrupt line is skipped, not thrown', () {
      expect(DriveRecord.fromJsonLine('not json'), isNull);
      expect(DriveRecord.fromJsonLine('{"t":"i"}'), isNull);
      expect(DriveRecord.fromJsonLine('{"t":"?","u":1}'), isNull);
      expect(DriveRecord.fromJsonLine(''), isNull);
      // A line truncated mid-write by a dying battery.
      expect(DriveRecord.fromJsonLine('{"t":"i","u":1,"a":[0.1,0.2'), isNull);
    });

    test('drive metadata round-trips and stays honest about gaps', () {
      const meta = DriveMeta(
        sessionId: 'abc',
        startedAtMs: 1695000000000,
        deviceModel: 'Pixel 9',
        vehicle: 'twoWheeler',
      );
      final restored = DriveMeta.fromJson(meta.toJson())!;
      expect(restored.sessionId, 'abc');
      expect(restored.deviceModel, 'Pixel 9');
      expect(restored.vehicle, 'twoWheeler');
      // Not supplied, so not guessed.
      expect(restored.weather, isNull);
      expect(restored.roadType, isNull);
    });
  });

  group('DriveRecorder', () {
    test('writes a header then the drive', () {
      final result = recordDrive();
      expect(result.lines.first, contains('"t":"m"'));
      expect(result.lines.first, contains('test-session'));
      expect(result.recorder.counts['imu'], greaterThan(1000));
      expect(result.recorder.counts['gnss'], greaterThan(100));
      expect(result.recorder.duration.inSeconds, greaterThan(100));
    });

    test('records rejected fixes too — a replay needs them', () {
      final sink = MemoryLogSink();
      final recorder = DriveRecorder(sink: sink);
      recorder.start(const DriveMeta(sessionId: 's', startedAtMs: 0));
      // Null island: the quality engine will reject it, but it still happened.
      recorder.recordGnss(const GnssObservation(
        latitudeDeg: 0,
        longitudeDeg: 0,
        accuracyM: 5,
        monotonicUs: 1000,
      ));
      expect(recorder.counts['gnss'], 1);
    });

    test('stops itself at the record limit instead of filling the phone', () {
      final sink = MemoryLogSink();
      final recorder = DriveRecorder(sink: sink, maxRecords: 10);
      recorder.start(const DriveMeta(sessionId: 's', startedAtMs: 0));
      for (var i = 0; i < 100; i++) {
        recorder.recordImu(
          monotonicUs: i * 20000,
          accel: Vector3(0, 0, -9.81),
          gyro: Vector3.zero(),
        );
      }
      expect(recorder.recordCount, 10);
      expect(recorder.isFull, isTrue);
      expect(recorder.isRecording, isFalse);
      expect(recorder.droppedRecords, greaterThan(0));
    });

    test('nothing is written before start or after stop', () {
      final sink = MemoryLogSink();
      final recorder = DriveRecorder(sink: sink);
      recorder.recordImu(
        monotonicUs: 0,
        accel: Vector3(0, 0, -9.81),
        gyro: Vector3.zero(),
      );
      expect(sink.lines, isEmpty);

      recorder.start(const DriveMeta(sessionId: 's', startedAtMs: 0));
      recorder.stop();
      recorder.recordImu(
        monotonicUs: 1,
        accel: Vector3(0, 0, -9.81),
        gyro: Vector3.zero(),
      );
      expect(sink.lines, hasLength(1)); // the header only
    });

    test('decimation trades fidelity for size, and says so in the count', () {
      final full = recordDrive();
      final thinned = recordDrive(imuDecimation: 5);
      expect(
        thinned.recorder.counts['imu']!,
        closeTo(full.recorder.counts['imu']! / 5, 5),
      );
    });
  });

  group('ReplayEngine determinism', () {
    test('a replay reproduces the live run exactly', () {
      final recorded = recordDrive();
      final replay = ReplayEngine.fromLines(recorded.lines);
      final summary = replay.runToEnd();

      expect(replay.skippedLines, 0);
      final replayed = summary.finalSnapshot!;

      // Not "close to": identical. The engine has no clock and no randomness,
      // and the log is lossless, so anything less would be a bug.
      expect(replayed.latitude, recorded.live.latitude);
      expect(replayed.longitude, recorded.live.longitude);
      expect(replayed.speedMps, recorded.live.speedMps);
      expect(replayed.headingDeg, recorded.live.headingDeg);
      expect(replayed.horizontalSigmaM, recorded.live.horizontalSigmaM);
      expect(replayed.mode, recorded.live.mode);
      expect(replayed.integrity, recorded.live.integrity);
    });

    test('replaying twice gives byte-identical results', () {
      final recorded = recordDrive();
      final first = ReplayEngine.fromLines(recorded.lines).runToEnd();
      final second = ReplayEngine.fromLines(recorded.lines).runToEnd();

      expect(second.finalSnapshot!.latitude, first.finalSnapshot!.latitude);
      expect(second.finalSnapshot!.longitude, first.finalSnapshot!.longitude);
      expect(second.finalErrorM, first.finalErrorM);
      expect(second.maxErrorM, first.maxErrorM);
      expect(second.snapshots, first.snapshots);
      expect(
        second.modeTransitions.map((t) => '${t.to.name}@${t.monotonicUs}'),
        first.modeTransitions.map((t) => '${t.to.name}@${t.monotonicUs}'),
      );
    });

    test('reset and replay gives the same answer again', () {
      final recorded = recordDrive();
      final replay = ReplayEngine.fromLines(recorded.lines);
      final first = replay.runToEnd();
      replay.reset();
      final second = replay.runToEnd();
      expect(second.finalSnapshot!.latitude, first.finalSnapshot!.latitude);
      expect(second.finalErrorM, first.finalErrorM);
    });

    test('seeking re-derives the state rather than guessing it', () {
      final recorded = recordDrive();
      final a = ReplayEngine.fromLines(recorded.lines);
      final b = ReplayEngine.fromLines(recorded.lines);

      final midUs = a._halfwayUs();
      a.runTo(midUs);
      // b goes the long way round: to the end, then seek back.
      b.runToEnd();
      b.seekTo(midUs);

      expect(b.engine.snapshot!.latitude, a.engine.snapshot!.latitude);
      expect(b.engine.snapshot!.longitude, a.engine.snapshot!.longitude);
      expect(b.index, a.index);
    });
  });

  group('ReplayEngine scoring', () {
    test('scores against the ground truth in the log', () {
      final recorded = recordDrive(cutGnssAfter: true);
      final summary = ReplayEngine.fromLines(recorded.lines).runToEnd();

      expect(summary.hasGroundTruth, isTrue);
      expect(summary.truthSamples, greaterThan(100));
      expect(summary.finalErrorM, isNotNull);
      expect(summary.maxErrorM! >= summary.p95ErrorM!, isTrue);
      expect(summary.p95ErrorM! >= summary.meanErrorM! - 1e-9, isTrue);
      // A 30 s outage after a clean lock should still be tens of metres.
      expect(summary.finalErrorM!, lessThan(100));
    });

    test('a log without truth scores nothing rather than inventing it', () {
      final recorded = recordDrive(withTruth: false);
      final summary = ReplayEngine.fromLines(recorded.lines).runToEnd();
      expect(summary.hasGroundTruth, isFalse);
      expect(summary.finalErrorM, isNull);
      expect(summary.maxErrorM, isNull);
      expect(summary.meanErrorM, isNull);
    });

    test('markers and mode transitions survive the replay', () {
      final recorded = recordDrive(cutGnssAfter: true);
      final summary = ReplayEngine.fromLines(recorded.lines).runToEnd();
      expect(
        summary.markers.map((m) => m.label),
        containsAll(['tunnel entry', 'tunnel exit']),
      );
      expect(
        summary.modeTransitions.map((t) => t.to),
        contains(NavMode.deadReckoning),
      );
      expect(summary.modeTransitions.every((t) => t.reason.isNotEmpty), isTrue);
    });

    test('metadata is read back from the log header', () {
      final recorded = recordDrive();
      final replay = ReplayEngine.fromLines(recorded.lines);
      expect(replay.meta, isNotNull);
      expect(replay.meta!.sessionId, 'test-session');
      expect(replay.meta!.deviceModel, 'Test Phone');
      expect(replay.meta!.mountDescription, 'tilted console');
    });

    test('a truncated log replays as far as it goes', () {
      final recorded = recordDrive();
      final truncated = [
        ...recorded.lines.take(recorded.lines.length ~/ 2),
        '{"t":"i","u":999,"a":[0.1,0.2', // cut off mid-write
      ];
      final replay = ReplayEngine.fromLines(truncated);
      final summary = replay.runToEnd();
      expect(replay.skippedLines, 1);
      expect(summary.records, recorded.lines.length ~/ 2);
      expect(summary.finalSnapshot, isNotNull);
    });

    test('progress runs from zero to one', () {
      final recorded = recordDrive();
      final replay = ReplayEngine.fromLines(recorded.lines);
      expect(replay.progress, 0);
      replay.stepOnce();
      expect(replay.progress, greaterThan(0));
      replay.runToEnd();
      expect(replay.progress, 1);
      expect(replay.isFinished, isTrue);
      expect(replay.stepOnce(), isNull);
    });
  });
}

extension on ReplayEngine {
  /// Timestamp halfway through the log, for the seek test.
  int _halfwayUs() {
    final first = recordCount == 0 ? 0 : 0;
    runToEnd();
    final last = currentUs ?? 0;
    reset();
    return first + (last ~/ 2);
  }
}
