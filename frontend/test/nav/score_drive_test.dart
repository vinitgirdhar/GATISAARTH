import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/benchmark_job.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_benchmark.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_report.dart';
import 'package:gatisaarth/core/nav/map/pmtiles_road_graph.dart';
import 'package:gatisaarth/core/nav/map/road_graph.dart';
import 'package:gatisaarth/core/nav/nav_config.dart';
import 'package:gatisaarth/core/nav/replay/drive_log.dart';

/// Scores a drive recorded on any phone, headless, with the same code the app
/// runs on the phone:
///
///     DRIVE_LOG=C:\path\to\drive-2026....jsonl flutter test test/nav/score_drive_test.dart
///
/// Set NAV_AI=1 to replay with the AI path on (`AiConfig.enabled`): the `ai`
/// records in the log (model outputs a phone recorded, or a Python job
/// injected) are then used, and the report is the drive scored with them.
///
/// Set DRIVE_MAP=C:\path\to\pack.pmtiles to give the replay a road graph (the
/// same one the phone builds from an installed map pack, cut for the drive's
/// own bounding box): road-locked dead reckoning can then run. Without it the
/// replay has no roads, same as a drive with no map pack installed.
///
/// The bounding box is read straight from this log's own `gnss` fixes
/// (`benchmark_job.dart`'s `_roadGraphFor` reads `DriveRecord.latitude`,
/// which is only ever populated for a `truth` record - a real phone log has
/// none, only `gnss` ones, so that path silently built no graph at all for a
/// real drive; this test builds the graph itself and calls
/// `OutageBenchmark.run` directly instead of going through
/// `runBenchmarkJob`/`BenchmarkJob.roadMapPath` for that reason).
///
/// Set NAV_HANDHELD=1 to replay with hand-held mode on
/// (`FeatureFlags.handHeldMode`): scores the hand-held tracker
/// (`motion/hand_held_tracker.dart`) rather than the mounted EKF, which is
/// what a drive with no converged mount alignment needs to be scored at all.
///
/// Skipped when DRIVE_LOG is not set, so it never fails a normal test run.
void main() {
  final path = Platform.environment['DRIVE_LOG'];
  final ai = Platform.environment['NAV_AI'] == '1';
  final mapPath = Platform.environment['DRIVE_MAP'];
  final handHeld = Platform.environment['NAV_HANDHELD'] == '1';

  test('scores the drive named by DRIVE_LOG', () async {
    final label = [path, if (ai) 'AI on', if (handHeld) 'hand-held'].join(' ');
    final engineConfig = NavConfig(
      ai: AiConfig(enabled: ai),
      features: FeatureFlags(
          handHeldMode: handHeld,
          speedPrior: Platform.environment['NAV_SPEEDPRIOR'] == '1'),
    );

    final report = mapPath == null
        ? await runBenchmarkJob(BenchmarkJob(
            label: label,
            path: path!,
            engineConfig: engineConfig,
          ))
        : await _runWithGnssBoundedMap(path!, label, engineConfig, mapPath);
    // ignore: avoid_print
    print(report.toText());
    // ignore: avoid_print
    print(report.headline);
  }, skip: path == null ? 'set DRIVE_LOG to a .jsonl drive log' : false);
}

Future<OutageReport> _runWithGnssBoundedMap(
  String path,
  String label,
  NavConfig engineConfig,
  String mapPath,
) async {
  final lines = path.endsWith('.gz')
      ? utf8.decode(gzip.decode(File(path).readAsBytesSync())).split('\n')
      : File(path).readAsLinesSync();
  final records = <DriveRecord>[];
  for (final line in lines) {
    final record = DriveRecord.fromJsonLine(line);
    if (record != null) records.add(record);
  }
  if (records.isEmpty) {
    throw FormatException('$label has no readable drive records');
  }

  double? south, west, north, east;
  for (final r in records) {
    if (r.type != DriveRecordType.gnss) continue;
    final lat = r.fix!.latitudeDeg;
    final lon = r.fix!.longitudeDeg;
    south = south == null ? lat : math.min(south, lat);
    north = north == null ? lat : math.max(north, lat);
    west = west == null ? lon : math.min(west, lon);
    east = east == null ? lon : math.max(east, lon);
  }
  RoadGraph? graph;
  if (south != null) {
    const marginDeg = 0.01; // ~1.1 km
    graph = await buildRoadGraphFromPmtiles(
      mapPath,
      south: south - marginDeg,
      west: west! - marginDeg,
      north: north! + marginDeg,
      east: east! + marginDeg,
    );
  }

  return OutageBenchmark.run(
    records,
    engineConfig: engineConfig,
    roadGraph: graph,
    source: label,
  );
}
