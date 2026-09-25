import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/model/outage_recovery.dart';
import 'package:gatisaarth/core/nav/model/simulated_outage.dart';

const double _metresPerDegree = 111320;
final DateTime _t0 = DateTime(2026, 9, 25, 14, 32, 18);

double _lat(double m) => m / _metresPerDegree;
double _lon(double m, double atLat) =>
    m / (_metresPerDegree * math.cos(atLat * math.pi / 180));

/// A straight track heading due north, one fix every 10 m for [lengthM].
List<TruthFix> _straightTrack(double lengthM, {int stepM = 10}) {
  final fixes = <TruthFix>[];
  for (var d = 0.0; d <= lengthM; d += stepM) {
    fixes.add(TruthFix(
      latitudeDeg: _lat(d),
      longitudeDeg: 0,
      accuracyM: 5,
      at: _t0.add(Duration(milliseconds: (d * 200).round())),
    ));
  }
  return fixes;
}

void main() {
  group('SimulatedOutageScorer', () {
    test('pure lateral offset reads as cross-track, not along-track', () {
      final truth = _straightTrack(300);
      final result = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 30),
        actualDuration: const Duration(seconds: 30),
        truthFixes: truth,
        // 20 m due east of the final truth fix — pure cross-track.
        lastDrLatitudeDeg: truth.last.latitudeDeg,
        lastDrLongitudeDeg: _lon(20, truth.last.latitudeDeg),
        coreLed: true,
      );

      expect(result.distanceM, closeTo(300, 0.5));
      expect(result.endpointErrorM, closeTo(20, 0.1));
      expect(result.crossTrackM, closeTo(20, 0.5));
      expect(result.alongTrackM, closeTo(0, 0.5));
      expect(result.driftPct, closeTo(100 * 20 / 300, 1e-6));
    });

    test('pure along-track offset reads as along-track, not cross-track', () {
      final truth = _straightTrack(300);
      final result = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 30),
        actualDuration: const Duration(seconds: 30),
        truthFixes: truth,
        // 15 m further north than the final truth fix — pure along-track.
        lastDrLatitudeDeg: _lat(300 + 15),
        lastDrLongitudeDeg: 0,
        coreLed: true,
      );

      expect(result.alongTrackM, closeTo(15, 0.5));
      expect(result.crossTrackM, closeTo(0, 0.5));
    });

    test('a curved track still decomposes against the local tangent', () {
      // A quarter-circle of radius 100 m, turning from heading north to east.
      final truth = <TruthFix>[];
      for (var i = 0; i <= 18; i++) {
        final angle = i * (math.pi / 2) / 18; // 0..pi/2
        final north = 100 * math.sin(angle);
        final east = 100 * (1 - math.cos(angle));
        truth.add(TruthFix(
          latitudeDeg: _lat(north),
          longitudeDeg: _lon(east, _lat(north)),
          accuracyM: 5,
          at: _t0.add(Duration(seconds: i)),
        ));
      }
      // Near the end the truth is heading almost due east. Offset the DR
      // position purely along that local tangent (east) from the last fix.
      final last = truth.last;
      final result = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 18),
        actualDuration: const Duration(seconds: 18),
        truthFixes: truth,
        lastDrLatitudeDeg: last.latitudeDeg,
        lastDrLongitudeDeg:
            last.longitudeDeg + _lon(10, last.latitudeDeg),
        coreLed: true,
      );
      // Whatever the exact split, the two components must reconstruct the
      // total error (an orthogonal decomposition), and it should read mostly
      // along-track since the offset was applied along the local tangent.
      final along = result.alongTrackM!, cross = result.crossTrackM!;
      expect(math.sqrt(along * along + cross * cross),
          closeTo(result.endpointErrorM!, 0.05));
      expect(along, greaterThan(cross));
    });

    test('fewer than two truth fixes has no distance and no track split', () {
      final result = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 10),
        actualDuration: const Duration(seconds: 10),
        truthFixes: [
          TruthFix(latitudeDeg: 0, longitudeDeg: 0, accuracyM: 5, at: _t0),
        ],
        lastDrLatitudeDeg: _lat(5),
        lastDrLongitudeDeg: 0,
        coreLed: true,
      );
      expect(result.distanceM, 0);
      expect(result.alongTrackM, isNull);
      expect(result.crossTrackM, isNull);
      // A single truth fix is still a valid endpoint to measure error against.
      expect(result.endpointErrorM, closeTo(5, 0.1));
    });

    test('no truth fixes at all leaves every distance-based metric null', () {
      final result = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 10),
        actualDuration: const Duration(seconds: 10),
        truthFixes: const [],
        lastDrLatitudeDeg: 0,
        lastDrLongitudeDeg: 0,
        coreLed: true,
      );
      expect(result.distanceM, isNull);
      expect(result.endpointErrorM, isNull);
      expect(result.driftPct, isNull);
      expect(result.meetsTarget(10), isNull);
      expect(result.fixAccuracyM, isNull);
    });

    test('sigma samples give initial, peak and final, in order sampled', () {
      final truth = _straightTrack(100);
      final result = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 30),
        actualDuration: const Duration(seconds: 30),
        truthFixes: truth,
        lastDrLatitudeDeg: truth.last.latitudeDeg,
        lastDrLongitudeDeg: truth.last.longitudeDeg,
        sigmaSamples: [
          SigmaSample(at: _t0, sigmaM: 4),
          SigmaSample(at: _t0.add(const Duration(seconds: 15)), sigmaM: 31),
          SigmaSample(at: _t0.add(const Duration(seconds: 30)), sigmaM: 28),
        ],
        coreLed: true,
      );
      expect(result.initialSigmaM, 4);
      expect(result.peakSigmaM, 31);
      expect(result.finalSigmaM, 28);
    });

    test('no sigma samples leaves the uncertainty fields null, not zero', () {
      final truth = _straightTrack(50);
      final result = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 10),
        actualDuration: const Duration(seconds: 10),
        truthFixes: truth,
        lastDrLatitudeDeg: truth.last.latitudeDeg,
        lastDrLongitudeDeg: truth.last.longitudeDeg,
        coreLed: true,
      );
      expect(result.initialSigmaM, isNull);
      expect(result.peakSigmaM, isNull);
      expect(result.finalSigmaM, isNull);
    });

    test('recovery jump is the distance from DR to the first restored fix',
        () {
      final truth = _straightTrack(100);
      final result = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 10),
        actualDuration: const Duration(seconds: 10),
        truthFixes: truth,
        lastDrLatitudeDeg: truth.last.latitudeDeg,
        lastDrLongitudeDeg: truth.last.longitudeDeg,
        firstRestoredLatitudeDeg: _lat(100 + 1.6),
        firstRestoredLongitudeDeg: 0,
        coreLed: true,
      );
      expect(result.recoveryJumpM, closeTo(1.6, 0.05));
    });

    test('no restored fix (a cancelled run) leaves recovery jump null', () {
      final truth = _straightTrack(50);
      final result = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 10),
        actualDuration: const Duration(seconds: 5),
        truthFixes: truth,
        lastDrLatitudeDeg: truth.last.latitudeDeg,
        lastDrLongitudeDeg: truth.last.longitudeDeg,
        coreLed: true,
      );
      expect(result.recoveryJumpM, isNull);
    });

    test('drift below target passes, above it does not', () {
      final pass = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 30),
        actualDuration: const Duration(seconds: 30),
        truthFixes: _straightTrack(300),
        lastDrLatitudeDeg: _lat(300),
        lastDrLongitudeDeg: _lon(10, _lat(300)),
        coreLed: true,
      );
      expect(pass.meetsTarget(10), isTrue); // 10/300 ≈ 3.3 %

      final fail = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 30),
        actualDuration: const Duration(seconds: 30),
        truthFixes: _straightTrack(100),
        lastDrLatitudeDeg: _lat(100),
        lastDrLongitudeDeg: _lon(20, _lat(100)),
        coreLed: true,
      );
      expect(fail.meetsTarget(10), isFalse); // 20/100 = 20 %
    });

    test('converts to a labelled, unrecoverable-as-real OutageRecovery', () {
      final truth = _straightTrack(200);
      final result = SimulatedOutageScorer.score(
        startedAt: _t0,
        plannedDuration: const Duration(seconds: 20),
        actualDuration: const Duration(seconds: 20),
        truthFixes: truth,
        lastDrLatitudeDeg: truth.last.latitudeDeg,
        lastDrLongitudeDeg: _lon(12, truth.last.latitudeDeg),
        sigmaSamples: [
          SigmaSample(at: _t0, sigmaM: 4),
          SigmaSample(at: _t0.add(const Duration(seconds: 20)), sigmaM: 30),
        ],
        firstRestoredLatitudeDeg: truth.last.latitudeDeg,
        firstRestoredLongitudeDeg: 0,
        coreLed: false,
      );
      final recovery = result.toOutageRecovery();
      expect(recovery, isA<OutageRecovery>());
      expect(recovery.isSimulated, isTrue);
      expect(recovery.durationS, closeTo(20, 1e-9));
      expect(recovery.distanceM, closeTo(200, 0.5));
      expect(recovery.errorM, closeTo(result.endpointErrorM!, 1e-9));
      expect(recovery.alongTrackM, result.alongTrackM);
      expect(recovery.crossTrackM, result.crossTrackM);
      expect(recovery.peakSigmaM, 30);
      expect(recovery.predictedSigmaM, 30);
      expect(recovery.coreLed, isFalse);
    });
  });
}
