import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';
import 'package:gatisaarth/core/nav/replay/drive_recorder.dart';
import 'package:gatisaarth/core/nav/replay/replay_engine.dart';
import 'package:gatisaarth/core/platform/gnss/gnss_telemetry.dart';

void main() {
  const snapshot = GnssTelemetrySnapshot(
    permissionGranted: true,
    statusSupported: true,
    rawMeasurementsSupported: true,
    satellites: [
      GnssSatellite(
        svid: 3,
        constellation: GnssConstellation.navic,
        cn0DbHz: 42.25,
        usedInFix: true,
        carrierFrequencyHz: 1176.45e6,
      ),
      GnssSatellite(
        svid: 21,
        constellation: GnssConstellation.gps,
        cn0DbHz: 31,
        usedInFix: false,
      ),
    ],
  );

  test('drive log preserves receiver evidence for later field analysis', () {
    final sink = MemoryLogSink();
    final recorder = DriveRecorder(sink: sink.call);
    recorder.start(const DriveMeta(sessionId: 'field-1', startedAtMs: 1));
    recorder.recordGnssReceiver(monotonicUs: 1000000, snapshot: snapshot);

    final record = DriveRecord.fromJsonLine(sink.lines.last)!;
    expect(record.type, DriveRecordType.gnssReceiver);
    expect(record.receiver!['raw'], isTrue);
    expect(record.receiver!['used'], 1);
    final satellites = record.receiver!['sv'] as List<dynamic>;
    expect(satellites, hasLength(2));
    expect(satellites.first, [7, 3, 42.25, true, 1176450000.0]);
  });

  test('receiver evidence is diagnostic and does not alter replayed position',
      () {
    final record = DriveRecord.gnssReceiver(
      monotonicUs: 1000000,
      snapshot: snapshot,
    );
    final replay = ReplayEngine(records: [record]);

    final summary = replay.runToEnd();
    expect(summary.records, 1);
    expect(summary.finalSnapshot, isNull);
  });
}
