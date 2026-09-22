import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/gnss/gnss_integrity_monitor.dart';
import 'package:gatisaarth/core/platform/gnss/gnss_telemetry.dart';

GnssTelemetrySnapshot snapshot(double cn0, {int used = 4}) =>
    GnssTelemetrySnapshot(
      permissionGranted: true,
      statusSupported: true,
      rawMeasurementsSupported: true,
      satellites: [
        for (var i = 0; i < 6; i++)
          GnssSatellite(
            svid: i + 1,
            constellation:
                i < 2 ? GnssConstellation.navic : GnssConstellation.gps,
            cn0DbHz: cn0,
            usedInFix: i < used,
            elevationDegrees: 20 + i * 8,
            azimuthDegrees: i * 55,
          ),
      ],
      recordedAt: DateTime(2026, 9, 22, 12),
    );

void main() {
  test('reports healthy receiver evidence without inventing an anomaly', () {
    final monitor = GnssIntegrityMonitor();
    monitor.add(snapshot(39));
    monitor.add(snapshot(38));

    expect(monitor.assessment.state, GnssSignalState.healthy);
    expect(monitor.assessment.meanCn0DbHz, closeTo(38, 0.01));
    expect(monitor.assessment.usedRatio, closeTo(4 / 6, 0.001));
    expect(monitor.cn0History, [39, 38]);
  });

  test('labels a rapid receiver collapse as an anomaly, never spoofing', () {
    final monitor = GnssIntegrityMonitor();
    monitor.add(snapshot(42));
    monitor.add(snapshot(41));
    monitor.add(snapshot(20, used: 1));

    expect(monitor.assessment.state, GnssSignalState.anomaly);
    expect(monitor.assessment.reason, contains('signal collapse'));
    expect(monitor.assessment.reason.toLowerCase(), isNot(contains('spoof')));
    expect(monitor.assessment.cn0ChangeDbHz, lessThan(-15));
  });

  test('missing permission is unavailable rather than degraded', () {
    final monitor = GnssIntegrityMonitor();
    monitor.add(const GnssTelemetrySnapshot(
      permissionGranted: false,
      statusSupported: true,
      rawMeasurementsSupported: false,
      satellites: [],
    ));

    expect(monitor.assessment.state, GnssSignalState.unavailable);
    expect(monitor.cn0History, isEmpty);
  });
}
