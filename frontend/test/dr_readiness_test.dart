import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_health.dart';
import 'package:gatisaarth/core/nav/model/nav_snapshot.dart';
import 'package:gatisaarth/core/nav/sensors/sensor_health.dart';
import 'package:gatisaarth/features/navigation_engine/domain/dr_readiness.dart';

const _passHardware = SensorHealthReport(overall: HealthVerdict.pass, checks: [
  HealthCheck(name: 'Sampling rate', verdict: HealthVerdict.pass, value: '50 Hz'),
  HealthCheck(name: 'Timestamp jitter', verdict: HealthVerdict.pass, value: '1%'),
  HealthCheck(name: 'Gyro bias stability', verdict: HealthVerdict.pass, value: '--'),
]);

const _normalGnss = GnssHealthAssessment(
  state: GnssHealthState.normal,
  reasons: [],
  metrics: GnssHealthMetrics(),
);

DrReadinessInput _input({
  bool alignmentConverged = true,
  bool recalibratingMount = false,
  SensorHealthReport hardwareCheck = _passHardware,
  bool roadAvailable = true,
  GnssHealthAssessment gnssHealth = _normalGnss,
  bool engineLeading = false,
  NavIntegrity integrity = NavIntegrity.high,
  double? gnssSpeedStdMps = 0.3,
  bool speedKnown = true,
  double? gnssAccuracyM = 6,
}) =>
    DrReadinessInput(
      alignmentConverged: alignmentConverged,
      recalibratingMount: recalibratingMount,
      hardwareCheck: hardwareCheck,
      roadAvailable: roadAvailable,
      gnssHealth: gnssHealth,
      engineLeading: engineLeading,
      integrity: integrity,
      gnssSpeedStdMps: gnssSpeedStdMps,
      speedKnown: speedKnown,
      gnssAccuracyM: gnssAccuracyM,
    );

void main() {
  group('evaluateDrReadiness (table-driven)', () {
    final cases = <String, (DrReadinessInput, DrReadinessLevel)>{
      'everything healthy -> ready': (_input(), DrReadinessLevel.ready),
      'mount recalibrating -> partially ready': (
        _input(alignmentConverged: false, recalibratingMount: true),
        DrReadinessLevel.partiallyReady,
      ),
      'alignment never converged -> not ready': (
        _input(alignmentConverged: false, recalibratingMount: false),
        DrReadinessLevel.notReady,
      ),
      'no road on the map -> not ready': (
        _input(roadAvailable: false),
        DrReadinessLevel.notReady,
      ),
      'sampling rate degraded -> partially ready': (
        _input(hardwareCheck: const SensorHealthReport(
          overall: HealthVerdict.degraded,
          checks: [
            HealthCheck(
                name: 'Sampling rate',
                verdict: HealthVerdict.degraded,
                value: '20 Hz',
                reason: 'Accel/gyro below 30 Hz'),
          ],
        )),
        DrReadinessLevel.partiallyReady,
      ),
      'sampling rate failing -> not ready': (
        _input(hardwareCheck: const SensorHealthReport(
          overall: HealthVerdict.fail,
          checks: [
            HealthCheck(
                name: 'Sampling rate',
                verdict: HealthVerdict.fail,
                value: '5 Hz',
                reason: 'Accel/gyro below 15 Hz'),
          ],
        )),
        DrReadinessLevel.notReady,
      ),
      'hardware check not measured yet -> not ready': (
        _input(hardwareCheck: SensorHealthReport.pending),
        DrReadinessLevel.notReady,
      ),
      'speed unknown -> not ready': (
        _input(speedKnown: false, gnssSpeedStdMps: null),
        DrReadinessLevel.notReady,
      ),
      'speed known but still settling -> partially ready': (
        _input(gnssSpeedStdMps: 1.8),
        DrReadinessLevel.partiallyReady,
      ),
      'speed swinging wildly -> not ready': (
        _input(gnssSpeedStdMps: 6.0),
        DrReadinessLevel.notReady,
      ),
      'gnss accuracy poor -> not ready': (
        _input(gnssAccuracyM: 80),
        DrReadinessLevel.notReady,
      ),
      'gnss accuracy moderate -> partially ready': (
        _input(gnssAccuracyM: 30),
        DrReadinessLevel.partiallyReady,
      ),
      'gnss multipath suspected -> not ready': (
        _input(gnssHealth: const GnssHealthAssessment(
          state: GnssHealthState.multipathSuspected,
          reasons: ['multipath'],
          metrics: GnssHealthMetrics(),
        )),
        DrReadinessLevel.notReady,
      ),
      'no gnss fix at all -> not ready': (
        _input(gnssHealth: const GnssHealthAssessment(
          state: GnssHealthState.waiting,
          reasons: [],
          metrics: GnssHealthMetrics(),
        ), gnssAccuracyM: null),
        DrReadinessLevel.notReady,
      ),
      'engine integrity invalid -> not ready regardless of the rest': (
        _input(integrity: NavIntegrity.invalid),
        DrReadinessLevel.notReady,
      ),
    };

    cases.forEach((name, spec) {
      final (input, expected) = spec;
      test(name, () {
        final report = evaluateDrReadiness(input);
        expect(report.overall, expected, reason: report.rows.map((r) =>
            '${r.label}: ${r.status} (${r.reason})').join('; '));
      });
    });

    test('every row carries a human reason', () {
      final report = evaluateDrReadiness(_input(alignmentConverged: false));
      for (final row in report.rows) {
        expect(row.reason, isNotEmpty);
      }
    });
  });
}
