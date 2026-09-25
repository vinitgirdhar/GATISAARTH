import '../gnss/gnss_quality.dart';
import '../math/nav_math.dart';
import '../replay/drive_log.dart';

/// A fault the Fault Injection Lab can inject into a replayed drive.
///
/// Every fault the developer picks in the lab screen (§ Fault Injection Lab)
/// is one of these. `magnitude`'s unit depends on [kind] - see [describe].
enum FaultKind {
  /// GNSS fixes stop arriving entirely for the window.
  gnssOutage,

  /// Every fix in the window is offset by a fixed distance, held steady - a
  /// step, not a drift. `magnitude` is metres.
  gnssPositionJump,

  /// The offset ramps smoothly from 0 to `magnitude` metres across the
  /// window, the way a spoofer would try to stay under the jump gate. The UI
  /// must call this "GNSS integrity anomaly", never "spoofing".
  gnssIntegrityAnomaly,

  /// A constant yaw-rate bias added to every gyroscope sample in the window.
  /// `magnitude` is degrees/second.
  gyroBias,

  /// A constant forward-axis bias added to every accelerometer sample in the
  /// window. `magnitude` is m/s².
  accelBias,

  /// The magnetometer reading is disturbed - scaled or offset, see
  /// [magMode]. `magnitude` is the scale factor or the offset in µT.
  magDisturbance,

  /// One IMU channel (gyro or accel, see [dropoutSensor]) freezes at its last
  /// reading for the window while the other keeps moving - what
  /// `SensorFaultDetector` calls "frozen".
  sensorDropout,

  /// Every GNSS fix in the window is timestamped `magnitude` milliseconds
  /// later than it actually arrived.
  timestampDelay,
}

/// Which IMU channel [FaultKind.sensorDropout] freezes.
enum DropoutSensor { gyro, accel }

/// How [FaultKind.magDisturbance] disturbs the field.
enum MagDisturbanceMode { scale, offset }

/// One fault to inject: what, when, how long, how strong.
class FaultSpec {
  const FaultSpec({
    required this.kind,
    required this.startS,
    required this.durationS,
    this.magnitude = 0,
    this.dropoutSensor = DropoutSensor.gyro,
    this.magMode = MagDisturbanceMode.scale,
  });

  final FaultKind kind;

  /// Seconds after the drive's first sensor record.
  final double startS;
  final double durationS;
  final double magnitude;
  final DropoutSensor dropoutSensor;
  final MagDisturbanceMode magMode;

  /// Human text for the lab's "Injected" block.
  String describe() {
    final at = 'at t=${startS.toStringAsFixed(0)}s';
    switch (kind) {
      case FaultKind.gnssOutage:
        return 'GNSS outage for ${durationS.toStringAsFixed(0)}s $at';
      case FaultKind.gnssPositionJump:
        return 'GNSS position offset +${magnitude.toStringAsFixed(0)} m for '
            '${durationS.toStringAsFixed(0)}s $at';
      case FaultKind.gnssIntegrityAnomaly:
        return 'GNSS integrity anomaly (drift ramping to '
            '${magnitude.toStringAsFixed(0)} m) over '
            '${durationS.toStringAsFixed(0)}s $at';
      case FaultKind.gyroBias:
        return 'Gyro bias +${magnitude.toStringAsFixed(2)} deg/s for '
            '${durationS.toStringAsFixed(0)}s $at';
      case FaultKind.accelBias:
        return 'Accelerometer bias +${magnitude.toStringAsFixed(2)} m/s² '
            'for ${durationS.toStringAsFixed(0)}s $at';
      case FaultKind.magDisturbance:
        return magMode == MagDisturbanceMode.scale
            ? 'Magnetometer field ×${magnitude.toStringAsFixed(1)} for '
                '${durationS.toStringAsFixed(0)}s $at'
            : 'Magnetometer offset +${magnitude.toStringAsFixed(0)} µT '
                'for ${durationS.toStringAsFixed(0)}s $at';
      case FaultKind.sensorDropout:
        final sensor = dropoutSensor == DropoutSensor.gyro ? 'Gyro' : 'Accel';
        return '$sensor dropout for ${durationS.toStringAsFixed(0)}s $at';
      case FaultKind.timestampDelay:
        return 'GNSS fixes delayed by ${magnitude.toStringAsFixed(0)} ms for '
            '${durationS.toStringAsFixed(0)}s $at';
    }
  }
}

/// Transforms a drive log to inject one [FaultSpec]. Pure and deterministic:
/// same records and spec always produce the same output, no clock, no
/// randomness - so a run is exactly reproducible (§ replay is bit-exact).
class FaultInjector {
  const FaultInjector._();

  static List<DriveRecord> apply(List<DriveRecord> records, FaultSpec spec) {
    if (records.isEmpty) return records;
    final startUs = _firstSensorUs(records) + (spec.startS * 1e6).round();
    final endUs = startUs + (spec.durationS * 1e6).round();
    bool inWindow(int us) => us >= startUs && us < endUs;

    switch (spec.kind) {
      case FaultKind.gnssOutage:
        return _outage(records, startUs, endUs);
      case FaultKind.gnssPositionJump:
        return _offsetGnss(records, inWindow, (fix, t) => spec.magnitude);
      case FaultKind.gnssIntegrityAnomaly:
        return _offsetGnss(records, inWindow, (fix, t) {
          final frac = ((fix.monotonicUs - startUs) / (endUs - startUs))
              .clamp(0.0, 1.0);
          return spec.magnitude * frac;
        });
      case FaultKind.gyroBias:
        return _mapImu(records, inWindow, (r) {
          final biasRad = spec.magnitude * NavMath.degToRad;
          return r.gyro! + Vector3(0, 0, biasRad);
        }, gyro: true);
      case FaultKind.accelBias:
        return _mapImu(records, inWindow, (r) {
          return r.accel! + Vector3(spec.magnitude, 0, 0);
        }, gyro: false);
      case FaultKind.magDisturbance:
        return _mapMag(records, inWindow, (mag) {
          if (spec.magMode == MagDisturbanceMode.scale) {
            return mag * spec.magnitude;
          }
          return mag + Vector3(spec.magnitude, 0, 0);
        });
      case FaultKind.sensorDropout:
        return _freezeSensor(records, inWindow, spec.dropoutSensor);
      case FaultKind.timestampDelay:
        return _delayGnss(records, inWindow, (spec.magnitude * 1000).round());
    }
  }

  static int _firstSensorUs(List<DriveRecord> records) {
    for (final r in records) {
      if (r.type != DriveRecordType.meta) return r.monotonicUs;
    }
    return 0;
  }

  /// Removes every `gnss` record in the window and marks the start of it as
  /// lost, mirroring how a real receiver-lost stream is recorded.
  static List<DriveRecord> _outage(
      List<DriveRecord> records, int startUs, int endUs) {
    final out = <DriveRecord>[];
    var markedLost = false;
    for (final r in records) {
      final inWindow = r.monotonicUs >= startUs && r.monotonicUs < endUs;
      if (r.type == DriveRecordType.gnss && inWindow) {
        if (!markedLost) {
          out.add(DriveRecord.gnssLost(startUs));
          markedLost = true;
        }
        continue;
      }
      out.add(r);
    }
    return out;
  }

  static List<DriveRecord> _offsetGnss(
    List<DriveRecord> records,
    bool Function(int us) inWindow,
    double Function(GnssObservation fix, int us) northMetres,
  ) {
    return [
      for (final r in records)
        if (r.type == DriveRecordType.gnss && inWindow(r.monotonicUs))
          DriveRecord.gnss(
              _offsetFix(r.fix!, northMetres(r.fix!, r.monotonicUs)))
        else
          r,
    ];
  }

  static GnssObservation _offsetFix(GnssObservation fix, double northM) {
    final moved = NavMath.addNed(
      latDeg: fix.latitudeDeg,
      lonDeg: fix.longitudeDeg,
      altM: fix.altitudeM ?? 0,
      north: northM,
      east: 0,
      down: 0,
    );
    return GnssObservation(
      latitudeDeg: moved[0],
      longitudeDeg: moved[1],
      accuracyM: fix.accuracyM,
      monotonicUs: fix.monotonicUs,
      altitudeM: fix.altitudeM,
      speedMps: fix.speedMps,
      speedAccuracyMps: fix.speedAccuracyMps,
      bearingDeg: fix.bearingDeg,
      bearingAccuracyDeg: fix.bearingAccuracyDeg,
      verticalAccuracyM: fix.verticalAccuracyM,
      satellitesUsed: fix.satellitesUsed,
      isMocked: fix.isMocked,
    );
  }

  static List<DriveRecord> _mapImu(
    List<DriveRecord> records,
    bool Function(int us) inWindow,
    Vector3 Function(DriveRecord r) transform, {
    required bool gyro,
  }) {
    return [
      for (final r in records)
        if (r.type == DriveRecordType.imu && inWindow(r.monotonicUs))
          DriveRecord.imu(
            monotonicUs: r.monotonicUs,
            accel: gyro ? r.accel! : transform(r),
            gyro: gyro ? transform(r) : r.gyro!,
            mag: r.mag,
            pressureHpa: r.pressureHpa,
            temperatureC: r.temperatureC,
          )
        else
          r,
    ];
  }

  static List<DriveRecord> _mapMag(
    List<DriveRecord> records,
    bool Function(int us) inWindow,
    Vector3 Function(Vector3 mag) transform,
  ) {
    return [
      for (final r in records)
        if (r.type == DriveRecordType.imu &&
            r.mag != null &&
            inWindow(r.monotonicUs))
          DriveRecord.imu(
            monotonicUs: r.monotonicUs,
            accel: r.accel!,
            gyro: r.gyro!,
            mag: transform(r.mag!),
            pressureHpa: r.pressureHpa,
            temperatureC: r.temperatureC,
          )
        else
          r,
    ];
  }

  /// Freezes one IMU channel at the value it held when the window opened -
  /// what `SensorFaultDetector` reports as [SensorFault.frozen] - while the
  /// other channel keeps reporting normally.
  static List<DriveRecord> _freezeSensor(
    List<DriveRecord> records,
    bool Function(int us) inWindow,
    DropoutSensor sensor,
  ) {
    Vector3? frozenAccel;
    Vector3? frozenGyro;
    final out = <DriveRecord>[];
    for (final r in records) {
      if (r.type != DriveRecordType.imu) {
        out.add(r);
        continue;
      }
      if (!inWindow(r.monotonicUs)) {
        frozenAccel = null;
        frozenGyro = null;
        out.add(r);
        continue;
      }
      if (sensor == DropoutSensor.accel) {
        frozenAccel ??= r.accel;
        out.add(DriveRecord.imu(
          monotonicUs: r.monotonicUs,
          accel: frozenAccel!,
          gyro: r.gyro!,
          mag: r.mag,
          pressureHpa: r.pressureHpa,
          temperatureC: r.temperatureC,
        ));
      } else {
        frozenGyro ??= r.gyro;
        out.add(DriveRecord.imu(
          monotonicUs: r.monotonicUs,
          accel: r.accel!,
          gyro: frozenGyro!,
          mag: r.mag,
          pressureHpa: r.pressureHpa,
          temperatureC: r.temperatureC,
        ));
      }
    }
    return out;
  }

  /// Shifts every `gnss` record's timestamp `delayUs` later, then re-sorts so
  /// the stream stays causally ordered - the same shape a truly late-arriving
  /// fix would have.
  static List<DriveRecord> _delayGnss(
    List<DriveRecord> records,
    bool Function(int us) inWindow,
    int delayUs,
  ) {
    final shifted = [
      for (final r in records)
        if (r.type == DriveRecordType.gnss && inWindow(r.monotonicUs))
          DriveRecord.gnss(GnssObservation(
            latitudeDeg: r.fix!.latitudeDeg,
            longitudeDeg: r.fix!.longitudeDeg,
            accuracyM: r.fix!.accuracyM,
            monotonicUs: r.fix!.monotonicUs + delayUs,
            altitudeM: r.fix!.altitudeM,
            speedMps: r.fix!.speedMps,
            speedAccuracyMps: r.fix!.speedAccuracyMps,
            bearingDeg: r.fix!.bearingDeg,
            bearingAccuracyDeg: r.fix!.bearingAccuracyDeg,
            verticalAccuracyM: r.fix!.verticalAccuracyM,
            satellitesUsed: r.fix!.satellitesUsed,
            isMocked: r.fix!.isMocked,
          ))
        else
          r,
    ];
    // Stable sort keeps same-timestamp records (notably the meta header) in
    // their original relative order.
    shifted.sort((a, b) => a.monotonicUs.compareTo(b.monotonicUs));
    return shifted;
  }
}

/// One built-in fault the lab screen offers as a tappable chip, with sensible
/// magnitude/duration defaults so a developer does not have to guess units.
class FaultPreset {
  const FaultPreset({required this.label, required this.spec});

  final String label;
  final FaultSpec spec;
}

/// `startS` is fixed at 90 s in for every preset: the bundled reference
/// drive's mount converges at ~77 s, and a fault injected before the core
/// leads measures nothing. Needs a recording of about two minutes or more.
const List<FaultPreset> kFaultPresets = [
  FaultPreset(
    label: 'GNSS outage',
    spec: FaultSpec(kind: FaultKind.gnssOutage, startS: 90, durationS: 20),
  ),
  FaultPreset(
    label: 'GNSS position jump (+120 m)',
    spec: FaultSpec(
      kind: FaultKind.gnssPositionJump,
      startS: 90,
      durationS: 20,
      magnitude: 120,
    ),
  ),
  FaultPreset(
    label: 'GNSS integrity anomaly',
    spec: FaultSpec(
      kind: FaultKind.gnssIntegrityAnomaly,
      startS: 90,
      durationS: 30,
      magnitude: 40,
    ),
  ),
  FaultPreset(
    label: 'Gyro bias (+0.5 deg/s)',
    spec: FaultSpec(
      kind: FaultKind.gyroBias,
      startS: 90,
      durationS: 20,
      magnitude: 0.5,
    ),
  ),
  FaultPreset(
    label: 'Accelerometer bias (+0.3 m/s²)',
    spec: FaultSpec(
      kind: FaultKind.accelBias,
      startS: 90,
      durationS: 20,
      magnitude: 0.3,
    ),
  ),
  FaultPreset(
    label: 'Magnetometer disturbance (×2)',
    spec: FaultSpec(
      kind: FaultKind.magDisturbance,
      startS: 90,
      durationS: 20,
      magnitude: 2.0,
      magMode: MagDisturbanceMode.scale,
    ),
  ),
  FaultPreset(
    label: 'Gyro dropout',
    spec: FaultSpec(
      kind: FaultKind.sensorDropout,
      startS: 90,
      durationS: 10,
      dropoutSensor: DropoutSensor.gyro,
    ),
  ),
  FaultPreset(
    label: 'Accelerometer dropout',
    spec: FaultSpec(
      kind: FaultKind.sensorDropout,
      startS: 90,
      durationS: 10,
      dropoutSensor: DropoutSensor.accel,
    ),
  ),
  FaultPreset(
    label: 'GNSS fixes delayed (+800 ms)',
    spec: FaultSpec(
      kind: FaultKind.timestampDelay,
      startS: 90,
      durationS: 20,
      magnitude: 800,
    ),
  ),
];
