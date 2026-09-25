import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_benchmark.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_report.dart';
import 'package:gatisaarth/core/nav/motion/motion_classifier.dart' show VehicleClass;
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

import 'support/drive_simulator.dart';
import 'support/reference_drive.dart';

const _config = OutageBenchmarkConfig(durationsS: [10, 30, 60], strideS: 30);

OutageReport _run(List<DriveRecord> log, {String source = 'test'}) =>
    OutageBenchmark.run(log, config: _config, source: source);

void main() {
  late List<DriveRecord> city;
  late OutageReport cityReport;

  setUpAll(() {
    city = simulateDriveLog(
        setup: referenceSetupDrive(), segments: referenceCityDrive());
    cityReport = _run(city, source: 'reference city drive');
  });

  group('outage benchmark', () {
    test('scores the core against the fixes it was denied', () {
      final r = cityReport.forDuration(30);
      expect(r, isNotNull);
      expect(r!.n, greaterThanOrEqualTo(3));
      expect(r.hold.medianM, isNonNegative);
      expect(r.engine.medianM, isNonNegative);
      expect(r.engine.medianM, lessThan(100));
      expect(cityReport.coreLedFromS, isNotNull);
    });

    test('through bends and stops, the core beats holding the last velocity',
        () {
      final r = cityReport.forDuration(60)!;
      expect(r.engine.medianM, lessThan(r.hold.medianM));
      expect(r.engineWins, greaterThan(r.n / 2));
    });

    test('on a straight cruise the hold baseline is honest, not a strawman',
        () {
      final straight = simulateDriveLog(setup: calibrationDrive(), segments: const [
        DriveSegment(seconds: 8, longitudinalAccel: 2.0),
        DriveSegment(seconds: 200),
      ]);
      final r = _run(straight).forDuration(30)!;
      // Same speed, same heading, nothing to drift: extrapolating the last fix
      // is nearly exact, so a large error would mean the baseline is broken.
      expect(r.hold.medianM, lessThan(15));
    });

    test('a core that never got aligned is reported, not scored', () {
      final unaligned = simulateDriveLog(segments: const [
        DriveSegment(seconds: 8, longitudinalAccel: 2.0),
        DriveSegment(seconds: 120),
      ]);
      final report = _run(unaligned);
      expect(report.coreLedFromS, isNull);
      expect(report.durations, isEmpty);
    });

    test('poor-quality fixes are not trusted as truth', () {
      final report = _run(simulateDriveLog(
        setup: referenceSetupDrive(),
        segments: referenceCityDrive(),
        gnssAccuracy: 60,
      ));
      expect(report.profile.truthFixes, 0);
      expect(report.durations, isEmpty);
    });

    test('a parked vehicle says nothing about drift', () {
      final parked = simulateDriveLog(
        setup: calibrationDrive(),
        segments: const [DriveSegment(seconds: 200)],
      );
      final report = _run(parked);
      expect(report.durations, isEmpty);
      expect(report.skipped[SkipReason.tooLittleTravel], greaterThan(0));
    });

    test('a log recorded on a two-wheeler is replayed with two-wheeler settings',
        () {
      final bike = simulateDriveLog(
        setup: referenceSetupDrive(),
        segments: referenceCityDrive(),
        vehicle: 'twoWheeler',
      );
      final report = _run(bike);
      expect(report.vehicleClass, VehicleClass.twoWheeler);
      expect(report.profile.vehicle, 'twoWheeler');
      expect(report.toText(), contains('two-wheeler settings'));
      expect(report.durations, isNotEmpty);
    });

    test('a walk recorded as a pedestrian is not replayed as a car', () {
      final walk = simulateDriveLog(
        setup: calibrationDrive(),
        segments: const [DriveSegment(seconds: 60)],
        vehicle: 'pedestrian',
      );
      final report = _run(walk);
      expect(report.vehicleClass, VehicleClass.pedestrian);
      expect(report.toText(), contains('pedestrian settings'));
    });

    test('a log that does not say what it was recorded on is replayed as a car',
        () {
      expect(cityReport.vehicleClass, VehicleClass.car);
      expect(cityReport.profile.vehicle, isNull);
      expect(cityReport.toText(), contains('car settings'));
    });

    test('a real phone log is timed by its sensors, not by its t=0 header', () {
      // A recorded log opens with a header stamped u=0 while every sensor line
      // carries the phone's own uptime clock (~1.8e15 us).
      const offset = 1789898939927459;
      final shifted = [
        for (final r in city)
          r.type == DriveRecordType.meta
              ? r
              : DriveRecord.fromJson(
                  {...r.toJson(), 'u': r.monotonicUs + offset})!,
      ];
      final report = _run(shifted);
      expect(report.profile.durationS,
          closeTo(cityReport.profile.durationS, 1));
      expect(report.coreLedFromS, closeTo(cityReport.coreLedFromS!, 1));
      expect(report.forDuration(30)!.engine.medianM,
          closeTo(cityReport.forDuration(30)!.engine.medianM, 1));
    });

    test('the same log always gives the same report', () {
      expect(_run(city).toText(), _run(city).toText());
    });

    test('the report names its source, device and every duration', () {
      final text = cityReport.toText();
      expect(text, contains('reference city drive'));
      expect(text, contains('simulator'));
      for (final s in const ['10 s', '30 s', '60 s']) {
        expect(text, contains(s));
      }
    });

    test('reports the phone-side facts the result depends on', () {
      final p = cityReport.profile;
      expect(p.imuHz, closeTo(50, 1));
      expect(p.gnssHz, closeTo(1, 0.1));
      expect(p.medianTruthAccuracyM, 5);
      expect(p.deviceModel, 'simulator');
    });

    test('reports along/cross-track error, max sigma and a verdict', () {
      final r = cityReport.forDuration(30)!;
      // The drive turns, so a direction of travel is always available and
      // every window should decompose cleanly.
      expect(r.medianAlongTrackM, isNonNegative);
      expect(r.medianCrossTrackM, isNonNegative);
      expect(r.medianMaxSigmaM, greaterThan(0));
      // Along + cross should reconstruct roughly the same magnitude as the
      // plain radial error (Pythagoras on the decomposition).
      final radial = math.sqrt(r.medianAlongTrackM * r.medianAlongTrackM +
          r.medianCrossTrackM * r.medianCrossTrackM);
      expect(radial, closeTo(r.engine.medianM, r.engine.medianM * 0.6 + 5));
      expect(cityReport.driftTargetPct, 10);
      expect(cityReport.passed, isNotNull);
      expect(cityReport.toText(), contains('Verdict:'));
    });

    test('the verdict is PASS only when every scored duration clears the '
        'target', () {
      const samples = [
        OutageSample(
            startUs: 0,
            holdErrorM: 100,
            engineErrorM: 5,
            engineSigmaM: 3,
            distanceM: 100),
      ];
      final good = DurationResult.of(30, samples);
      expect(good.passed(10), isTrue);
      const bad = [
        OutageSample(
            startUs: 0,
            holdErrorM: 100,
            engineErrorM: 40,
            engineSigmaM: 3,
            distanceM: 100),
      ];
      final failing = DurationResult.of(30, bad);
      expect(failing.passed(10), isFalse);
    });
  });
}
