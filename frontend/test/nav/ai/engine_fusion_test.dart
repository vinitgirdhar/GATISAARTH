import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/ai/ai_types.dart';
import 'package:gatisaarth/core/nav/gnss/gnss_quality.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';
import 'package:gatisaarth/core/nav/replay/replay_engine.dart';

import '../support/ai_injection.dart';
import '../support/drive_simulator.dart';

/// P3 only: the AI fusion confidence is in the loop and nothing else is.
const _fusionOnly = AiConfig(
    enabled: true, speedMeasurement: false, disturbanceAdaptation: false);

List<DriveSegment> _cruise() => const [
      DriveSegment(seconds: 8, longitudinalAccel: 1.6),
      DriveSegment(seconds: 60),
    ];

/// [records] with a fusion confidence recorded after every tenth IMU line
/// (every 200 ms at 50 Hz): what a Python job would inject.
List<DriveRecord> _withFusion(List<DriveRecord> records,
    {double gnss = 1, double ins = 1}) {
  var n = 0;
  return [
    for (final r in records) ...[
      r,
      if (r.type == DriveRecordType.imu && ++n % 10 == 0)
        DriveRecord.ai(
          monotonicUs: r.monotonicUs,
          fusion: FusionConfidence(
              gnssTrust: gnss, insTrust: ins, monotonicUs: r.monotonicUs),
        ),
    ],
  ];
}

void main() {
  late List<DriveRecord> plain;
  late int marker;

  setUpAll(() {
    plain = simulateDriveLogWithAi(
        setup: calibrationDrive(),
        segments: _cruise(),
        inject: false,
        truth: true);
    marker = plain
        .firstWhere((r) => r.type == DriveRecordType.marker)
        .monotonicUs;
  });

  /// How far (m) one fix [offsetM] east of the position moves the fused
  /// position, under [ai] and the fusion confidence [gnssTrust] (null: none).
  double pull(AiConfig ai, {double? gnssTrust, double offsetM = 12}) {
    final replay = ReplayEngine(records: plain, config: NavConfig(ai: ai));
    final at = marker + 30 * 1000000;
    replay.runTo(at);
    final engine = replay.engine;
    if (gnssTrust != null) {
      engine.onFusionConfidence(FusionConfidence(
          gnssTrust: gnssTrust, monotonicUs: at));
    }
    // The filter's own state, not the last snapshot (up to 100 ms old): the
    // vehicle is doing 12 m/s.
    final s = engine.filter.state!;
    final east = NavMath.addNed(
        latDeg: s.latitudeDeg,
        lonDeg: s.longitudeDeg,
        altM: 0,
        north: 0,
        east: offsetM,
        down: 0);
    final fix = GnssObservation(
      latitudeDeg: east[0],
      longitudeDeg: east[1],
      accuracyM: 5,
      monotonicUs: at + 500000,
      altitudeM: 0,
    );
    engine.onGnss(fix);
    final after = engine.filter.state!;
    return NavMath.horizontalDistance(
        lat0: s.latitudeDeg,
        lon0: s.longitudeDeg,
        lat1: after.latitudeDeg,
        lon1: after.longitudeDeg);
  }

  group('GNSS trust divides the GNSS measurement variance', () {
    test('a distrusted fix moves the position less, by about the gain', () {
      final full = pull(_fusionOnly, gnssTrust: 1.0);
      final low = pull(_fusionOnly, gnssTrust: 0.25);
      expect(full, greaterThan(1));
      expect(low, greaterThan(0));
      // R x4 on a filter already tight around this cruise: clearly less pull.
      expect(low, lessThan(full * 0.7));
    });

    test('a trust of 1, no trust at all, and the AI being off are the same '
        'engine, to the bit', () {
      final none = pull(const AiConfig());
      expect(pull(_fusionOnly), none);
      expect(pull(_fusionOnly, gnssTrust: 1.0), none);
    });

    test('the fusion switch is real: with it off the trust is ignored', () {
      final ignored = pull(
          const AiConfig(
              enabled: true,
              speedMeasurement: false,
              disturbanceAdaptation: false,
              fusionTrust: false),
          gnssTrust: 0.1);
      expect(ignored, pull(const AiConfig()));
    });

    test('the trust expires: a stale one is forgotten, not obeyed forever', () {
      final replay =
          ReplayEngine(records: plain, config: const NavConfig(ai: _fusionOnly));
      final at = marker + 30 * 1000000;
      replay.runTo(at);
      replay.engine.onFusionConfidence(
          FusionConfidence(gnssTrust: 0.1, monotonicUs: at));
      expect(replay.engine.aiDiagnostics.fusion?.gnssTrust, 0.1);
      replay.runTo(at + 2 * 1000000);
      expect(replay.engine.aiDiagnostics.fusion, isNull);
      expect(replay.engine.aiDiagnostics.gnssSigmaScale, 1.0);
    });
  });

  group('INS trust divides the strapdown process noise', () {
    double speedSigmaAfterBlackout(double? insTrust) {
      final log = blackoutFrom(
          _withFusion(plain, ins: insTrust ?? 1), marker + 20 * 1000000);
      final replay = ReplayEngine(
          records: insTrust == null ? withoutAi(log) : log,
          config: const NavConfig(ai: _fusionOnly))
        ..runToEnd();
      return replay.engine.snapshot!.speedSigmaMps!;
    }

    test('half the trust means twice the process noise: the filter admits '
        'more speed uncertainty after a blackout', () {
      final neutral = speedSigmaAfterBlackout(null);
      final half = speedSigmaAfterBlackout(0.5);
      final quarter = speedSigmaAfterBlackout(0.25);
      expect(half, greaterThan(neutral));
      expect(quarter, greaterThan(half));
      // Process noise x4 is up to x2 on the sigma; the part of the speed
      // uncertainty that comes from the attitude error rather than from the
      // process noise does not scale, so the ratio lands below that.
      expect(quarter / neutral, inInclusiveRange(1.2, 2.1));
    });

    test('a trust of 1 injected every 200 ms changes nothing', () {
      expect(speedSigmaAfterBlackout(1.0), speedSigmaAfterBlackout(null));
    });

    test('the diagnostics say what is being applied, and that it is AI',
        () {
      final log = _withFusion(plain, gnss: 0.5, ins: 0.5);
      final replay = ReplayEngine(
          records: log, config: const NavConfig(ai: _fusionOnly))
        ..runToEnd();
      final d = replay.engine.aiDiagnostics;
      expect(d.fusionActive, isTrue);
      expect(d.fusion!.gnssTrust, 0.5);
      expect(d.processNoiseScale, closeTo(2.0, 1e-12));
      expect(d.gnssSigmaScale, closeTo(1.4142135623730951, 1e-12));
      expect(d.summary, contains('fusion'));
    });
  });

  test('a distrusted GNSS costs accuracy when the GNSS was right, which is why '
      'the trust must be earned by a model, not assumed', () {
    // Honest about the trade: scaling R by 1/trust is only a good idea when the
    // model is right about the GNSS. On a clean drive it just throws away
    // information, and the replay says so.
    final trusted = ReplayEngine(
        records: _withFusion(plain, gnss: 1),
        config: const NavConfig(ai: _fusionOnly))
      ..runToEnd();
    final distrusted = ReplayEngine(
        records: _withFusion(plain, gnss: 0.2),
        config: const NavConfig(ai: _fusionOnly))
      ..runToEnd();
    expect(distrusted.summary().meanErrorM!,
        greaterThanOrEqualTo(trusted.summary().meanErrorM! * 0.9));
  });
}
