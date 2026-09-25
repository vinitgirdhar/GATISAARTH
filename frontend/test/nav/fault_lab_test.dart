import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/fault_injection.dart';
import 'package:gatisaarth/core/nav/benchmark/fault_lab.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

import 'support/drive_simulator.dart';
import 'support/reference_drive.dart';

void main() {
  late List<DriveRecord> drive;

  setUpAll(() {
    drive = simulateDriveLog(
      setup: referenceSetupDrive(),
      segments: const [
        DriveSegment(seconds: 8, longitudinalAccel: 1.6),
        DriveSegment(seconds: 200),
      ],
    );
  });

  group('FaultLab', () {
    test('a GNSS position jump is rejected by the quality gate', () {
      final result = FaultLab.run(
        drive,
        const FaultSpec(
          kind: FaultKind.gnssPositionJump,
          startS: 60,
          durationS: 20,
          magnitude: 120,
        ),
      );

      expect(result.detected, isTrue);
      expect(result.mechanism, contains('rejected'));
      expect(result.action, contains('dead reckoning maintained'));
      expect(result.detectionLatencyS, isNotNull);
      expect(result.detectionLatencyS!, lessThan(2));
    });

    test('a GNSS outage is not flagged as an anomaly; DR keeps leading', () {
      final result = FaultLab.run(
        drive,
        const FaultSpec(
          kind: FaultKind.gnssOutage,
          startS: 60,
          durationS: 10,
        ),
      );

      // Withholding fixes is normal operation, not a fault the integrity
      // monitor "catches" - the honest report is that DR carried on.
      expect(result.keptLeading, isTrue);
    });

    test('a small gyro bias: report what the engine actually does', () {
      final result = FaultLab.run(
        drive,
        const FaultSpec(
          kind: FaultKind.gyroBias,
          startS: 60,
          durationS: 20,
          magnitude: 0.5,
        ),
      );

      // A 0.5 deg/s systematic bias is far below `SensorFaultDetector`'s
      // noise/range thresholds, so it is still not caught there - but
      // `FaultMonitor` (§ Fault Injection Lab) now runs two read-only
      // detectors that both notice a bias this size: comparing integrated
      // gyro yaw against the GNSS course rate, and an innovation CUSUM on
      // the position drift it causes. Either can fire first depending on the
      // drive; both are read-only, so DR keeps leading either way.
      expect(result.detected, isTrue);
      expect(
        result.mechanism,
        anyOf('Gyro bias suspected', 'GNSS integrity anomaly detected'),
      );
      expect(result.action, contains('no correction applied'));
      expect(result.maxErrorM, greaterThanOrEqualTo(0));
    });
  });
}
