import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_benchmark.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_report.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_reader.dart';
import 'package:gatisaarth/core/platform/maps/pack_road_source.dart';

import '../support/fake_map_packs.dart';

/// Map matching on REAL sensors and REAL roads.
///
/// Real IO-VNBD drives around Coventry (vehicle ESP/CAN channels as an
/// external IMU, VBOX GNSS and truth) are replayed through the app's engine
/// with and without the road graph read from a real OpenStreetMap archive of
/// the same area (cut by `test/tool/extract_region_pack_test.dart`, the phone's
/// own map downloader), and scored with the outage benchmark.
///
///     IOVNBD_LOG_DIR=ml/data/processed/drive_logs_vehicle \
///     IOVNBD_PACK=ml/data/raw/osm/west-midlands.pmtiles EVIDENCE_DIR=docs/evidence \
///       flutter test test/nav/iovnbd_real_map_matching_test.dart
const _trips = [
  'M_Driver_B__M.jsonl',
  'S_Driver_A__S1__S1.jsonl',
  'S_Driver_A__S3c__S3c.jsonl',
  'S_Driver_A__S4__S4.jsonl',
  'Y_Driver_D__Y1__Y1.jsonl',
];

List<DriveRecord> _read(String path) => [
      for (final line in File(path).readAsLinesSync())
        if (DriveRecord.fromJsonLine(line) case final r?) r,
    ];

Map<String, Object> _row(DurationResult d) => {
      'n': d.n,
      'drift_median_pct': double.parse(d.engine.medianDriftPct.toStringAsFixed(2)),
      'error_median_m': double.parse(d.engine.medianM.toStringAsFixed(1)),
      'closer_than_hold': '${d.engineWins}/${d.n}',
    };

void main() {
  final logs = Platform.environment['IOVNBD_LOG_DIR'];
  final packPath = Platform.environment['IOVNBD_PACK'];
  final out = Platform.environment['EVIDENCE_DIR'];

  test('real drives, real UK roads: engine with and without the road graph',
      skip: logs == null || packPath == null
          ? 'set IOVNBD_LOG_DIR and IOVNBD_PACK'
          : false,
      timeout: const Timeout(Duration(minutes: 60)), () async {
    final file = File(packPath!);
    // The catalogue knows no UK region: describe this archive to the service.
    const westMidlands = OfflinePack(
      id: 'west-midlands',
      name: 'West Midlands',
      south: 52.33,
      west: -1.66,
      north: 52.58,
      east: -1.20,
      maxZoom: 15,
      approxBytes: 0,
    );
    final maps = OfflineMapService(
      catalog: const [westMidlands],
      locator: FakeMapPackLocator({
        'west-midlands.pmtiles': PackLocation(
          path: file.path,
          offset: 0,
          length: file.lengthSync(),
          origin: PackOrigin.sideloaded,
        ),
      }),
    );
    await maps.load();
    expect(maps.installed, isNotEmpty);

    final rows = <Map<String, Object?>>[];
    final pooled = <int, List<List<double>>>{};
    for (final name in _trips) {
      final path = '$logs/$name';
      if (!File(path).existsSync()) continue;
      final records = _read(path);

      // The road graph must cover the whole drive: centre it on the trip.
      var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
      for (final r in records) {
        if (r.type != DriveRecordType.truth) continue;
        minLat = math.min(minLat, r.latitude!);
        maxLat = math.max(maxLat, r.latitude!);
        minLon = math.min(minLon, r.longitude!);
        maxLon = math.max(maxLon, r.longitude!);
      }
      final spanKm = math.max((maxLat - minLat) * 111.3,
          (maxLon - minLon) * 111.3 * math.cos(minLat * math.pi / 180));
      final radius = math.min(24, (spanKm / 2 / 1.1).ceil() + 2);
      final source = PackRoadGraphSource(maps, tileRadius: radius);
      final coverage = await source.roadsAround(
          (minLat + maxLat) / 2, (minLon + maxLon) / 2);
      expect(coverage, isNotNull, reason: 'roads for $name');
      final graph = coverage!.graph;

      final plain = OutageBenchmark.run(records, source: name);
      final mapped = OutageBenchmark.run(records, roadGraph: graph, source: name);

      final row = <String, Object?>{
        'trip': name,
        'trip_span_km': double.parse(spanKm.toStringAsFixed(1)),
        'graph_edges': graph.edgeCount,
        'core_led_from_s': plain.coreLedFromS?.round(),
      };
      for (final seconds in const [10, 30, 60, 120]) {
        final a = plain.forDuration(seconds);
        final b = mapped.forDuration(seconds);
        if (a == null || b == null) continue;
        row['${seconds}s'] = {'without_map': _row(a), 'with_map': _row(b)};
        pooled.putIfAbsent(seconds, () => []).add([
          a.engine.medianDriftPct,
          b.engine.medianDriftPct,
        ]);
      }
      rows.add(row);
      // ignore: avoid_print
      print('$name: ${jsonEncode(row)}');
    }

    final summary = <String, Object?>{
      'what': 'REAL IO-VNBD drives around Coventry (vehicle ESP/CAN IMU proxy, '
          'VBOX GNSS/truth) through the app\'s navigation core, with and '
          'without the road graph read from a real OpenStreetMap archive of '
          'the area (West Midlands, UK), outage benchmark.',
      'trips': rows,
      for (final e in pooled.entries)
        'median_over_trips_${e.key}s': {
          'trips': e.value.length,
          'without_map_drift_pct': double.parse(
              _median([for (final v in e.value) v[0]]).toStringAsFixed(2)),
          'with_map_drift_pct': double.parse(
              _median([for (final v in e.value) v[1]]).toStringAsFixed(2)),
        },
    };
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(summary));
    if (out != null) {
      File('$out/iovnbd_real_map_matching.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(summary));
    }
  });
}

double _median(List<double> v) {
  final s = List<double>.of(v)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}
