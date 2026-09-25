import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/pmtiles_road_graph.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

/// Checks the Mumbai pack actually map-matches the team's real field drives:
/// builds a RoadGraph from a `.pmtiles` archive and reports what fraction of
/// each drive's GNSS fixes land within 20 m of a road edge. Prints only -
/// drive-derived data (the field_drives/*.jsonl.gz logs) is git-ignored and
/// never written into the repo.
///
///     FIELD_DRIVES_DIR=field_drives DRIVE_MAP=frontend/assets/maps/packs/mumbai.pmtiles \
///         flutter test test/nav/field_drive_map_match_test.dart
///
/// Skipped when FIELD_DRIVES_DIR or DRIVE_MAP is not set.
void main() {
  final drivesDir = Platform.environment['FIELD_DRIVES_DIR'];
  final mapPath = Platform.environment['DRIVE_MAP'];
  const matchRadiusM = 20.0;

  test('the Mumbai road graph matches fixes on real field drives', () async {
    final files = Directory(drivesDir!)
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.jsonl') || f.path.endsWith('.jsonl.gz'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);

    for (final file in files) {
      final lines = file.path.endsWith('.gz')
          ? utf8.decode(gzip.decode(file.readAsBytesSync())).split('\n')
          : file.readAsLinesSync();
      final fixes = <(double, double)>[];
      double? south, west, north, east;
      for (final line in lines) {
        final record = DriveRecord.fromJsonLine(line);
        if (record?.type != DriveRecordType.gnss) continue;
        final lat = record!.fix?.latitudeDeg, lon = record.fix?.longitudeDeg;
        if (lat == null || lon == null) continue;
        fixes.add((lat, lon));
        south = south == null ? lat : (lat < south ? lat : south);
        north = north == null ? lat : (lat > north ? lat : north);
        west = west == null ? lon : (lon < west ? lon : west);
        east = east == null ? lon : (lon > east ? lon : east);
      }
      if (fixes.isEmpty || south == null) {
        // ignore: avoid_print
        print('${file.path}: no GNSS fixes readable');
        continue;
      }

      const marginDeg = 0.01;
      final graph = await buildRoadGraphFromPmtiles(
        mapPath!,
        south: south - marginDeg,
        west: west! - marginDeg,
        north: north! + marginDeg,
        east: east! + marginDeg,
      );
      if (graph == null || graph.isEmpty) {
        // ignore: avoid_print
        print('${file.path}: no road graph over this drive\'s box');
        continue;
      }

      var matched = 0;
      for (final (lat, lon) in fixes) {
        if (graph.nearby(lat, lon, radiusM: matchRadiusM).isNotEmpty) matched++;
      }
      final pct = 100 * matched / fixes.length;
      // ignore: avoid_print
      print('${file.path}: ${fixes.length} fixes, $matched within '
          '${matchRadiusM}m of a road (${pct.toStringAsFixed(1)}%), '
          '${graph.edgeCount} edges loaded');
      expect(matched, greaterThan(0),
          reason: 'the Mumbai pack should match at least some fixes on a '
              'real Mumbai drive');
    }
  },
      skip: drivesDir == null
          ? 'set FIELD_DRIVES_DIR to a folder of drive logs'
          : mapPath == null
              ? 'set DRIVE_MAP to a .pmtiles archive'
              : false);
}
