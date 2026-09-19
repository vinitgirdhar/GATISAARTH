import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_quality.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';

const double lat0 = 28.6139;
const double lon0 = 77.2090;

GnssObservation fix({
  double? lat,
  double? lon,
  double accuracy = 5,
  required int seconds,
  double? speed,
  double? bearing,
  bool mocked = false,
  double northOffset = 0,
  double eastOffset = 0,
}) {
  final moved = NavMath.addNed(
    latDeg: lat ?? lat0,
    lonDeg: lon ?? lon0,
    altM: 0,
    north: northOffset,
    east: eastOffset,
    down: 0,
  );
  return GnssObservation(
    latitudeDeg: moved[0],
    longitudeDeg: moved[1],
    accuracyM: accuracy,
    monotonicUs: seconds * 1000000,
    speedMps: speed,
    bearingDeg: bearing,
    isMocked: mocked,
  );
}

void main() {
  group('quality banding', () {
    test('a tight fix is excellent, a loose one is not', () {
      final e = GnssQualityEngine();
      expect(e.assess(fix(accuracy: 4, seconds: 0)).quality,
          GnssQualityClass.excellent);

      final e2 = GnssQualityEngine();
      expect(e2.assess(fix(accuracy: 15, seconds: 0)).quality,
          GnssQualityClass.good);

      final e3 = GnssQualityEngine();
      expect(e3.assess(fix(accuracy: 45, seconds: 0)).quality,
          GnssQualityClass.degraded);

      final e4 = GnssQualityEngine();
      expect(e4.assess(fix(accuracy: 100, seconds: 0)).quality,
          GnssQualityClass.poor);
    });

    test('the score falls as accuracy worsens', () {
      double score(double accuracy) =>
          GnssQualityEngine().assess(fix(accuracy: accuracy, seconds: 0)).score;
      expect(score(3), greaterThan(score(15)));
      expect(score(15), greaterThan(score(45)));
      expect(score(45), greaterThan(score(110)));
    });

    test('measurement sigma is inflated beyond the reported accuracy when the '
        'score is low', () {
      final good = GnssQualityEngine().assess(fix(accuracy: 5, seconds: 0));
      expect(good.horizontalSigmaM, closeTo(5, 0.01));

      final poor = GnssQualityEngine().assess(fix(accuracy: 100, seconds: 0));
      expect(poor.horizontalSigmaM, greaterThan(100));
    });
  });

  group('rejection', () {
    test('null island is rejected', () {
      final e = GnssQualityEngine();
      final r = e.assess(const GnssObservation(
        latitudeDeg: 0,
        longitudeDeg: 0,
        accuracyM: 5,
        monotonicUs: 0,
      ));
      expect(r.reason, GnssRejectReason.outOfBounds);
      expect(r.usable, isFalse);
    });

    test('NaN and out-of-range coordinates are rejected', () {
      final e = GnssQualityEngine();
      expect(
        e
            .assess(const GnssObservation(
              latitudeDeg: double.nan,
              longitudeDeg: 77,
              accuracyM: 5,
              monotonicUs: 0,
            ))
            .reason,
        GnssRejectReason.nonFinite,
      );
      expect(
        e
            .assess(const GnssObservation(
              latitudeDeg: 95,
              longitudeDeg: 77,
              accuracyM: 5,
              monotonicUs: 0,
            ))
            .reason,
        GnssRejectReason.nonFinite,
      );
    });

    test('a mocked fix is rejected and said so', () {
      final r = GnssQualityEngine().assess(fix(seconds: 0, mocked: true));
      expect(r.reason, GnssRejectReason.mocked);
      expect(r.notes.first, contains('mocked'));
    });

    test('accuracy worse than the usable limit is rejected outright', () {
      final r = GnssQualityEngine().assess(fix(accuracy: 500, seconds: 0));
      expect(r.reason, GnssRejectReason.accuracyTooPoor);
      expect(r.quality, GnssQualityClass.invalid);
    });

    test('a teleport is rejected', () {
      final e = GnssQualityEngine();
      expect(e.assess(fix(seconds: 0)).usable, isTrue);
      // 2 km in one second.
      final r = e.assess(fix(seconds: 1, northOffset: 2000));
      expect(r.reason, GnssRejectReason.impossibleJump);
      expect(r.notes.single, contains('m/s'));
    });

    test('ordinary highway motion is NOT a teleport', () {
      final e = GnssQualityEngine();
      e.assess(fix(seconds: 0, speed: 30));
      // 30 m/s = 108 km/h.
      final r = e.assess(fix(seconds: 1, northOffset: 30, speed: 30));
      expect(r.usable, isTrue);
    });

    test('two loose fixes a short distance apart are noise, not a jump', () {
      final e = GnssQualityEngine();
      e.assess(fix(accuracy: 60, seconds: 0));
      // 80 m apart in 1 s looks like 80 m/s, but both fixes claim 60 m of
      // uncertainty, so the tolerance absorbs it.
      final r = e.assess(fix(accuracy: 60, seconds: 1, northOffset: 80));
      expect(r.usable, isTrue);
    });

    test('an impossible acceleration between fixes is rejected', () {
      final e = GnssQualityEngine();
      e.assess(fix(seconds: 0, speed: 0));
      e.assess(fix(seconds: 1, northOffset: 1, speed: 1));
      // 1 m/s to 60 m/s in one second.
      final r = e.assess(fix(seconds: 2, northOffset: 61, speed: 60));
      expect(
        r.reason,
        anyOf(GnssRejectReason.impossibleAcceleration,
            GnssRejectReason.impossibleJump),
      );
    });

    test('a fix that is not newer than the last accepted one is rejected', () {
      final e = GnssQualityEngine();
      e.assess(fix(seconds: 10));
      expect(e.assess(fix(seconds: 10)).reason, GnssRejectReason.stale);
      expect(e.assess(fix(seconds: 5)).reason, GnssRejectReason.stale);
    });

    test('an impossible heading change at speed is rejected', () {
      final e = GnssQualityEngine();
      e.assess(fix(seconds: 0, speed: 20, bearing: 0));
      final r = e.assess(
          fix(seconds: 1, northOffset: 20, speed: 20, bearing: 190));
      expect(r.reason, GnssRejectReason.impossibleHeadingChange);
    });

    test('a wild bearing while parked is ignored, not rejected', () {
      // A stationary phone's GNSS bearing spins freely; that is normal.
      final e = GnssQualityEngine();
      e.assess(fix(seconds: 0, speed: 0.1, bearing: 0));
      final r = e.assess(fix(seconds: 1, speed: 0.1, bearing: 190));
      expect(r.usable, isTrue);
    });

    test('consecutive rejections are counted', () {
      final e = GnssQualityEngine();
      e.assess(fix(seconds: 0));
      e.assess(fix(seconds: 1, northOffset: 5000));
      e.assess(fix(seconds: 2, northOffset: 5000));
      expect(e.consecutiveRejections, 2);
      e.assess(fix(seconds: 3, northOffset: 5));
      expect(e.consecutiveRejections, 0);
    });
  });

  group('velocity usability', () {
    test('a sharp fix with speed offers a velocity measurement', () {
      final r = GnssQualityEngine()
          .assess(fix(accuracy: 6, seconds: 0, speed: 18));
      expect(r.useVelocity, isTrue);
      expect(r.velocitySigmaMps, isNotNull);
    });

    test('a loose fix does not, and says so with a null sigma', () {
      final r = GnssQualityEngine()
          .assess(fix(accuracy: 90, seconds: 0, speed: 18));
      expect(r.useVelocity, isFalse);
      expect(r.velocitySigmaMps, isNull);
    });

    test('a fix with no speed field offers no velocity', () {
      final r = GnssQualityEngine().assess(fix(accuracy: 5, seconds: 0));
      expect(r.useVelocity, isFalse);
    });
  });

  group('integrity monitor', () {
    test('clean fixes stay healthy', () {
      final e = GnssQualityEngine();
      for (var i = 0; i < 10; i++) {
        final r = e.assess(fix(seconds: i, northOffset: i * 20, speed: 20));
        expect(r.integrity, GnssIntegrity.healthy);
      }
    });

    test('repeated rejections raise an integrity anomaly, worded cautiously',
        () {
      final e = GnssQualityEngine();
      e.assess(fix(seconds: 0));
      late GnssAssessment last;
      for (var i = 1; i <= 4; i++) {
        last = e.assess(fix(seconds: i, northOffset: 9000));
      }
      expect(last.integrity, GnssIntegrity.anomaly);
      // Never claims to have proven spoofing.
      expect(last.integrity.label, 'GNSS integrity anomaly detected');
      expect(last.integrity.label.toLowerCase(), isNot(contains('spoof')));
    });

    test('a stationary GNSS while the vehicle moves is flagged as an urban '
        'canyon signature', () {
      final e = GnssQualityEngine();
      // Eight fixes all within a couple of metres while the IMU says 15 m/s.
      GnssAssessment? last;
      for (var i = 0; i < 12; i++) {
        last = e.assess(
          fix(seconds: i, northOffset: (i.isEven ? 1.5 : -1.5)),
          inertialSpeedMps: 15,
        );
      }
      expect(last!.notes.any((n) => n.contains('oscillating')), isTrue);
      expect(last.score, lessThan(0.6));
      expect(last.integrity, isNot(GnssIntegrity.healthy));
    });

    test('the same oscillation while genuinely parked is not flagged', () {
      final e = GnssQualityEngine();
      GnssAssessment? last;
      for (var i = 0; i < 12; i++) {
        last = e.assess(
          fix(seconds: i, northOffset: (i.isEven ? 1.5 : -1.5)),
          inertialSpeedMps: 0.1,
        );
      }
      expect(last!.notes, isEmpty);
      expect(last.integrity, GnssIntegrity.healthy);
    });

    test('a GNSS bearing fighting the inertial heading lowers the score', () {
      final e = GnssQualityEngine();
      final agreeing = e.assess(
        fix(seconds: 0, speed: 20, bearing: 90),
        inertialHeadingDeg: 88,
        inertialSpeedMps: 20,
      );
      final e2 = GnssQualityEngine();
      final fighting = e2.assess(
        fix(seconds: 0, speed: 20, bearing: 270),
        inertialHeadingDeg: 88,
        inertialSpeedMps: 20,
      );
      expect(fighting.score, lessThan(agreeing.score));
      expect(fighting.notes.any((n) => n.contains('disagrees')), isTrue);
    });

    test('large GNSS movement while the vehicle is stationary is suspicious',
        () {
      final e = GnssQualityEngine();
      e.assess(fix(seconds: 0), inertialSpeedMps: 0.05);
      final r = e.assess(
        fix(seconds: 1, northOffset: 40),
        inertialSpeedMps: 0.05,
      );
      expect(r.notes.any((n) => n.contains('stationary')), isTrue);
      expect(r.score, lessThan(0.5));
    });

    test('reset clears the history so a new session starts clean', () {
      final e = GnssQualityEngine();
      e.assess(fix(seconds: 0));
      e.assess(fix(seconds: 1, northOffset: 9000));
      e.reset();
      expect(e.consecutiveRejections, 0);
      expect(e.windowLength, 0);
      expect(e.assess(fix(seconds: 0)).integrity, GnssIntegrity.healthy);
    });
  });

  group('honesty', () {
    test('satellite count is null unless the platform gave one', () {
      const withoutCount = GnssObservation(
        latitudeDeg: lat0,
        longitudeDeg: lon0,
        accuracyM: 5,
        monotonicUs: 0,
      );
      expect(withoutCount.satellitesUsed, isNull);
    });
  });
}
