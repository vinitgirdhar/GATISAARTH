import 'dart:io';

import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_reader.dart';
import 'package:gatisaarth/core/platform/maps/pack_road_source.dart';

import 'fake_map_packs.dart';

/// A real offline map archive on this machine, or null.
///
/// Delhi NCR ships with the app (`assets/maps/packs/`, git-ignored, so a
/// checkout without it skips the real-map tests). Any other archive is read
/// from the folder in `MAP_PACK_DIR` - `adb pull` a phone's
/// `files/offline_maps/*.pmtiles` there - so the same tests run for Mumbai,
/// Pune or anywhere else the app has maps.
File? realPackFile(String id) {
  final dirs = [
    'assets/maps/packs',
    if (Platform.environment['MAP_PACK_DIR'] != null)
      Platform.environment['MAP_PACK_DIR']!,
  ];
  for (final dir in dirs) {
    final file = File('$dir/$id.pmtiles');
    if (file.existsSync()) return file;
  }
  return null;
}

/// Why a real-map test is skipped, or null when its archive is present.
String? skipUnlessPack(String id) =>
    realPackFile(id) == null ? '$id.pmtiles not on this machine' : null;

final Map<String, PackRoadGraphSource> _sources = {};

/// The road source backed by the real archive [id], or null when absent.
/// One source per archive per test run: its tile cache is what makes the
/// second place in the same city cheap.
Future<PackRoadGraphSource?> openRealRoadSource(String id) async {
  final cached = _sources[id];
  if (cached != null) return cached;
  final file = realPackFile(id);
  if (file == null) return null;
  final maps = OfflineMapService(
    locator: FakeMapPackLocator({
      '$id.pmtiles': PackLocation(
        path: file.path,
        offset: 0,
        length: file.lengthSync(),
        origin: PackOrigin.sideloaded,
      ),
    }),
  );
  await maps.load();
  return _sources[id] = PackRoadGraphSource(maps);
}
