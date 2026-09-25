import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/model/outage_log.dart';
import 'package:gatisaarth/core/nav/model/outage_recovery.dart';

OutageRecovery _r(int endedS, double errorM, {double distanceM = 500}) =>
    OutageRecovery(
      durationS: 30,
      distanceM: distanceM,
      errorM: errorM,
      fixAccuracyM: 5,
      endedAtUs: endedS * 1000000,
      coreLed: true,
    );

void main() {
  test('logs each outage once, however often the snapshot repeats it', () {
    final log = OutageLog();
    expect(log.add(_r(10, 20)), isTrue);
    expect(log.add(_r(10, 20)), isFalse);
    expect(log.add(_r(90, 80)), isTrue);
    expect(log.length, 2);
  });

  test('summarises against the target', () {
    final log = OutageLog()
      ..add(_r(10, 20)) // 4 %
      ..add(_r(20, 30)) // 6 %
      ..add(_r(30, 75)); // 15 %
    expect(log.metTarget(10), 2);
    expect(log.medianDriftPct, closeTo(6, 1e-9));
    expect(log.worstDriftPct, closeTo(15, 1e-9));
  });

  test('exports one CSV row per outage', () {
    final log = OutageLog()
      ..add(_r(10, 20))
      ..add(_r(30, 75));
    final lines = log.toCsv(10).trim().split('\n');
    expect(lines.first, startsWith('outage,duration_s'));
    expect(lines.first, contains('along_track_m,cross_track_m,'
        'peak_sigma_m,recovery_jump_m,simulated'));
    expect(lines, hasLength(3));
    expect(lines[1], '1,30.0,500.0,20.0,4.00,5.0,true,true,,,,,false');
    expect(lines[2], endsWith(',false,,,,,false'));
  });

  test('keeps only the newest entries past its capacity', () {
    final log = OutageLog(capacity: 2)
      ..add(_r(1, 1))
      ..add(_r(2, 1))
      ..add(_r(3, 1));
    expect(log.entries.first.endedAtUs, 2000000);
  });
}
