import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/ai/ai_types.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';
import 'package:gatisaarth/core/nav/replay/drive_recorder.dart';
import 'package:gatisaarth/core/nav/replay/replay_engine.dart';

const _speed = AiSpeedObservation(
  speedMps: 12.345678901234567,
  sigmaMps: 0.4123456789,
  monotonicUs: 1789898939927459,
  latencyMs: 4.25,
  featureZMax: 2.718281828,
  windowsFed: 57,
);

DisturbanceEstimate _disturbance(int us) => DisturbanceEstimate(
      vibrationScore: 0.6180339887,
      vibrationClass: DisturbanceClass.high,
      motionQuality: 0.4142135623,
      monotonicUs: us,
      shock: ShockKind.pothole,
    );

FusionConfidence _fusion(int us) =>
    FusionConfidence(gnssTrust: 0.7071067811, insTrust: 0.5, monotonicUs: us);

Map<String, dynamic> _json(DriveRecord r) =>
    jsonDecode(r.toJsonLine()) as Map<String, dynamic>;

DriveRecord? _parse(String line) => DriveRecord.fromJsonLine(line);

void main() {
  group('the ai record, as a Python job writes it', () {
    test('a full record has exactly these keys', () {
      final r = DriveRecord.ai(
        monotonicUs: _speed.monotonicUs,
        speed: _speed,
        disturbance: _disturbance(_speed.monotonicUs),
        fusion: _fusion(_speed.monotonicUs),
      );
      expect(_json(r).keys.toSet(), {
        't', 'u', // record type "a", time in us on the IMU clock
        'spd', 'sig', 'lms', 'fz', 'win', // speed group
        'vib', 'vcl', 'shk', 'mq', // disturbance group
        'gt', 'it', // fusion group
      });
      expect(_json(r)['t'], 'a');
    });

    test('a group is written only when the record carries it', () {
      final speedOnly =
          DriveRecord.ai(monotonicUs: 5, speed: _speed.copyForTest(5));
      expect(_json(speedOnly).keys.toSet(),
          {'t', 'u', 'spd', 'sig', 'lms', 'fz', 'win'});
      final disturbanceOnly =
          DriveRecord.ai(monotonicUs: 5, disturbance: _disturbance(5));
      expect(_json(disturbanceOnly).keys.toSet(),
          {'t', 'u', 'vib', 'vcl', 'shk', 'mq'});
      final fusionOnly = DriveRecord.ai(monotonicUs: 5, fusion: _fusion(5));
      expect(_json(fusionOnly).keys.toSet(), {'t', 'u', 'gt', 'it'});
    });

    test('the enums are written as their indices', () {
      final r = DriveRecord.ai(
          monotonicUs: 5, disturbance: _disturbance(5));
      expect(_json(r)['vcl'], 2); // 0 low, 1 normal, 2 high
      expect(_json(r)['shk'], 2); // 0 none, 1 bump, 2 pothole, 3 jolt
      expect(DisturbanceClass.values.map((c) => c.name),
          ['low', 'normal', 'high']);
      expect(ShockKind.values.map((c) => c.name),
          ['none', 'bump', 'pothole', 'jolt']);
    });

    test('every value survives the round trip to the last bit', () {
      final us = _speed.monotonicUs;
      final original = DriveRecord.ai(
        monotonicUs: us,
        speed: _speed,
        disturbance: _disturbance(us),
        fusion: _fusion(us),
      );
      final restored = _parse(original.toJsonLine())!;
      expect(restored.type, DriveRecordType.ai);
      expect(restored.monotonicUs, us);
      final s = restored.aiSpeed!;
      expect(s.speedMps, _speed.speedMps);
      expect(s.sigmaMps, _speed.sigmaMps);
      expect(s.latencyMs, _speed.latencyMs);
      expect(s.featureZMax, _speed.featureZMax);
      expect(s.windowsFed, _speed.windowsFed);
      expect(s.monotonicUs, us);
      final d = restored.disturbance!;
      expect(d.vibrationScore, 0.6180339887);
      expect(d.vibrationClass, DisturbanceClass.high);
      expect(d.motionQuality, 0.4142135623);
      expect(d.shock, ShockKind.pothole);
      expect(d.source, EstimateSource.model);
      final f = restored.fusion!;
      expect(f.gnssTrust, 0.7071067811);
      expect(f.insTrust, 0.5);
    });

    test('a hand-written minimal line parses with honest defaults', () {
      final speed = _parse('{"t":"a","u":5000000,"spd":12.5,"sig":0.4}')!;
      expect(speed.aiSpeed!.speedMps, 12.5);
      expect(speed.aiSpeed!.latencyMs, 0);
      expect(speed.aiSpeed!.featureZMax, 0);
      // No warm-up count given means "no warm-up information": not held back.
      expect(speed.aiSpeed!.windowsFed, greaterThan(1000));
      expect(speed.disturbance, isNull);
      expect(speed.fusion, isNull);

      final dist = _parse('{"t":"a","u":5,"vib":0.7,"mq":0.4}')!;
      expect(dist.disturbance!.vibrationClass, DisturbanceClass.high);
      expect(dist.disturbance!.shock, ShockKind.none);
      expect(_parse('{"t":"a","u":5,"vib":0.1,"mq":0.9}')!
          .disturbance!.vibrationClass, DisturbanceClass.low);
      expect(_parse('{"t":"a","u":5,"vib":0.4,"mq":0.9}')!
          .disturbance!.vibrationClass, DisturbanceClass.normal);

      final fusion = _parse('{"t":"a","u":5,"gt":0.5}')!;
      expect(fusion.fusion!.gnssTrust, 0.5);
      expect(fusion.fusion!.insTrust, 1.0);
      expect(_parse('{"t":"a","u":5,"it":0.25}')!.fusion!.gnssTrust, 1.0);
    });

    test('integers written as JSON ints (as Python does) are accepted', () {
      final r = _parse('{"t":"a","u":100,"spd":10,"sig":1,"win":20}')!;
      expect(r.aiSpeed!.speedMps, 10.0);
      expect(r.aiSpeed!.windowsFed, 20);
    });

    test('a record with no usable group is unreadable, not empty', () {
      expect(_parse('{"t":"a","u":5}'), isNull);
      // A group needs its required keys: spd AND sig, vib AND mq.
      expect(_parse('{"t":"a","u":5,"spd":1.0}'), isNull);
      expect(_parse('{"t":"a","u":5,"vib":0.5}'), isNull);
      expect(_parse('{"t":"a","spd":1.0,"sig":0.4}'), isNull);
      expect(_parse('{"t":"a","u":5,"spd":"fast","sig":0.4}'), isNull);
    });

    test('an out-of-range class or shock index falls back rather than crashes',
        () {
      final r = _parse(
          '{"t":"a","u":5,"vib":0.9,"mq":0.5,"vcl":9,"shk":-1}')!;
      expect(r.disturbance!.vibrationClass, DisturbanceClass.high);
      expect(r.disturbance!.shock, ShockKind.none);
    });

    test('a line cut off mid-write is skipped, as for every other record', () {
      expect(_parse('{"t":"a","u":5,"spd":12.5,"sig'), isNull);
    });
  });

  group('recording', () {
    test('an ai record follows the IMU line it describes, and is counted', () {
      final sink = MemoryLogSink();
      final recorder = DriveRecorder(sink: sink)
        ..start(const DriveMeta(sessionId: 's', startedAtMs: 0));
      recorder.recordImu(
          monotonicUs: 1000, accel: Vector3(0, 0, -9.8), gyro: Vector3.zero());
      recorder.recordAi(monotonicUs: 1000, speed: _speed.copyForTest(1000));
      expect(recorder.counts['ai'], 1);
      expect(sink.lines[1], contains('"t":"i"'));
      expect(sink.lines[2], contains('"t":"a"'));
    });

    test('nothing is written before start, after stop, or for an empty record',
        () {
      final sink = MemoryLogSink();
      final recorder = DriveRecorder(sink: sink);
      recorder.recordAi(monotonicUs: 1, speed: _speed.copyForTest(1));
      expect(sink.lines, isEmpty);
      recorder.start(const DriveMeta(sessionId: 's', startedAtMs: 0));
      recorder.recordAi(monotonicUs: 2); // nothing to say
      expect(sink.lines, hasLength(1)); // the header only
      recorder.stop();
      recorder.recordAi(monotonicUs: 3, speed: _speed.copyForTest(3));
      expect(sink.lines, hasLength(1));
    });
  });

  group('replay of old and new logs', () {
    test('a log written before the ai record existed replays without a single '
        'skipped line', () {
      final legacy = [
        '{"t":"m","u":0,"sid":"old","start":0}',
        '{"t":"i","u":1000000,"a":[0.1,0.2,9.8],"g":[0,0,0]}',
        '{"t":"g","u":1000000,"lat":28.6139,"lon":77.209,"acc":5.0}',
      ];
      final replay = ReplayEngine.fromLines(legacy)..runToEnd();
      expect(replay.skippedLines, 0);
      expect(replay.recordCount, 3);
    });

    test('ai lines are fed to the engine in order, alongside the sensors', () {
      final lines = [
        '{"t":"i","u":1000000,"a":[0.1,0.2,9.8],"g":[0,0,0]}',
        '{"t":"a","u":1000000,"spd":3.0,"sig":0.5}',
        '{"t":"i","u":1020000,"a":[0.1,0.2,9.8],"g":[0,0,0]}',
      ];
      final replay = ReplayEngine.fromLines(lines);
      expect(replay.recordCount, 3);
      final types = <DriveRecordType>[];
      while (!replay.isFinished) {
        types.add(replay.stepOnce()!.record.type);
      }
      expect(types,
          [DriveRecordType.imu, DriveRecordType.ai, DriveRecordType.imu]);
      // The default engine has the AI off: it ignored the line but counted it.
      expect(replay.engine.aiDiagnostics.enabled, isFalse);
    });
  });
}

extension on AiSpeedObservation {
  AiSpeedObservation copyForTest(int us) => AiSpeedObservation(
        speedMps: speedMps,
        sigmaMps: sigmaMps,
        monotonicUs: us,
        latencyMs: latencyMs,
        featureZMax: featureZMax,
        windowsFed: windowsFed,
      );
}
