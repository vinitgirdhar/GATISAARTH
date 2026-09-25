import 'dart:io';
import 'dart:math' as math;

import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../../platform/maps/pack_reader.dart';
import 'road_graph.dart';
import 'tile_roads.dart';

/// Builds a [RoadGraph] straight from a `.pmtiles` archive on disk, the same
/// tile decoding the phone uses (`PackRoadGraphSource`), but for a bare file
/// path instead of an [OfflineMapService]-managed pack. Used by the headless
/// benchmark (`DRIVE_MAP=`) so a drive can be map-matched off a PC without the
/// app's pack-locator plumbing.
///
/// Loads every tile at [zoom] (clamped to the archive's own max zoom) that
/// covers the box `[south, west, north, east]`. A drive's own bounding box
/// (with a small margin) is small enough that this is a handful of tiles, not
/// a scan of the whole archive.
Future<RoadGraph?> buildRoadGraphFromPmtiles(
  String path, {
  required double south,
  required double west,
  required double north,
  required double east,
  int zoom = 15,
}) async {
  final file = File(path);
  final reader = OffsetFileAt(file, length: await file.length());
  // ignore: invalid_use_of_visible_for_testing_member
  final archive = await PmTilesArchive.fromReadAt(reader);
  try {
    return await _buildFrom(archive, path,
        south: south, west: west, north: north, east: east, zoom: zoom);
  } finally {
    await archive.close();
  }
}

Future<RoadGraph?> _buildFrom(
  PmTilesArchive archive,
  String path, {
  required double south,
  required double west,
  required double north,
  required double east,
  required int zoom,
}) async {
  if (archive.header.tileType != TileType.mvt) {
    throw StateError('$path holds ${archive.header.tileType} tiles, not '
        'vector tiles');
  }
  final provider = PmTilesVectorTileProvider.fromArchive(archive);
  final z = math.min(zoom, provider.maximumZoom);

  final nw = tileOf(north, west, z);
  final se = tileOf(south, east, z);
  final limit = 1 << z;

  final lines = <TileRoadLine>[];
  for (var y = nw.y; y <= se.y; y++) {
    for (var x = nw.x; x <= se.x; x++) {
      if (x < 0 || x >= limit || y < 0 || y >= limit) continue;
      try {
        final bytes = await provider.provide(TileIdentity(z, x, y));
        lines.addAll(decodeRoadTile(bytes, z, x, y, clipToTile: true));
      } on ProviderException {
        // Tile not in the archive (outside its cut bbox, or a gap): skip it.
      }
    }
  }
  return buildRoadGraph(lines, region: path);
}
