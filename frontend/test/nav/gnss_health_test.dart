import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_health.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_quality.dart';

GnssHealthSatelliteSample sat({
  GnssHealthConstellation constellation = GnssHealthConstellation.gps,
  double cn0 = 35,
  bool used = true,
  double? elevation = 45,
}) =>
    GnssHealthSatelliteSample(
      constellation: constellation,
      cn0DbHz: cn0,
      usedInFix: used,
      elevationDegrees: elevation,
    );

List<GnssHealthSatelliteSample> goodConstellation({int count = 8}) => [
      for (var i = 0; i < count; i++)
        sat(
          constellation: i.isEven
              ? GnssHealthConstellation.gps
              : GnssHealthConstellation.galileo,
        ),
    ];

void main() {
  group('waiting / pre-fix', () {
    test('reports waiting before any fix has ever been accepted', () {
      final classifier = GnssHealthClassifier();
      expect(classifier.assessment.state, GnssHealthState.waiting);

      classifier.addReceiverSample(
        GnssHealthReceiverSample(satellites: goodConstellation()),
        nowSeconds: 1,
      );
      // Telemetry alone (no accepted fix yet) still means waiting, not
      // outage — the app has never had a position at all.
      expect(classifier.assessment.state, GnssHealthState.waiting);
    });
  });

  group('outage', () {
    test('no accepted fix for longer than the stale threshold is outage',
        () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: 0);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(satellites: goodConstellation()),
        nowSeconds: 0.1,
      );
      expect(classifier.assessment.state, GnssHealthState.normal);

      classifier.addReceiverSample(
        GnssHealthReceiverSample(satellites: goodConstellation()),
        nowSeconds: 10,
      );
      expect(classifier.assessment.state, GnssHealthState.outage);
    });

    test('fresh fixes with no satellite flagged used are not an outage: the '
        'receiver just does not report usage (emulator, some chipsets)', () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: 0);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(
          satellites: [for (var i = 0; i < 8; i++) sat(used: false)],
        ),
        nowSeconds: 0.5,
      );
      expect(classifier.assessment.state, GnssHealthState.normal);
    });
  });

  group('normal', () {
    test('plenty of satellites and strong signal is normal', () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 4, nowSeconds: 0);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(satellites: goodConstellation()),
        nowSeconds: 0.5,
      );
      expect(classifier.assessment.state, GnssHealthState.normal);
      expect(classifier.assessment.metrics.satellitesUsed, 8);
    });
  });

  group('degraded', () {
    test('few used satellites is degraded', () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: 0);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(
          satellites: [sat(), sat(), sat(constellation: GnssHealthConstellation.galileo)],
        ),
        nowSeconds: 0.5,
      );
      expect(classifier.assessment.state, GnssHealthState.degraded);
    });

    test('weak mean C/N0 is degraded even with old-device null fields', () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: 0);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(
          satellites: [
            for (var i = 0; i < 8; i++)
              sat(cn0: 15, elevation: null, constellation: GnssHealthConstellation.gps),
          ],
          // No multipath/AGC/clock evidence — this device does not report it.
        ),
        nowSeconds: 0.5,
      );
      expect(classifier.assessment.state, GnssHealthState.degraded);
      expect(classifier.assessment.metrics.multipathDetectedCount, isNull);
      expect(classifier.assessment.metrics.meanAutomaticGainControlDb, isNull);
      expect(classifier.assessment.metrics.clockDiscontinuityCount, isNull);
    });
  });

  group('multipath suspected', () {
    test('several multipath-flagged measurements trigger it', () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: 0);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(
          satellites: goodConstellation(),
          multipathDetectedCount: 4,
        ),
        nowSeconds: 0.5,
      );
      expect(classifier.assessment.state, GnssHealthState.multipathSuspected);
    });

    test(
        'position jumps rejected while C/N0 is fine points at multipath, not interference',
        () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: 0);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(satellites: goodConstellation()),
        nowSeconds: 0.5,
      );
      classifier.addFix(
          reason: GnssRejectReason.impossibleJump, nowSeconds: 1);
      classifier.addFix(
          reason: GnssRejectReason.impossibleHeadingChange, nowSeconds: 1.5);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(satellites: goodConstellation()),
        nowSeconds: 2,
      );
      expect(classifier.assessment.state, GnssHealthState.multipathSuspected);
    });
  });

  group('interference suspected', () {
    test('broadband C/N0 collapse across constellations is interference', () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: 0);
      // A few clean samples establish the "before" baseline.
      for (var t = 0.5; t < 2; t += 0.5) {
        classifier.addReceiverSample(
          GnssHealthReceiverSample(satellites: goodConstellation()),
          nowSeconds: t,
        );
      }
      // Then every satellite's signal collapses at once.
      classifier.addReceiverSample(
        GnssHealthReceiverSample(
          satellites: goodConstellation().map((s) => sat(
                constellation: s.constellation,
                cn0: s.cn0DbHz - 15,
              )).toList(),
        ),
        nowSeconds: 2.5,
      );
      expect(
          classifier.assessment.state, GnssHealthState.interferenceSuspected);
    });

    test('a sharp AGC drop is interference, never worded as spoofing', () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: 0);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(
          satellites: goodConstellation(),
          meanAutomaticGainControlDb: 20,
        ),
        nowSeconds: 0.5,
      );
      classifier.addReceiverSample(
        GnssHealthReceiverSample(
          satellites: goodConstellation(),
          meanAutomaticGainControlDb: 12,
        ),
        nowSeconds: 1,
      );
      expect(
          classifier.assessment.state, GnssHealthState.interferenceSuspected);
      for (final reason in classifier.assessment.reasons) {
        expect(reason.toLowerCase(), isNot(contains('spoof')));
      }
    });
  });

  group('hysteresis', () {
    test('a single clean sample does not clear a bad state immediately', () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: 0);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(
          satellites: goodConstellation(),
          multipathDetectedCount: 5,
        ),
        nowSeconds: 0.5,
      );
      expect(classifier.assessment.state, GnssHealthState.multipathSuspected);

      // One clean sample right after — should not instantly clear.
      classifier.addReceiverSample(
        GnssHealthReceiverSample(satellites: goodConstellation()),
        nowSeconds: 0.6,
      );
      expect(classifier.assessment.state, GnssHealthState.multipathSuspected);

      // Sustained clean evidence for the full window clears it — fresh fixes
      // keep arriving throughout so this exercises the multipath hysteresis,
      // not an unrelated fix-freshness timeout.
      for (var t = 1.0; t <= 20; t += 1.0) {
        classifier.addFix(
            reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: t);
        classifier.addReceiverSample(
          GnssHealthReceiverSample(satellites: goodConstellation()),
          nowSeconds: t,
        );
      }
      expect(classifier.assessment.state, GnssHealthState.normal);
    });

    test('entering a worse state is immediate', () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: 0);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(satellites: goodConstellation()),
        nowSeconds: 0.5,
      );
      expect(classifier.assessment.state, GnssHealthState.normal);

      classifier.addReceiverSample(
        GnssHealthReceiverSample(
          satellites: goodConstellation(),
          multipathDetectedCount: 5,
        ),
        nowSeconds: 0.6,
      );
      expect(classifier.assessment.state, GnssHealthState.multipathSuspected);
    });
  });

  group('reset', () {
    test('reset returns to waiting', () {
      final classifier = GnssHealthClassifier();
      classifier.addFix(reason: GnssRejectReason.none, accuracyM: 5, nowSeconds: 0);
      classifier.addReceiverSample(
        GnssHealthReceiverSample(satellites: goodConstellation()),
        nowSeconds: 0.5,
      );
      expect(classifier.assessment.state, GnssHealthState.normal);
      classifier.reset();
      expect(classifier.assessment.state, GnssHealthState.waiting);
    });
  });
}
