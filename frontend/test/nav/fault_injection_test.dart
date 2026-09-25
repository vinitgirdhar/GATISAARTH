import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/fault_injection.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_quality.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

List<DriveRecord> _imuGnssLog({int seconds = 10}) {
  final records = <DriveRecord>[
    const DriveRecord(type: DriveRecordType.meta, monotonicUs: 0),
  ];
  for (var s = 0; s < seconds; s++) {
    for (var i = 0; i < 50; i++) {
      final us = s * 1000000 + (i * 20000);
      records.add(DriveRecord.imu(
        monotonicUs: us,
        accel: Vector3(0, 0, -9.81),
        gyro: Vector3(0, 0, 0),
        mag: Vector3(20, 0, 40),
      ));
    }
    records.add(DriveRecord.gnss(GnssObservation(
      latitudeDeg: 28.6139 + s * 0.0001,
      longitudeDeg: 77.2090,
      accuracyM: 5,
      monotonicUs: s * 1000000,
      speedMps: 10,
      bearingDeg: 0,
    )));
  }
  return records;
}

void main() {
  group('FaultInjector', () {
    test('gnssOutage removes fixes in the window and marks it lost', () {
      final log = _imuGnssLog();
      final spec = FaultSpec(
          kind: FaultKind.gnssOutage, startS: 3, durationS: 3);
      final out = FaultInjector.apply(log, spec);

      final gnssInWindow = out.where((r) =>
          r.type == DriveRecordType.gnss &&
          r.monotonicUs >= 3000000 &&
          r.monotonicUs < 6000000);
      expect(gnssInWindow, isEmpty);
      expect(
          out.any((r) =>
              r.type == DriveRecordType.gnssLost && r.monotonicUs == 3000000),
          isTrue);
      // Fixes outside the window are untouched.
      expect(
          out.where((r) => r.type == DriveRecordType.gnss).length,
          _imuGnssLog().where((r) => r.type == DriveRecordType.gnss).length -
              3);
    });

    test('gnssPositionJump holds a constant offset for the window', () {
      final log = _imuGnssLog();
      final spec = FaultSpec(
          kind: FaultKind.gnssPositionJump,
          startS: 3,
          durationS: 2,
          magnitude: 120);
      final out = FaultInjector.apply(log, spec);

      final original =
          log.firstWhere((r) => r.type == DriveRecordType.gnss && r.monotonicUs == 3000000);
      final faulted = out
          .firstWhere((r) => r.type == DriveRecordType.gnss && r.monotonicUs == 3000000);
      final movedM = NavMath.horizontalDistance(
        lat0: original.fix!.latitudeDeg,
        lon0: original.fix!.longitudeDeg,
        lat1: faulted.fix!.latitudeDeg,
        lon1: faulted.fix!.longitudeDeg,
      );
      expect(movedM, closeTo(120, 1));

      // Outside the window, unchanged.
      final untouched = out
          .firstWhere((r) => r.type == DriveRecordType.gnss && r.monotonicUs == 0);
      expect(untouched.fix!.latitudeDeg, 28.6139);
    });

    test('gnssIntegrityAnomaly ramps from 0 to the target offset', () {
      final log = _imuGnssLog();
      final spec = FaultSpec(
          kind: FaultKind.gnssIntegrityAnomaly,
          startS: 0,
          durationS: 4,
          magnitude: 40);
      final out = FaultInjector.apply(log, spec);

      double offsetAt(int us) {
        final original =
            log.firstWhere((r) => r.type == DriveRecordType.gnss && r.monotonicUs == us);
        final faulted =
            out.firstWhere((r) => r.type == DriveRecordType.gnss && r.monotonicUs == us);
        return NavMath.horizontalDistance(
          lat0: original.fix!.latitudeDeg,
          lon0: original.fix!.longitudeDeg,
          lat1: faulted.fix!.latitudeDeg,
          lon1: faulted.fix!.longitudeDeg,
        );
      }

      expect(offsetAt(0), closeTo(0, 0.5));
      expect(offsetAt(2000000), closeTo(20, 2));
      expect(offsetAt(3000000), greaterThan(offsetAt(2000000)));
    });

    test('gyroBias adds a constant yaw-rate bias within the window only', () {
      final log = _imuGnssLog();
      final spec = FaultSpec(
          kind: FaultKind.gyroBias, startS: 2, durationS: 1, magnitude: 0.5);
      final out = FaultInjector.apply(log, spec);

      final inWindow =
          out.firstWhere((r) => r.type == DriveRecordType.imu && r.monotonicUs == 2000000);
      expect(inWindow.gyro!.z, closeTo(0.5 * NavMath.degToRad, 1e-9));

      final outside =
          out.firstWhere((r) => r.type == DriveRecordType.imu && r.monotonicUs == 0);
      expect(outside.gyro!.z, 0);
    });

    test('accelBias adds a constant forward bias within the window only', () {
      final log = _imuGnssLog();
      final spec = FaultSpec(
          kind: FaultKind.accelBias, startS: 2, durationS: 1, magnitude: 0.3);
      final out = FaultInjector.apply(log, spec);

      final inWindow =
          out.firstWhere((r) => r.type == DriveRecordType.imu && r.monotonicUs == 2000000);
      expect(inWindow.accel!.x, closeTo(0.3, 1e-9));
      expect(inWindow.accel!.z, closeTo(-9.81, 1e-9));
    });

    test('magDisturbance scales the field magnitude', () {
      final log = _imuGnssLog();
      final spec = FaultSpec(
          kind: FaultKind.magDisturbance,
          startS: 2,
          durationS: 1,
          magnitude: 2.0,
          magMode: MagDisturbanceMode.scale);
      final out = FaultInjector.apply(log, spec);
      final inWindow =
          out.firstWhere((r) => r.type == DriveRecordType.imu && r.monotonicUs == 2000000);
      expect(inWindow.mag!.x, closeTo(40, 1e-9));
      expect(inWindow.mag!.z, closeTo(80, 1e-9));
    });

    test('magDisturbance offsets the field', () {
      final log = _imuGnssLog();
      final spec = FaultSpec(
          kind: FaultKind.magDisturbance,
          startS: 2,
          durationS: 1,
          magnitude: 60,
          magMode: MagDisturbanceMode.offset);
      final out = FaultInjector.apply(log, spec);
      final inWindow =
          out.firstWhere((r) => r.type == DriveRecordType.imu && r.monotonicUs == 2000000);
      expect(inWindow.mag!.x, closeTo(20 + 60, 1e-9));
    });

    test('sensorDropout freezes gyro while accel keeps changing', () {
      final log = <DriveRecord>[
        const DriveRecord(type: DriveRecordType.meta, monotonicUs: 0),
        DriveRecord.imu(
            monotonicUs: 0, accel: Vector3(0, 0, -9.81), gyro: Vector3(0, 0, 0.1)),
        DriveRecord.imu(
            monotonicUs: 20000, accel: Vector3(1, 0, -9.81), gyro: Vector3(0, 0, 0.2)),
        DriveRecord.imu(
            monotonicUs: 40000, accel: Vector3(2, 0, -9.81), gyro: Vector3(0, 0, 0.3)),
      ];
      final spec = FaultSpec(
          kind: FaultKind.sensorDropout,
          startS: 0,
          durationS: 1,
          dropoutSensor: DropoutSensor.gyro);
      final out = FaultInjector.apply(log, spec)
          .where((r) => r.type == DriveRecordType.imu)
          .toList();
      // Gyro frozen at the value it had when the window opened.
      expect(out[0].gyro!.z, 0.1);
      expect(out[1].gyro!.z, 0.1);
      expect(out[2].gyro!.z, 0.1);
      // Accel keeps changing normally.
      expect(out[0].accel!.x, 0);
      expect(out[1].accel!.x, 1);
      expect(out[2].accel!.x, 2);
    });

    test('timestampDelay shifts GNSS fixes later and keeps the stream sorted',
        () {
      final log = _imuGnssLog();
      final spec = FaultSpec(
          kind: FaultKind.timestampDelay,
          startS: 3,
          durationS: 1,
          magnitude: 500); // ms
      final out = FaultInjector.apply(log, spec);

      final delayed = out.firstWhere((r) =>
          r.type == DriveRecordType.gnss && r.fix!.monotonicUs == 3500000);
      expect(delayed.monotonicUs, 3500000);
      // The stream stays sorted by time.
      for (var i = 1; i < out.length; i++) {
        expect(out[i].monotonicUs, greaterThanOrEqualTo(out[i - 1].monotonicUs));
      }
    });
  });
}
