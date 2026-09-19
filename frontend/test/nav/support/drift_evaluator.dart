import 'dart:math' as math;

import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/model/nav_snapshot.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';

import 'drive_simulator.dart';

/// Ground-truth scoring for one GNSS outage (§39).
///
/// Every number here is measured against the simulator's own truth. That makes
/// it a bound on the *engine*, under modelled sensor error — it is not a field
/// measurement and must never be quoted as one (§83).
class OutageScore {
  OutageScore({
    required this.outageSeconds,
    required this.distanceM,
    required this.finalErrorM,
    required this.maxErrorM,
    required this.meanErrorM,
    required this.p95ErrorM,
    required this.finalHeadingErrorDeg,
    required this.finalSpeedErrorMps,
    required this.finalSigmaM,
    required this.mode,
  });

  final double outageSeconds;

  /// Ground truth distance travelled during the outage.
  final double distanceM;

  final double finalErrorM;
  final double maxErrorM;
  final double meanErrorM;
  final double p95ErrorM;
  final double finalHeadingErrorDeg;
  final double finalSpeedErrorMps;

  /// What the filter itself claimed its uncertainty was at the end.
  final double finalSigmaM;

  final NavMode mode;

  /// The §76 headline: position error as a percentage of distance travelled.
  double get driftPercent =>
      distanceM <= 0 ? double.nan : 100 * finalErrorM / distanceM;

  /// True when the filter's own uncertainty covered the error it actually
  /// had. An estimate that is wrong but *knows* it is wrong is still usable;
  /// one that is wrong and confident is not (§28).
  bool get uncertaintyCoveredError => finalSigmaM * 3 >= finalErrorM;

  String get row => '${outageSeconds.toStringAsFixed(0).padLeft(5)}s '
      '${distanceM.toStringAsFixed(0).padLeft(7)}m '
      '${finalErrorM.toStringAsFixed(1).padLeft(8)}m '
      '${driftPercent.toStringAsFixed(2).padLeft(7)}% '
      '${maxErrorM.toStringAsFixed(1).padLeft(8)}m '
      '${p95ErrorM.toStringAsFixed(1).padLeft(8)}m '
      '${finalHeadingErrorDeg.toStringAsFixed(1).padLeft(7)}deg '
      '${finalSpeedErrorMps.toStringAsFixed(2).padLeft(7)}m/s '
      '${finalSigmaM.toStringAsFixed(0).padLeft(6)}m '
      '${uncertaintyCoveredError ? 'covered' : 'OPTIMISTIC'}';

  static const String header = ' outage    dist    error   drift%      max  '
      '     p95     hdg    speed  sigma  3-sigma';
}

/// Runs a calibration drive, then a GNSS outage, and scores it.
class DriftEvaluator {
  DriftEvaluator({
    required this.mount,
    this.seed = 42,
    this.accelBias = const [0.08, -0.05, 0.06],
    this.gyroBias = const [0.002, -0.001, 0.004],
  });

  final PhoneMount mount;
  final int seed;
  final List<double> accelBias;
  final List<double> gyroBias;

  /// Drives [segments] with GNSS live, then repeats [outageProfile] until
  /// [outageSeconds] have passed with GNSS gone.
  OutageScore evaluate({
    required double outageSeconds,
    List<DriveSegment>? outageProfile,
    List<DriveSegment>? warmUp,
  }) {
    final engine = NavigationEngine();
    final sim = DriveSimulator(
      mount: mount,
      seed: seed,
      accelBias: accelBias,
      gyroBias: gyroBias,
    );

    var nextGnssUs = 0;
    void drive(List<DriveSegment> segments, {required bool gnss}) {
      for (final segment in segments) {
        final steps = (segment.seconds * sim.imuHz).round();
        for (var i = 0; i < steps; i++) {
          final frame = sim.step(segment);
          engine.onImu(
            accelPhone: frame.accelPhone,
            gyroPhone: frame.gyroPhone,
            monotonicUs: frame.truth.monotonicUs,
          );
          if (frame.truth.monotonicUs >= nextGnssUs) {
            nextGnssUs = frame.truth.monotonicUs + 1000000;
            if (gnss) {
              engine.onGnss(sim.gnss());
            } else {
              engine.onGnssLost(frame.truth.monotonicUs);
            }
          }
          if (!gnss) _sampleError(engine, sim);
        }
      }
    }

    drive(calibrationDrive(), gnss: true);
    drive(
      warmUp ??
          const [
            DriveSegment(seconds: 10, longitudinalAccel: 1.5),
            DriveSegment(seconds: 5),
          ],
      gnss: true,
    );

    final distanceAtLoss = sim.truth.distanceM;
    _errors.clear();

    // Repeat the profile until the requested outage length is covered.
    final profile = outageProfile ?? _defaultOutageProfile;
    final profileSeconds =
        profile.fold<double>(0, (sum, s) => sum + s.seconds);
    final repeats = math.max(1, (outageSeconds / profileSeconds).ceil());
    for (var i = 0; i < repeats; i++) {
      drive(profile, gnss: false);
    }

    final snapshot = engine.snapshot!;
    final truth = sim.truth;
    final finalError = _errorNow(engine, sim) ?? double.nan;
    final sorted = List<double>.from(_errors)..sort();

    return OutageScore(
      outageSeconds: repeats * profileSeconds,
      distanceM: truth.distanceM - distanceAtLoss,
      finalErrorM: finalError,
      maxErrorM: sorted.isEmpty ? double.nan : sorted.last,
      meanErrorM: sorted.isEmpty
          ? double.nan
          : sorted.reduce((a, b) => a + b) / sorted.length,
      p95ErrorM: sorted.isEmpty
          ? double.nan
          : sorted[math.min(sorted.length - 1, (sorted.length * 0.95).floor())],
      finalHeadingErrorDeg: snapshot.headingDeg == null
          ? double.nan
          : NavMath.angleDiffDeg(
              snapshot.headingDeg!,
              NavMath.wrap360(truth.headingRad * NavMath.radToDeg),
            ).abs(),
      finalSpeedErrorMps: snapshot.speedMps == null
          ? double.nan
          : (snapshot.speedMps! - truth.speedMps).abs(),
      finalSigmaM: snapshot.horizontalSigmaM ?? double.nan,
      mode: snapshot.mode,
    );
  }

  final List<double> _errors = [];

  void _sampleError(NavigationEngine engine, DriveSimulator sim) {
    final e = _errorNow(engine, sim);
    if (e != null) _errors.add(e);
  }

  double? _errorNow(NavigationEngine engine, DriveSimulator sim) {
    final s = engine.snapshot;
    if (s == null || !s.hasPosition) return null;
    return NavMath.horizontalDistance(
      lat0: sim.truth.latitude,
      lon0: sim.truth.longitude,
      lat1: s.latitude!,
      lon1: s.longitude!,
    );
  }

  /// 30 s of ordinary driving: cruise, a bend, cruise, a stop, pull away.
  static const List<DriveSegment> _defaultOutageProfile = [
    DriveSegment(seconds: 8),
    DriveSegment(seconds: 4, yawRate: 0.12),
    DriveSegment(seconds: 6),
    DriveSegment(seconds: 4, longitudinalAccel: -2.5),
    DriveSegment(seconds: 4),
    DriveSegment(seconds: 4, longitudinalAccel: 2.5),
  ];
}
