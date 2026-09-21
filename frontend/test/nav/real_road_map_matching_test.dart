import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/math/nav_math.dart';
import 'package:gatisaarth/core/nav/model/nav_snapshot.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';

import '../support/real_map_packs.dart';
import 'support/drive_simulator.dart';
import 'support/route_drive.dart';

/// Live map matching and road constraints on REAL road data.
///
/// The streets are the ones in the app's own offline map archives (the same
/// OSM vector tiles that draw the map): Delhi NCR from the bundled pack, and
/// Mumbai / Pune when their archives are in `MAP_PACK_DIR`. A simulated vehicle
/// drives a route along those real streets - straight through every crossing,
/// steered like a driver - through a calibration drive, a GNSS-aided stretch
/// and a GNSS blackout, and the SAME sensor stream is fed to two engines: one
/// with the road graph, one without. The sensors are simulated (there is no
/// recorded drive on these roads), so this shows what the road constraint does
/// on real topology - parallel roads, junctions, dead ends - not field accuracy.
class _Place {
  const _Place(this.pack, this.name, this.lat, this.lon);
  final String pack;
  final String name;
  final double lat;
  final double lon;
}

const _places = [
  _Place('delhi-ncr', 'Delhi, Dwarka', 28.5921, 77.0460),
  _Place('delhi-ncr', 'Delhi, Rohini', 28.7383, 77.1132),
  _Place('delhi-ncr', 'Delhi, Vasant Kunj', 28.5195, 77.1573),
  _Place('mumbai', 'Mumbai, Andheri', 19.1136, 72.8697),
  _Place('pune', 'Pune, Kothrud', 18.5074, 73.8077),
];

// The SIH examples are a blackout of about a minute; longer ones are measured
// elsewhere (`test/nav/drift_benchmark_test.dart`, the IO-VNBD replay).
const _outageSeconds = 60;
const _aidedSeconds = 120;

class _Outcome {
  _Outcome({
    required this.routeM,
    required this.outageM,
    required this.finalErrorM,
    required this.maxErrorM,
    required this.meanOffRoadM,
    required this.meanHeadingErrorDeg,
    required this.matchedShareAided,
    required this.mapAssistedShareOutage,
    required this.imuMeanUs,
    required this.imuMaxUs,
    required this.notMatchedReasons,
  });

  final int routeM;
  final double outageM;
  final double finalErrorM;
  final double maxErrorM;

  /// How far the estimate sat from the nearest real road, on average, during
  /// the blackout (cross-track), and its mean heading error against the truth.
  final double meanOffRoadM;
  final double meanHeadingErrorDeg;
  final double matchedShareAided;
  final double mapAssistedShareOutage;
  final double imuMeanUs;
  final int imuMaxUs;

  /// Why the matcher declined to snap while GNSS was available, most common
  /// first (the number is a percentage of those samples).
  final Map<String, int> notMatchedReasons;

  double get driftPercent => outageM <= 0 ? 0 : 100 * finalErrorM / outageM;

  Map<String, Object> toJson() => {
        'route_m': routeM,
        'outage_distance_m': double.parse(outageM.toStringAsFixed(1)),
        'final_error_m': double.parse(finalErrorM.toStringAsFixed(1)),
        'max_error_m': double.parse(maxErrorM.toStringAsFixed(1)),
        'mean_distance_to_nearest_road_m':
            double.parse(meanOffRoadM.toStringAsFixed(1)),
        'mean_heading_error_deg':
            double.parse(meanHeadingErrorDeg.toStringAsFixed(1)),
        'drift_percent': double.parse(driftPercent.toStringAsFixed(2)),
        'matched_share_gnss_aided':
            double.parse(matchedShareAided.toStringAsFixed(3)),
        'map_assisted_share_outage':
            double.parse(mapAssistedShareOutage.toStringAsFixed(3)),
        'imu_frame_mean_us': double.parse(imuMeanUs.toStringAsFixed(1)),
        'imu_frame_max_us': imuMaxUs,
        'not_matched_reasons_percent': notMatchedReasons,
      };
}

Map<String, int> _topReasons(Map<String, int> counts, int total) {
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {
    for (final e in sorted.take(4))
      e.key: total == 0 ? 0 : (100 * e.value / total).round(),
  };
}

_Outcome _drive(RoadGraph graph, List<RoutePoint> route,
    {required bool withMap}) {
  final engine = NavigationEngine(roadGraph: withMap ? graph : null);
  final sim = DriveSimulator(
    mount: PhoneMount.tilted(),
    startLat: route.first.lat,
    startLon: route.first.lon,
    startHeadingRad: route.first.bearingDeg * NavMath.degToRad,
    seed: 11,
  );
  final pursuit = RoutePursuit(route);
  var nextGnssUs = 0;
  var frames = 0;
  var micros = 0;
  var maxMicros = 0;

  var aidedSamples = 0;
  var matchedSamples = 0;
  final reasons = <String, int>{};
  var outageSamples = 0;
  var assistedSamples = 0;
  var outageStartDistance = 0.0;
  var finalError = 0.0;
  var maxError = 0.0;
  var offRoadSum = 0.0;
  var headingErrSum = 0.0;

  void step(DriveSegment segment, {required bool gnss, required bool outage}) {
    final frame = sim.step(segment);
    final watch = Stopwatch()..start();
    final snapshot = engine.onImu(
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
    watch.stop();
    frames++;
    micros += watch.elapsedMicroseconds;
    maxMicros = math.max(maxMicros, watch.elapsedMicroseconds);
    if (snapshot == null || snapshot.latitude == null) return;
    if (outage) {
      outageSamples++;
      if (snapshot.mode == NavMode.mapAssistedDeadReckoning) assistedSamples++;
      final error = NavMath.horizontalDistance(
        lat0: snapshot.latitude!,
        lon0: snapshot.longitude!,
        lat1: frame.truth.latitude,
        lon1: frame.truth.longitude,
      );
      finalError = error;
      maxError = math.max(maxError, error);
      final near = graph.nearby(snapshot.latitude!, snapshot.longitude!,
          radiusM: 300, limit: 1);
      offRoadSum += near.isEmpty ? 300 : near.first.perpendicularM;
      final heading = snapshot.headingDeg;
      if (heading != null) {
        headingErrSum += NavMath.angleDiffDeg(
                heading, frame.truth.headingRad * NavMath.radToDeg)
            .abs();
      }
    } else if (gnss) {
      aidedSamples++;
      final match = snapshot.mapMatchResult;
      if (match?.snapped ?? false) {
        matchedSamples++;
      } else if (withMap) {
        // Numbers in the message vary; keep the sentence.
        final why = (match?.reason ?? 'no result')
            .replaceAll(RegExp(r'[0-9]+'), 'N');
        reasons[why] = (reasons[why] ?? 0) + 1;
      }
    }
  }

  // 1. Calibration on the straight start of the route (GNSS on).
  for (final segment in calibrationDrive()) {
    for (var i = 0; i < segment.seconds * sim.imuHz; i++) {
      step(segment, gnss: true, outage: false);
    }
  }
  // 2. Along the streets with GNSS.
  for (var i = 0; i < _aidedSeconds * sim.imuHz; i++) {
    step(pursuit.next(sim.truth, targetSpeed: 10),
        gnss: true, outage: false);
  }
  // 3. GNSS blackout.
  outageStartDistance = sim.truth.distanceM;
  for (var i = 0; i < _outageSeconds * sim.imuHz; i++) {
    step(pursuit.next(sim.truth, targetSpeed: 10),
        gnss: false, outage: true);
  }

  return _Outcome(
    routeM: route.length,
    outageM: sim.truth.distanceM - outageStartDistance,
    finalErrorM: finalError,
    maxErrorM: maxError,
    meanOffRoadM: outageSamples == 0 ? 0 : offRoadSum / outageSamples,
    meanHeadingErrorDeg: outageSamples == 0 ? 0 : headingErrSum / outageSamples,
    matchedShareAided: aidedSamples == 0 ? 0 : matchedSamples / aidedSamples,
    mapAssistedShareOutage:
        outageSamples == 0 ? 0 : assistedSamples / outageSamples,
    imuMeanUs: frames == 0 ? 0 : micros / frames,
    imuMaxUs: maxMicros,
    notMatchedReasons: _topReasons(reasons, aidedSamples),
  );
}

void main() {
  final evidence = <String, Object>{};

  tearDownAll(() {
    final dir = Platform.environment['EVIDENCE_DIR'];
    if (dir == null || evidence.isEmpty) return;
    File('$dir/real_road_map_matching.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'what': 'Simulated sensors on real OSM streets read from the app\'s '
            'offline map archives; engine with vs without the road graph, '
            'same sensor stream. Not field accuracy.',
        'places': evidence,
      }),
    );
  });

  for (final place in _places) {
    test('${place.name}: matching on real streets, with and without the map',
        skip: skipUnlessPack(place.pack),
        timeout: const Timeout(Duration(minutes: 5)), () async {
      final source = (await openRealRoadSource(place.pack))!;
      final coverage = await source.roadsAround(place.lat, place.lon);
      expect(coverage, isNotNull, reason: 'roads read from the archive');
      final graph = coverage!.graph;
      final route = straightThenOnRoute(graph);
      if (route == null) {
        markTestSkipped('no straight road to calibrate on near ${place.name}');
        return;
      }

      final plain = _drive(graph, route, withMap: false);
      final mapped = _drive(graph, route, withMap: true);

      printOnFailure('${place.name}: without map ${plain.toJson()}');
      printOnFailure('${place.name}: with map    ${mapped.toJson()}');
      evidence[place.name] = {
        'graph_edges': graph.edgeCount,
        'without_map': plain.toJson(),
        'with_map': mapped.toJson(),
      };

      // The road graph reaches the matcher and matches the real street.
      expect(mapped.matchedShareAided, greaterThan(0.5),
          reason: 'GNSS-aided samples matched to a real street');
      expect(plain.matchedShareAided, 0);
      // The road graph must not make the blackout worse: same sensor stream,
      // same drive. (Along-track drift here is dominated by the simulated
      // accelerometer bias and is measured properly by the IO-VNBD replay; the
      // map's job is cross-track and heading.)
      expect(mapped.meanOffRoadM, lessThanOrEqualTo(plain.meanOffRoadM * 1.3 + 3),
          reason: 'estimate no farther from real roads than without the map');
      expect(mapped.meanHeadingErrorDeg,
          lessThanOrEqualTo(plain.meanHeadingErrorDeg * 1.3 + 2),
          reason: 'heading no worse than without the map');
      // Matching runs inside the sensor loop: it must stay cheap per frame.
      expect(mapped.imuMeanUs, lessThan(2000),
          reason: 'microseconds per sensor frame with matching on');
    });
  }
}
