import 'dart:collection';
import 'dart:math' as math;

import '../nav_config.dart';
import 'sensor_sample.dart';

/// Per-stream timing bookkeeping: rate, jitter, drops, duplicates, order (§4).
class _Timeline {
  _Timeline(this.type, this.config);

  final SensorType type;
  final SensorConfig config;

  int received = 0;
  int dropped = 0;
  int duplicates = 0;
  int outOfOrder = 0;

  int? lastUs;
  int? firstUs;
  double? meanIntervalUs;
  double _intervalVarianceUs2 = 0;
  int _sequence = 0;

  /// Returns the interval to the previous accepted sample, or null when this
  /// is the first one.
  double? note(int monotonicUs) {
    received++;
    firstUs ??= monotonicUs;
    final prev = lastUs;
    lastUs = monotonicUs;
    if (prev == null) return null;

    final interval = (monotonicUs - prev).toDouble();
    final mean = meanIntervalUs;
    if (mean == null) {
      meanIntervalUs = interval;
    } else {
      final a = config.rateEstimatorAlpha;
      final delta = interval - mean;
      meanIntervalUs = mean + a * delta;
      // EWMA variance of the interval, for the jitter ratio.
      _intervalVarianceUs2 =
          (1 - a) * (_intervalVarianceUs2 + a * delta * delta);
      if (interval > mean * config.gapFactor) {
        // A gap this long means the platform produced samples we never saw.
        dropped += math.max(1, (interval / mean).round() - 1);
      }
    }
    return interval;
  }

  int nextSequence() => ++_sequence;

  double? get effectiveHz {
    final mean = meanIntervalUs;
    if (mean == null || mean <= 0 || received < 3) return null;
    return 1e6 / mean;
  }

  double? get jitterRatio {
    final mean = meanIntervalUs;
    if (mean == null || mean <= 0 || received < 5) return null;
    return math.sqrt(_intervalVarianceUs2) / mean;
  }

  SampleQuality get quality {
    if (received == 0) return SampleQuality.invalid;
    if (received < 5) return SampleQuality.good;
    final jitter = jitterRatio;
    if (jitter == null) return SampleQuality.good;
    final drops = received + dropped == 0 ? 0.0 : dropped / (received + dropped);
    if (drops > config.degradedDropRate * 4) return SampleQuality.invalid;
    if (drops > config.degradedDropRate) return SampleQuality.degraded;
    if (jitter <= config.excellentJitterRatio) return SampleQuality.excellent;
    if (jitter <= config.goodJitterRatio) return SampleQuality.good;
    return SampleQuality.degraded;
  }

  SensorStreamStats stats() => SensorStreamStats(
        type: type,
        quality: quality,
        received: received,
        dropped: dropped,
        duplicates: duplicates,
        outOfOrder: outOfOrder,
        effectiveHz: effectiveHz,
        jitterRatio: jitterRatio,
        lastSampleUs: lastUs,
        available: received > 0,
      );
}

/// Merges several sensor streams into one monotonically ordered stream (§4).
///
/// Sensors arrive on independent callbacks, so a gyro sample timestamped
/// *before* an accelerometer sample can still be delivered after it. Feeding
/// the filter in arrival order integrates rates against the wrong interval.
/// [TimeSync] holds each sample only as long as it must to guarantee ordering,
/// then releases it.
///
/// Release rule: a buffered sample may be emitted once every other *live*
/// stream has either produced something at least as new, or has gone quiet
/// past the reorder window. That bounds added latency by
/// [SensorConfig.reorderWindow] and never reorders across it.
///
/// Deliberately does **not** interpolate. §4 allows it "where justified";
/// nothing here is yet — resampling a 15 Hz magnetometer up to 50 Hz would
/// invent measurements the filter would then treat as independent.
class TimeSync {
  TimeSync({NavConfig config = NavConfig.defaults})
      : _config = config.sensors,
        _capabilityProbe = config.sensors.capabilityProbe;

  final SensorConfig _config;
  final Duration _capabilityProbe;

  final Map<SensorType, _Timeline> _timelines = {};
  final Map<SensorType, Queue<SensorSample>> _buffers = {};
  final Set<SensorType> _expected = {};

  int _bufferOverflows = 0;
  int? _startUs;
  int? _lastReleasedUs;

  /// Tell the sync which streams this device is expected to deliver, so a
  /// silent stream can be told apart from one that simply has not started.
  void expect(Iterable<SensorType> types) => _expected.addAll(types);

  int get bufferOverflows => _bufferOverflows;

  /// Streams that have actually produced at least one sample.
  SensorAvailability get availability => SensorAvailability(
        _timelines.entries
            .where((e) => e.value.received > 0)
            .map((e) => e.key)
            .toSet(),
      );

  Map<SensorType, SensorStreamStats> get stats => {
        for (final type in {..._expected, ..._timelines.keys})
          type: _timelines[type]?.stats() ??
              SensorStreamStats.unavailable(type),
      };

  SensorStreamStats statsFor(SensorType type) =>
      _timelines[type]?.stats() ?? SensorStreamStats.unavailable(type);

  /// A stream is unavailable once the capability probe window has passed with
  /// nothing delivered (§3).
  bool isUnavailable(SensorType type, int nowUs) {
    if ((_timelines[type]?.received ?? 0) > 0) return false;
    final start = _startUs;
    if (start == null) return false;
    return nowUs - start > _capabilityProbe.inMicroseconds;
  }

  /// Accepts a raw sample. Returns false when it was rejected as a duplicate,
  /// as out-of-order beyond the reorder window, or as invalid.
  bool add(SensorSample sample) {
    _startUs ??= sample.monotonicUs;
    final timeline = _timelines.putIfAbsent(
      sample.type,
      () => _Timeline(sample.type, _config),
    );
    final buffer = _buffers.putIfAbsent(sample.type, () => Queue<SensorSample>());

    if (!sample.values.every((v) => v.isFinite)) {
      timeline.received++;
      return false;
    }

    // Duplicate: same stream, same event time.
    if (timeline.lastUs == sample.monotonicUs ||
        buffer.any((s) => s.monotonicUs == sample.monotonicUs)) {
      timeline.duplicates++;
      return false;
    }

    // Already released past this point — cannot un-integrate, so drop it.
    final released = _lastReleasedUs;
    if (released != null && sample.monotonicUs < released) {
      timeline.outOfOrder++;
      return false;
    }

    final interval = timeline.note(sample.monotonicUs);
    final prepared = sample.copyWith(
      sequence: timeline.nextSequence(),
      intervalUs: interval,
    );

    // Insert in timestamp order; within the window this is a short walk.
    if (buffer.isEmpty || buffer.last.monotonicUs <= prepared.monotonicUs) {
      buffer.addLast(prepared);
    } else {
      timeline.outOfOrder++;
      final ordered = [...buffer, prepared]
        ..sort((a, b) => a.monotonicUs.compareTo(b.monotonicUs));
      buffer
        ..clear()
        ..addAll(ordered);
    }

    while (buffer.length > _config.queueLimit) {
      buffer.removeFirst();
      _bufferOverflows++;
      timeline.dropped++;
    }
    return true;
  }

  /// Emits every sample that is now safe to process, oldest first.
  ///
  /// [nowUs] is the current monotonic time; it lets a stream that has fallen
  /// silent stop blocking the others once the reorder window has passed.
  List<SensorSample> drain(int nowUs) {
    final out = <SensorSample>[];
    final windowUs = _config.reorderWindow.inMicroseconds;

    while (true) {
      SensorType? bestType;
      int bestUs = 0;
      for (final entry in _buffers.entries) {
        if (entry.value.isEmpty) continue;
        final us = entry.value.first.monotonicUs;
        if (bestType == null || us < bestUs) {
          bestType = entry.key;
          bestUs = us;
        }
      }
      if (bestType == null) break;

      // Safe to release only if no still-active stream could still deliver
      // something older.
      var blocked = false;
      for (final entry in _buffers.entries) {
        if (entry.key == bestType) continue;
        final timeline = _timelines[entry.key];
        if (timeline == null || timeline.received == 0) continue;
        if (entry.value.isNotEmpty) continue; // it has newer data, fine
        final last = timeline.lastUs;
        if (last == null) continue;
        // The stream is quiet; give it the reorder window before assuming it
        // has nothing older to contribute.
        if (last < bestUs && nowUs - last < windowUs) {
          blocked = true;
          break;
        }
      }
      if (blocked && nowUs - bestUs < windowUs) break;

      out.add(_buffers[bestType]!.removeFirst());
      _lastReleasedUs = bestUs;
    }
    return out;
  }

  /// Releases everything still buffered, in order. Used when a session pauses
  /// so nothing is silently lost.
  List<SensorSample> flush() {
    final all = <SensorSample>[];
    for (final buffer in _buffers.values) {
      all.addAll(buffer);
      buffer.clear();
    }
    all.sort((a, b) => a.monotonicUs.compareTo(b.monotonicUs));
    if (all.isNotEmpty) _lastReleasedUs = all.last.monotonicUs;
    return all;
  }

  void reset() {
    _timelines.clear();
    _buffers.clear();
    _bufferOverflows = 0;
    _startUs = null;
    _lastReleasedUs = null;
  }
}
