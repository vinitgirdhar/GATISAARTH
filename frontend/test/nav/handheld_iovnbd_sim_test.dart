import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_benchmark.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

/// SCRATCH / exploratory harness — not part of the normal test suite, gated
/// off by default. Delete this file once reviewed (see report for path).
///
/// Synthesizes a hand-held-like phone rotation (random constant mount +
/// slow hand-wobble + occasional "handling" bursts + vibration noise) on
/// top of REAL IO-VNBD vehicle-frame IMU (already converted to the app's
/// drive-log format — see `.claude/skills/iovnbd-dataset/SKILL.md`), then
/// scores `FeatureFlags.handHeldMode` on vs off vs the hold-last-velocity
/// baseline with the same `OutageBenchmark` the app and
/// `test/nav/score_drive_test.dart` use.
///
/// EVERY NUMBER THIS PRINTS IS SIMULATED: a synthetic rotation bolted onto a
/// real trip's IMU magnitudes, not a real hand-held recording. Never quote
/// it as field accuracy — see the root CLAUDE.md "never quote simulated
/// results" rule and `frontend/lib/core/nav/CLAUDE.md`'s "Hand-held mode"
/// section, whose real-drive table this is deliberately styled after so the
/// two are easy to compare side by side (and not confuse with each other).
///
/// Run (from `frontend/`, matches this repo's `--no-pub` convention):
///
///   HANDHELD_SIM=1 IOVNBD_LOG_DIR=../ml/data/processed/drive_logs_vehicle \
///     C:\src\flutter\bin\flutter.bat test --no-pub test/nav/handheld_iovnbd_sim_test.dart
///
/// Optional: HANDHELD_SIM_TRIPS=<n> (default 3) picks the first n trips
/// (alphabetically) from IOVNBD_LOG_DIR; HANDHELD_SIM_SEED=<n> reseeds the
/// synthetic rotation.
///
/// Skipped (not run, not counted, not failed) unless HANDHELD_SIM=1, so this
/// file cannot affect a normal `flutter test`.
void main() {
  final enabled = Platform.environment['HANDHELD_SIM'] == '1';
  final dir = Platform.environment['IOVNBD_LOG_DIR'] ??
      '../ml/data/processed/drive_logs_vehicle';
  final maxTrips =
      int.tryParse(Platform.environment['HANDHELD_SIM_TRIPS'] ?? '') ?? 3;
  final baseSeed =
      int.tryParse(Platform.environment['HANDHELD_SIM_SEED'] ?? '') ?? 2026;

  test(
    'SIMULATED: hand-held mode on synthetically-rotated real IO-VNBD trips',
    skip: enabled ? false : 'set HANDHELD_SIM=1 to run this scratch harness',
    timeout: const Timeout(Duration(minutes: 40)),
    () async {
      final dirHandle = Directory(dir);
      expect(dirHandle.existsSync(), isTrue,
          reason: '$dir not found — set IOVNBD_LOG_DIR, or convert trips '
              'first: python ml/src/dataset/iovnbd_to_drive_log.py --imu '
              'vehicle --all --out ml/data/processed/drive_logs_vehicle');

      final files = dirHandle
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, isNotEmpty, reason: 'no .jsonl trips in $dir');

      final chosen = files.take(maxTrips).toList();
      // ignore: avoid_print
      print('SIMULATED hand-held validation — ${chosen.length} trip(s) from '
          '$dir, seed $baseSeed. Every number below is synthetic (random '
          'mount + wobble + handling bursts + noise bolted onto real '
          'IO-VNBD vehicle IMU) — not a field-drive result.\n');

      var seed = baseSeed;
      final results = <String, ({String on, String off})>{};
      for (final file in chosen) {
        seed++;
        final label = file.uri.pathSegments.last;
        final baseRecords = <DriveRecord>[];
        for (final line in file.readAsLinesSync()) {
          final r = DriveRecord.fromJsonLine(line);
          if (r != null) baseRecords.add(r);
        }
        if (baseRecords.isEmpty) {
          // ignore: avoid_print
          print('=== SIMULATED — $label: no readable records, skipped ===\n');
          continue;
        }

        final rotated = _handHeldRotate(baseRecords, seed: seed);

        final onReport = OutageBenchmark.run(
          rotated,
          engineConfig: NavConfig(features: FeatureFlags(handHeldMode: true)),
          source: 'SIMULATED $label (handHeldMode=on)',
        );
        final offReport = OutageBenchmark.run(
          rotated,
          engineConfig:
              NavConfig(features: FeatureFlags(handHeldMode: false)),
          source: 'SIMULATED $label (handHeldMode=off / mounted EKF)',
        );

        results[label] = (on: onReport.toText(), off: offReport.toText());

        // ignore: avoid_print
        print('=== SIMULATED — $label — handHeldMode=on ===');
        // ignore: avoid_print
        print(onReport.toText());
        // ignore: avoid_print
        print('=== SIMULATED — $label — handHeldMode=off (mounted EKF) ===');
        // ignore: avoid_print
        print(offReport.toText());
      }

      expect(results, isNotEmpty,
          reason: 'no trip produced a scoreable report');
    },
  );
}

/// Rewrites every `imu` record's accel/gyro as what a HAND-HELD phone would
/// have reported, given the real vehicle-frame accel/gyro in [records]:
///
///  * a random constant mount orientation (uniform random axis, random
///    angle) — "hand-held" means no fixed phone-to-vehicle transform;
///  * a slow hand-wobble: three low-frequency (0.05-0.15 Hz) sinusoids, a
///    few degrees each, one axis each;
///  * occasional "handling" bursts: 20-60 deg about a random axis, 1-3 s,
///    roughly one per 90 s of trip (smoothstep-shaped so the rate is
///    continuous — no artificial jump at the burst edges);
///  * zero-mean Gaussian vibration noise, ~0.4 rad/s gyro / ~1.2 m/s² accel
///    per axis per sample, independent of the rotation above.
///
/// The rotation quaternion `q` (phone-frame-to-vehicle-frame) is integrated
/// from exactly the wobble+burst rate via `NavMath.propagate` — the same
/// pattern `hand_held_engine_test.dart`'s `_HandHeldRig` uses — so `q` and
/// the injected gyro rate stay kinematically consistent; the vehicle's own
/// true rotation is separately carried through by rotating `gyroVehicle`
/// into the current phone frame. Noise is added last and does not feed back
/// into `q` (it is sensor noise, not real motion).
List<DriveRecord> _handHeldRotate(List<DriveRecord> records, {required int seed}) {
  final rng = math.Random(seed);

  double gauss(double std) {
    final u1 = math.max(1e-12, rng.nextDouble());
    final u2 = rng.nextDouble();
    final z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    return z * std;
  }

  Vector3 randomAxis() {
    final v = Vector3(gauss(1), gauss(1), gauss(1));
    return v.length > 1e-6 ? v.normalized() : Vector3(0, 0, 1);
  }

  // Random constant mount orientation.
  final mountAxis = randomAxis();
  final mountAngle = rng.nextDouble() * 2 * math.pi;
  final mountQ =
      NavMath.quaternionFromRotationVector(mountAxis * mountAngle);

  // Slow hand-wobble: three axes, a few degrees, low frequency.
  final wobbleAxes = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)];
  final wobbleAmpRad =
      [3.0, 5.0, 2.0].map((d) => d * NavMath.degToRad).toList();
  final wobbleFreqHz = [0.08, 0.13, 0.05];
  final wobblePhase = [for (var i = 0; i < 3; i++) rng.nextDouble() * 2 * math.pi];

  Vector3 wobbleRate(double tS) {
    var rate = Vector3.zero();
    for (var i = 0; i < 3; i++) {
      final omega = 2 * math.pi * wobbleFreqHz[i];
      final r = wobbleAmpRad[i] * omega * math.cos(omega * tS + wobblePhase[i]);
      rate = rate + wobbleAxes[i] * r;
    }
    return rate;
  }

  // Handling bursts: 20-60 deg about a random axis, 1-3 s, roughly one per
  // 90 s of trip (at least 2, capped so a very long trip doesn't get silly).
  final tripDurationS =
      (records.last.monotonicUs - records.first.monotonicUs) / 1e6;
  final burstCount = (tripDurationS / 90).round().clamp(2, 20);
  final bursts = <_Burst>[];
  for (var i = 0; i < burstCount; i++) {
    final start = rng.nextDouble() * math.max(1, tripDurationS - 5);
    final dur = 1 + rng.nextDouble() * 2;
    final angle = (20 + rng.nextDouble() * 40) * NavMath.degToRad;
    bursts.add(_Burst(
      startS: start,
      durationS: dur,
      angle: angle,
      axis: randomAxis(),
    ));
  }

  Vector3 burstRate(double tS) {
    for (final b in bursts) {
      if (tS < b.startS || tS > b.startS + b.durationS) continue;
      final u = ((tS - b.startS) / b.durationS).clamp(0.0, 1.0);
      final dSmoothstepDu = 6 * u - 6 * u * u; // d/du(3u^2 - 2u^3)
      final rate = b.angle * dSmoothstepDu / b.durationS;
      return b.axis * rate;
    }
    return Vector3.zero();
  }

  final startUs = records.first.monotonicUs;
  var q = mountQ;
  int? lastUs;
  final out = <DriveRecord>[];
  for (final r in records) {
    if (r.type != DriveRecordType.imu || r.accel == null || r.gyro == null) {
      out.add(r);
      continue;
    }
    final tS = (r.monotonicUs - startUs) / 1e6;
    final dt = lastUs == null ? 0.0 : (r.monotonicUs - lastUs) / 1e6;
    lastUs = r.monotonicUs;
    final handlingRate = wobbleRate(tS) + burstRate(tS);
    if (dt > 0 && dt < 1) {
      q = NavMath.propagate(q, handlingRate, dt);
    }

    final accelPhone = NavMath.rotateNavToBody(q, r.accel!) +
        Vector3(gauss(1.2), gauss(1.2), gauss(1.2));
    final gyroPhone = NavMath.rotateNavToBody(q, r.gyro!) +
        handlingRate +
        Vector3(gauss(0.4), gauss(0.4), gauss(0.4));

    out.add(DriveRecord.imu(
      monotonicUs: r.monotonicUs,
      accel: accelPhone,
      gyro: gyroPhone,
    ));
  }
  return out;
}

class _Burst {
  _Burst({
    required this.startS,
    required this.durationS,
    required this.angle,
    required this.axis,
  });
  final double startS;
  final double durationS;
  final double angle;
  final Vector3 axis;
}
