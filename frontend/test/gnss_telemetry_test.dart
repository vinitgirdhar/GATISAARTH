import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/gnss/gnss_telemetry.dart';

void main() {
  group('GnssTelemetrySnapshot', () {
    test('parses Android constellation telemetry without inventing satellites',
        () {
      final snapshot = GnssTelemetrySnapshot.fromPlatformMap({
        'timestampMs': 1727000000123,
        'permissionGranted': true,
        'statusSupported': true,
        'rawMeasurementsSupported': true,
        'satellites': [
          {
            'svid': 3,
            'constellation': 7,
            'cn0DbHz': 42.5,
            'usedInFix': true,
            'carrierFrequencyHz': 1176.45e6,
          },
          {
            'svid': 8,
            'constellation': 7,
            'cn0DbHz': 37,
            'usedInFix': false,
          },
          {
            'svid': 21,
            'constellation': 1,
            'cn0DbHz': 31.5,
            'usedInFix': true,
          },
        ],
      });

      expect(snapshot.permissionGranted, isTrue);
      expect(snapshot.statusSupported, isTrue);
      expect(snapshot.rawMeasurementsSupported, isTrue);
      expect(snapshot.satellites, hasLength(3));
      expect(snapshot.visibleCount, 3);
      expect(snapshot.usedInFixCount, 2);
      expect(snapshot.countFor(GnssConstellation.navic), 2);
      expect(snapshot.usedCountFor(GnssConstellation.navic), 1);
      expect(
          snapshot.meanCn0For(GnssConstellation.navic), closeTo(39.75, 0.001));
      expect(snapshot.satellites.first.carrierBand, 'L5');
      expect(
        snapshot.recordedAt,
        DateTime.fromMillisecondsSinceEpoch(1727000000123),
      );
    });

    test('invalid platform values degrade to an honest empty snapshot', () {
      final snapshot = GnssTelemetrySnapshot.fromPlatformMap({
        'permissionGranted': false,
        'statusSupported': true,
        'rawMeasurementsSupported': false,
        'satellites': [
          {'svid': 'not-a-number', 'constellation': 1, 'cn0DbHz': 30},
          {'svid': 4, 'constellation': 99, 'cn0DbHz': double.nan},
          'bad item',
        ],
      });

      expect(snapshot.permissionGranted, isFalse);
      expect(snapshot.hasRealStatus, isFalse);
      expect(snapshot.satellites, isEmpty);
      expect(snapshot.meanCn0For(GnssConstellation.gps), isNull);
    });

    test('old maps without the new receiver-clock/multipath keys still parse',
        () {
      final snapshot = GnssTelemetrySnapshot.fromPlatformMap({
        'permissionGranted': true,
        'statusSupported': true,
        'rawMeasurementsSupported': true,
        'satellites': [
          {'svid': 3, 'constellation': 1, 'cn0DbHz': 40, 'usedInFix': true},
        ],
      });

      expect(snapshot.clockDiscontinuityCount, isNull);
      expect(snapshot.clockBiasNanos, isNull);
      expect(snapshot.clockDriftNanosPerSecond, isNull);
      expect(snapshot.multipathDetectedCount, isNull);
      expect(snapshot.meanAutomaticGainControlDb, isNull);
    });

    test('parses the optional receiver-clock/multipath/AGC evidence', () {
      final snapshot = GnssTelemetrySnapshot.fromPlatformMap({
        'permissionGranted': true,
        'statusSupported': true,
        'rawMeasurementsSupported': true,
        'satellites': [],
        'clockDiscontinuityCount': 2,
        'clockBiasNanos': 1234.5,
        'clockDriftNanosPerSecond': -0.75,
        'multipathDetectedCount': 3,
        'meanAutomaticGainControlDb': 21.4,
      });

      expect(snapshot.clockDiscontinuityCount, 2);
      expect(snapshot.clockBiasNanos, closeTo(1234.5, 0.001));
      expect(snapshot.clockDriftNanosPerSecond, closeTo(-0.75, 0.001));
      expect(snapshot.multipathDetectedCount, 3);
      expect(snapshot.meanAutomaticGainControlDb, closeTo(21.4, 0.001));
    });

    test('maps every Android constellation code used by modern phones', () {
      expect(GnssConstellation.fromAndroidType(1), GnssConstellation.gps);
      expect(GnssConstellation.fromAndroidType(3), GnssConstellation.glonass);
      expect(GnssConstellation.fromAndroidType(4), GnssConstellation.qzss);
      expect(GnssConstellation.fromAndroidType(5), GnssConstellation.beidou);
      expect(GnssConstellation.fromAndroidType(6), GnssConstellation.galileo);
      expect(GnssConstellation.fromAndroidType(7), GnssConstellation.navic);
      expect(GnssConstellation.fromAndroidType(99), GnssConstellation.unknown);
    });
  });
}
