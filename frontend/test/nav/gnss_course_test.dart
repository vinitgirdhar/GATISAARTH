import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_course.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_quality.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

import 'support/drive_simulator.dart';
import 'support/reference_drive.dart';

/// Feeds 1 Hz fixes moving at [speed] m/s on compass [courseDeg], turning at
/// [turnDegPerS]; returns the last course the tracker reported.
GnssCourse? _drive(GnssCourseTracker t,
    {required double courseDeg,
    double speed = 10,
    double turnDegPerS = 0,
    int seconds = 10}) {
  var lat = 19.1, lon = 72.85, c = courseDeg;
  GnssCourse? last;
  for (var i = 0; i < seconds; i++) {
    last = t.add(
      latitudeDeg: lat,
      longitudeDeg: lon,
      accuracyM: 8,
      monotonicUs: i * 1000000,
    );
    final rad = c * math.pi / 180;
    lat += speed * math.cos(rad) / 111320;
    lon += speed * math.sin(rad) / (111320 * math.cos(lat * math.pi / 180));
    c += turnDegPerS;
  }
  return last;
}

void main() {
  group('GnssCourseTracker', () {
    test('a straight run gives its course', () {
      final c = _drive(GnssCourseTracker(), courseDeg: 128)!;
      expect(courseDifferenceDeg(c.courseDeg, 128).abs(), lessThan(1));
      expect(c.sigmaDeg, lessThan(20));
    });

    test('too slow to trace a course gives none', () {
      expect(_drive(GnssCourseTracker(), courseDeg: 90, speed: 1), isNull);
    });

    test('a tight turn inside the baseline gives none', () {
      expect(
          _drive(GnssCourseTracker(), courseDeg: 0, turnDegPerS: 25), isNull);
    });

    test('course difference wraps across north', () {
      expect(courseDifferenceDeg(5, 355), closeTo(10, 1e-9));
      expect(courseDifferenceDeg(355, 5), closeTo(-10, 1e-9));
    });
  });

  test(
      'a receiver that never reports bearing still gets the right heading '
      '(2026-09-26 rickshaw drive: the core ran ~90 deg off for 10 min)', () {
    // Speed up, then turn ~90 degrees, so "north" is a wrong guess.
    final records = [
      for (final r in simulateDriveLog(
        setup: calibrationDrive(),
        segments: const [
          DriveSegment(seconds: 5, longitudinalAccel: 2),
          DriveSegment(seconds: 9, yawRate: 10 * math.pi / 180),
          DriveSegment(seconds: 60),
        ],
      ))
        if (r.type == DriveRecordType.gnss) _withoutBearing(r) else r,
    ];
    final engine = NavigationEngine();
    final fixes = <GnssObservation>[];
    for (final r in records) {
      switch (r.type) {
        case DriveRecordType.imu:
          engine.onImu(
            accelPhone: r.accel!,
            gyroPhone: r.gyro!,
            monotonicUs: r.monotonicUs,
            magPhone: r.mag,
          );
        case DriveRecordType.gnss:
          fixes.add(r.fix!);
          engine.onGnss(r.fix!);
        default:
          break;
      }
    }
    // Truth over a 10 s chord: two fixes 1 s apart carry the simulated noise.
    final last = fixes.last, prev = fixes[fixes.length - 11];
    final dn = last.latitudeDeg - prev.latitudeDeg;
    final de = (last.longitudeDeg - prev.longitudeDeg) *
        math.cos(last.latitudeDeg * math.pi / 180);
    final truth = (math.atan2(de, dn) * 180 / math.pi + 360) % 360;
    final heading = engine.snapshot!.headingDeg!;
    expect(
        engine.transitions.where((t) => t.reason.contains('re-seeded')), isEmpty,
        reason: 'a clean drive needs no re-seed');
    expect(courseDifferenceDeg(heading, truth).abs(), lessThan(15),
        reason: 'core $heading vs GNSS course $truth');
  });
}

DriveRecord _withoutBearing(DriveRecord r) {
  final f = r.fix!;
  return DriveRecord.gnss(GnssObservation(
    latitudeDeg: f.latitudeDeg,
    longitudeDeg: f.longitudeDeg,
    accuracyM: f.accuracyM,
    monotonicUs: f.monotonicUs,
    altitudeM: f.altitudeM,
    speedMps: f.speedMps,
    verticalAccuracyM: f.verticalAccuracyM,
  ));
}
