import 'package:flutter/foundation.dart';

/// Physical sources the navigation core knows about (§3).
///
/// Nothing may assume a given type exists — [SensorAvailability] records what
/// this particular phone actually produced.
enum SensorType {
  accelerometer,
  gyroscope,
  magnetometer,
  gravity,
  linearAcceleration,
  rotationVector,
  gnss,
  barometer,
  temperature,
}

extension SensorTypeLabel on SensorType {
  String get label {
    switch (this) {
      case SensorType.accelerometer:
        return 'Accelerometer';
      case SensorType.gyroscope:
        return 'Gyroscope';
      case SensorType.magnetometer:
        return 'Magnetometer';
      case SensorType.gravity:
        return 'Gravity';
      case SensorType.linearAcceleration:
        return 'Linear acceleration';
      case SensorType.rotationVector:
        return 'Rotation vector';
      case SensorType.gnss:
        return 'GNSS';
      case SensorType.barometer:
        return 'Barometer';
      case SensorType.temperature:
        return 'Temperature';
    }
  }
}

/// How trustworthy a stream's *timing* is (§4). This is about delivery, not
/// about whether the values are physically sensible.
enum SampleQuality { excellent, good, degraded, invalid }

/// Provenance of a displayed value (§65). Every number the diagnostics UI
/// shows carries one of these, so "demo" can never silently read as "live".
enum DataSource {
  /// Measured by real hardware on this device.
  real,

  /// Produced by the scenario simulator or demo mode. Must be visibly labelled.
  simulated,

  /// Derived by the filter rather than measured (e.g. a dead-reckoned position).
  estimated,

  /// This device or build cannot produce it. Shows as `--`, never as zero.
  unavailable,
}

/// One timestamped observation from one sensor (§3).
@immutable
class SensorSample {
  const SensorSample({
    required this.type,
    required this.monotonicUs,
    required this.values,
    this.wallClockUs,
    this.accuracy = -1,
    this.sequence = 0,
    this.intervalUs,
    this.valid = true,
    this.source = DataSource.real,
  });

  final SensorType type;

  /// Device event time in microseconds, from a monotonic clock. This is the
  /// only time base the filter integrates against — wall clock can step.
  final int monotonicUs;

  /// Wall-clock microseconds when known, for correlating with GNSS and logs.
  final int? wallClockUs;

  final List<double> values;

  /// Platform-reported accuracy/status, or -1 when the platform does not
  /// expose one. Never invent a value here.
  final int accuracy;

  /// Monotonic counter per sensor type; a jump means samples were dropped.
  final int sequence;

  /// Estimated interval to the previous sample (µs), null for the first.
  final double? intervalUs;

  /// False when the producer knows the payload is bad (NaN, out of range).
  final bool valid;

  final DataSource source;

  double get x => values.isNotEmpty ? values[0] : double.nan;
  double get y => values.length > 1 ? values[1] : double.nan;
  double get z => values.length > 2 ? values[2] : double.nan;

  double get monotonicSeconds => monotonicUs / 1e6;

  SensorSample copyWith({
    int? sequence,
    double? intervalUs,
    bool? valid,
    DataSource? source,
  }) =>
      SensorSample(
        type: type,
        monotonicUs: monotonicUs,
        values: values,
        wallClockUs: wallClockUs,
        accuracy: accuracy,
        sequence: sequence ?? this.sequence,
        intervalUs: intervalUs ?? this.intervalUs,
        valid: valid ?? this.valid,
        source: source ?? this.source,
      );

  @override
  String toString() =>
      '${type.name}#$sequence @${monotonicUs}us $values${valid ? '' : ' INVALID'}';
}

/// Live timing statistics for one sensor stream (§4, §64).
@immutable
class SensorStreamStats {
  const SensorStreamStats({
    required this.type,
    required this.quality,
    required this.received,
    required this.dropped,
    required this.duplicates,
    required this.outOfOrder,
    required this.effectiveHz,
    required this.jitterRatio,
    required this.lastSampleUs,
    required this.available,
  });

  const SensorStreamStats.unavailable(this.type)
      : quality = SampleQuality.invalid,
        received = 0,
        dropped = 0,
        duplicates = 0,
        outOfOrder = 0,
        effectiveHz = null,
        jitterRatio = null,
        lastSampleUs = null,
        available = false;

  final SensorType type;
  final SampleQuality quality;
  final int received;

  /// Samples the platform produced but we never saw, inferred from gaps
  /// larger than the expected interval.
  final int dropped;
  final int duplicates;
  final int outOfOrder;

  /// Measured delivery rate, null until there is enough history. Never a
  /// nominal "50 Hz" — this is what the phone actually did (§83).
  final double? effectiveHz;

  /// Interval standard deviation over its mean; null until measurable.
  final double? jitterRatio;

  final int? lastSampleUs;

  /// False when this device never produced a sample of this type.
  final bool available;

  double get dropRate => received + dropped == 0
      ? 0
      : dropped / (received + dropped);

  DataSource get source =>
      available ? DataSource.real : DataSource.unavailable;
}

/// Which sensors this device actually produced (§3 capability detection).
@immutable
class SensorAvailability {
  const SensorAvailability(this.present);

  const SensorAvailability.none() : present = const {};

  final Set<SensorType> present;

  bool has(SensorType t) => present.contains(t);

  /// The floor the navigation core must keep working on: accelerometer plus
  /// gyroscope. Everything else degrades a feature, not the position.
  bool get hasMinimumViableSet =>
      has(SensorType.accelerometer) && has(SensorType.gyroscope);

  SensorAvailability withPresent(SensorType t) =>
      SensorAvailability({...present, t});
}
