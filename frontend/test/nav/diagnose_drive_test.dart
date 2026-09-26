import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/navigation_engine.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

/// Per-second trace of a real drive through the core, for debugging:
///
///     DRIVE_LOG=path.jsonl.gz [OUTAGE_AT=200] flutter test test/nav/diagnose_drive_test.dart
///
/// Prints, at every GNSS fix, the core's speed/heading next to the fix's
/// speed and course, plus alignment, integrity and bias states; then replays
/// one 15 s outage from OUTAGE_AT seconds and prints the drift second by
/// second. Skipped without DRIVE_LOG.
void main() {
  final path = Platform.environment['DRIVE_LOG'];
  final outageAtS = double.tryParse(Platform.environment['OUTAGE_AT'] ?? '');

  test('diagnose', () {
    final lines = path!.endsWith('.gz')
        ? utf8.decode(gzip.decode(File(path).readAsBytesSync())).split('\n')
        : File(path).readAsLinesSync();
    final records = [
      for (final l in lines)
        if (l.trim().isNotEmpty) DriveRecord.fromJsonLine(l),
    ].whereType<DriveRecord>().toList();
    final t0 = records.firstWhere((r) => r.type == DriveRecordType.imu).monotonicUs;
    final noMag = Platform.environment['NAV_NOMAG'] == '1';
    final engine = NavigationEngine(
        config: NavConfig(
            features: FeatureFlags(magnetometerHeading: !noMag)));
    double? lastLat, lastLon;
    int? outageStartUs;
    double? oLat, oLon;
    final outageUs =
        outageAtS == null ? null : t0 + (outageAtS * 1e6).round();
    var nextPrint = 0.0;

    String f(double? v, [int d = 1]) => v == null ? '--' : v.toStringAsFixed(d);
    double dist(double la1, double lo1, double la2, double lo2) {
      const r = 6371000.0;
      final dl = (la2 - la1) * math.pi / 180;
      final dn = (lo2 - lo1) * math.pi / 180 * math.cos(la1 * math.pi / 180);
      return r * math.sqrt(dl * dl + dn * dn);
    }

    // ignore: avoid_print
    print(' t(s) lead integ  conf  yawOff  coreSpd gnssSpd  coreHdg gnssCrs  sigma  vUp   ba(x,y,z)            bg(z)deg/s');
    for (final r in records) {
      final tS = (r.monotonicUs - t0) / 1e6;
      switch (r.type) {
        case DriveRecordType.imu:
          engine.onImu(
            accelPhone: r.accel!,
            gyroPhone: r.gyro!,
            monotonicUs: r.monotonicUs,
            magPhone: r.mag,
            pressureHpa: r.pressureHpa,
            temperatureC: r.temperatureC,
          );
        case DriveRecordType.gnss:
          final fix = r.fix!;
          final inOutage = outageUs != null &&
              r.monotonicUs >= outageUs &&
              r.monotonicUs < outageUs + 15000000;
          double? course;
          if (lastLat != null) {
            final dn = (fix.latitudeDeg - lastLat) * 111000;
            final de = (fix.longitudeDeg - lastLon!) *
                111000 *
                math.cos(fix.latitudeDeg * math.pi / 180);
            if (math.sqrt(dn * dn + de * de) > 2) {
              course = (math.atan2(de, dn) * 180 / math.pi + 360) % 360;
            }
          }
          lastLat = fix.latitudeDeg;
          lastLon = fix.longitudeDeg;
          if (inOutage) {
            outageStartUs ??= r.monotonicUs;
            if (oLat == null) {
              oLat = fix.latitudeDeg;
              oLon = fix.longitudeDeg;
            }
            engine.onGnssLost(r.monotonicUs);
            final s = engine.snapshot;
            final err = s?.latitude == null
                ? null
                : dist(s!.latitude!, s.longitude!, fix.latitudeDeg, fix.longitudeDeg);
            // ignore: avoid_print
            print('OUT ${f(tS, 0).padLeft(4)} +${f((r.monotonicUs - outageStartUs!) / 1e6, 0)}s '
                'err ${f(err)} m  coreSpd ${f(s?.speedMps)} gnssSpd ${f(fix.speedMps)} '
                'coreHdg ${f(s?.headingDeg, 0)} gnssCrs ${f(course, 0)} sigma ${f(s?.horizontalSigmaM)} '
                'lead ${s?.canLeadPosition}');
            continue;
          }
          engine.onGnss(fix);
          final win = Platform.environment['REJECT_WIN'];
          if (win != null) {
            final p = win.split('-').map(double.parse).toList();
            if (tS >= p[0] && tS <= p[1]) {
              final s = engine.snapshot;
              // ignore: avoid_print
              print('RJ ${f(tS, 0)} reason ${s?.gnss?.reason.name} acc ${f(fix.accuracyM)} '
                  'gnssSpd ${f(fix.speedMps)} coreSpd ${f(s?.speedMps)} lead ${s?.canLeadPosition} integ ${s?.integrity.name}');
            }
          }
          if (tS < nextPrint) continue;
          nextPrint = tS + 5;
          final s = engine.snapshot;
          final st = engine.filter.state;
          final a = engine.alignment;
          // ignore: avoid_print
          print('${f(tS, 0).padLeft(5)} ${(s?.canLeadPosition ?? false) ? 'Y' : 'n'}    '
              '${s?.integrity.name.padRight(6)} ${f(s?.alignmentConfidence, 2)}  '
              '${f(a == null ? null : a.yawOffsetRad * 180 / math.pi, 0).padLeft(5)}  '
              '${f(s?.speedMps).padLeft(6)} ${f(fix.speedMps).padLeft(6)}  '
              '${f(s?.headingDeg, 0).padLeft(6)} ${f(course, 0).padLeft(6)}  '
              '${f(s?.horizontalSigmaM).padLeft(5)} ${f(st == null ? null : -st.velocityNed.z).padLeft(5)}  '
              '${st == null ? '--' : '${f(st.accelBias.x, 2)},${f(st.accelBias.y, 2)},${f(st.accelBias.z, 2)}'}  '
              '${st == null ? '--' : f(st.gyroBias.z * 180 / math.pi, 2)}');
        case DriveRecordType.gnssLost:
          engine.onGnssLost(r.monotonicUs);
        default:
          break;
      }
    }
    for (final t in engine.transitions) {
      // ignore: avoid_print
      print('TR ${f((t.monotonicUs - t0) / 1e6, 0)} ${t.from.name}->${t.to.name}: ${t.reason}');
    }
  }, skip: path == null ? 'set DRIVE_LOG' : false);
}
