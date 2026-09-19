import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/sensors/sensor_sample.dart';
import 'package:gatisaarth/core/nav/sensors/time_sync.dart';

SensorSample sample(SensorType type, int us, [List<double>? values]) =>
    SensorSample(
      type: type,
      monotonicUs: us,
      values: values ?? const [1, 2, 3],
    );

void main() {
  group('TimeSync ordering', () {
    test('merges two streams into one timestamp-ordered sequence', () {
      final sync = TimeSync();
      // Accelerometer at 0, 20, 40 ms; gyro at 10, 30 ms — delivered by
      // stream, not interleaved, which is what sensors_plus actually does.
      sync.add(sample(SensorType.accelerometer, 0));
      sync.add(sample(SensorType.accelerometer, 20000));
      sync.add(sample(SensorType.accelerometer, 40000));
      sync.add(sample(SensorType.gyroscope, 10000));
      sync.add(sample(SensorType.gyroscope, 30000));

      // The 40 ms accel sample is deliberately withheld: the gyro's newest is
      // 30 ms, so a gyro sample between 30 and 40 ms could still arrive.
      final out = sync.drain(60000);
      expect(out.map((s) => s.monotonicUs).toList(), [0, 10000, 20000, 30000]);
      expect(out.map((s) => s.type).toList(), [
        SensorType.accelerometer,
        SensorType.gyroscope,
        SensorType.accelerometer,
        SensorType.gyroscope,
      ]);

      // Once the gyro has been quiet past the reorder window it is released.
      expect(sync.drain(400000).map((s) => s.monotonicUs).toList(), [40000]);
    });

    test('output is never out of order across many drains', () {
      final sync = TimeSync();
      var last = -1;
      for (var i = 0; i < 200; i++) {
        sync.add(sample(SensorType.accelerometer, i * 20000));
        if (i.isEven) sync.add(sample(SensorType.gyroscope, i * 20000 + 7000));
        for (final s in sync.drain(i * 20000)) {
          expect(s.monotonicUs, greaterThanOrEqualTo(last));
          last = s.monotonicUs;
        }
      }
    });

    test('holds a sample back while another live stream might still be older',
        () {
      final sync = TimeSync();
      // Both streams active and recent.
      sync.add(sample(SensorType.accelerometer, 0));
      sync.add(sample(SensorType.gyroscope, 0));
      sync.drain(1000);

      // Accel jumps ahead; gyro has been quiet only 5 ms, well inside the
      // 200 ms reorder window, so the accel sample waits.
      sync.add(sample(SensorType.accelerometer, 100000));
      expect(sync.drain(5000), isEmpty);

      // Gyro catches up: the older sample is now decidable and goes first.
      sync.add(sample(SensorType.gyroscope, 50000));
      expect(sync.drain(100000).map((s) => s.monotonicUs).toList(), [50000]);
      // The accel sample follows once the gyro's silence exceeds the window.
      expect(sync.drain(400000).map((s) => s.monotonicUs).toList(), [100000]);
    });

    test('a silent stream stops blocking once the reorder window passes', () {
      final sync = TimeSync();
      sync.add(sample(SensorType.accelerometer, 0));
      sync.add(sample(SensorType.gyroscope, 0));
      sync.drain(1000);

      sync.add(sample(SensorType.accelerometer, 10000));
      // Gyro died at t=0. After 200 ms of silence the accel sample is released
      // instead of stalling the filter forever.
      expect(sync.drain(10000), isEmpty);
      expect(sync.drain(500000).map((s) => s.monotonicUs).toList(), [10000]);
    });

    test('flush releases everything still buffered, in order', () {
      final sync = TimeSync();
      sync.add(sample(SensorType.accelerometer, 30000));
      sync.add(sample(SensorType.gyroscope, 10000));
      sync.add(sample(SensorType.barometer, 20000));
      expect(
        sync.flush().map((s) => s.monotonicUs).toList(),
        [10000, 20000, 30000],
      );
    });
  });

  group('TimeSync rejection', () {
    test('a duplicate timestamp on the same stream is rejected and counted',
        () {
      final sync = TimeSync();
      expect(sync.add(sample(SensorType.accelerometer, 1000)), isTrue);
      expect(sync.add(sample(SensorType.accelerometer, 1000)), isFalse);
      expect(sync.statsFor(SensorType.accelerometer).duplicates, 1);
      expect(sync.statsFor(SensorType.accelerometer).received, 1);
    });

    test('the same timestamp on different streams is not a duplicate', () {
      final sync = TimeSync();
      expect(sync.add(sample(SensorType.accelerometer, 1000)), isTrue);
      expect(sync.add(sample(SensorType.gyroscope, 1000)), isTrue);
      expect(sync.statsFor(SensorType.gyroscope).duplicates, 0);
    });

    test('a sample older than what was already released is dropped', () {
      final sync = TimeSync();
      sync.add(sample(SensorType.accelerometer, 50000));
      sync.drain(500000);
      expect(sync.add(sample(SensorType.accelerometer, 10000)), isFalse);
      expect(sync.statsFor(SensorType.accelerometer).outOfOrder, 1);
    });

    test('out-of-order inside the buffer is re-sorted, not dropped', () {
      final sync = TimeSync();
      sync.add(sample(SensorType.accelerometer, 20000));
      expect(sync.add(sample(SensorType.accelerometer, 10000)), isTrue);
      expect(
        sync.drain(500000).map((s) => s.monotonicUs).toList(),
        [10000, 20000],
      );
      expect(sync.statsFor(SensorType.accelerometer).outOfOrder, 1);
    });

    test('a NaN payload is rejected instead of poisoning the filter', () {
      final sync = TimeSync();
      expect(
        sync.add(sample(SensorType.accelerometer, 1000, [1, double.nan, 3])),
        isFalse,
      );
      expect(
        sync.add(
            sample(SensorType.accelerometer, 2000, [double.infinity, 0, 0])),
        isFalse,
      );
      expect(sync.drain(500000), isEmpty);
    });

    test('the bounded buffer drops oldest rather than growing without limit',
        () {
      const limit = 8;
      final sync = TimeSync(
        config: const NavConfig(sensors: SensorConfig(queueLimit: limit)),
      );
      for (var i = 0; i < 100; i++) {
        sync.add(sample(SensorType.accelerometer, i * 1000));
      }
      final out = sync.drain(1000000);
      expect(out.length, limit);
      // The survivors are the newest ones.
      expect(out.first.monotonicUs, (100 - limit) * 1000);
      expect(sync.bufferOverflows, 100 - limit);
    });
  });

  group('TimeSync statistics', () {
    test('estimates the real delivery rate, not the nominal one', () {
      final sync = TimeSync();
      // Asked for 50 Hz, actually delivering 40 Hz.
      for (var i = 0; i < 60; i++) {
        sync.add(sample(SensorType.accelerometer, i * 25000));
      }
      final hz = sync.statsFor(SensorType.accelerometer).effectiveHz;
      expect(hz, isNotNull);
      expect(hz!, closeTo(40, 0.5));
    });

    test('effective rate is null before there is enough history', () {
      final sync = TimeSync();
      sync.add(sample(SensorType.accelerometer, 0));
      expect(sync.statsFor(SensorType.accelerometer).effectiveHz, isNull);
    });

    test('a gap is counted as dropped samples', () {
      final sync = TimeSync();
      for (var i = 0; i < 40; i++) {
        sync.add(sample(SensorType.accelerometer, i * 20000));
      }
      final before = sync.statsFor(SensorType.accelerometer).dropped;
      // 200 ms hole where 10 samples should have been.
      sync.add(sample(SensorType.accelerometer, 40 * 20000 + 200000));
      final after = sync.statsFor(SensorType.accelerometer).dropped;
      expect(after - before, greaterThanOrEqualTo(9));
    });

    test('a steady stream is excellent, a jittery one is not', () {
      final steady = TimeSync();
      for (var i = 0; i < 60; i++) {
        steady.add(sample(SensorType.accelerometer, i * 20000));
      }
      expect(
        steady.statsFor(SensorType.accelerometer).quality,
        SampleQuality.excellent,
      );

      final jittery = TimeSync();
      var t = 0;
      for (var i = 0; i < 60; i++) {
        t += i.isEven ? 6000 : 34000; // same mean, heavy jitter
        jittery.add(sample(SensorType.accelerometer, t));
      }
      expect(
        jittery.statsFor(SensorType.accelerometer).quality,
        isNot(SampleQuality.excellent),
      );
    });

    test('an untouched sensor reports unavailable, not zero', () {
      final sync = TimeSync()..expect([SensorType.barometer]);
      final stats = sync.statsFor(SensorType.barometer);
      expect(stats.available, isFalse);
      expect(stats.effectiveHz, isNull);
      expect(stats.source, DataSource.unavailable);
    });

    test('capability detection waits for the probe window before giving up',
        () {
      final sync = TimeSync(
        config: const NavConfig(
          sensors: SensorConfig(capabilityProbe: Duration(seconds: 3)),
        ),
      )..expect([SensorType.accelerometer, SensorType.barometer]);
      sync.add(sample(SensorType.accelerometer, 0));

      expect(sync.isUnavailable(SensorType.barometer, 1000000), isFalse);
      expect(sync.isUnavailable(SensorType.barometer, 4000000), isTrue);
      expect(sync.isUnavailable(SensorType.accelerometer, 4000000), isFalse);
    });

    test('availability reports only streams that really delivered', () {
      final sync = TimeSync()
        ..expect([
          SensorType.accelerometer,
          SensorType.gyroscope,
          SensorType.magnetometer,
        ]);
      sync.add(sample(SensorType.accelerometer, 0));
      sync.add(sample(SensorType.gyroscope, 0));

      final availability = sync.availability;
      expect(availability.has(SensorType.accelerometer), isTrue);
      expect(availability.has(SensorType.magnetometer), isFalse);
      expect(availability.hasMinimumViableSet, isTrue);
    });

    test('losing the gyroscope breaks the minimum viable set', () {
      final sync = TimeSync();
      sync.add(sample(SensorType.accelerometer, 0));
      sync.add(sample(SensorType.magnetometer, 0));
      expect(sync.availability.hasMinimumViableSet, isFalse);
    });

    test('sequence numbers are per stream and gapless for accepted samples',
        () {
      final sync = TimeSync();
      sync.add(sample(SensorType.accelerometer, 0));
      sync.add(sample(SensorType.gyroscope, 1000));
      sync.add(sample(SensorType.accelerometer, 2000));
      final out = sync.drain(500000);
      final accel =
          out.where((s) => s.type == SensorType.accelerometer).toList();
      final gyro = out.where((s) => s.type == SensorType.gyroscope).toList();
      expect(accel.map((s) => s.sequence).toList(), [1, 2]);
      expect(gyro.map((s) => s.sequence).toList(), [1]);
    });
  });
}
