import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' show LatLng;

/// One offline map archive (a PMTiles file of OpenStreetMap vector tiles).
///
/// The phone cuts each archive out of the newest Protomaps OpenStreetMap build
/// itself (`PackInstaller`); Delhi NCR additionally ships inside the APK.
/// `tools/offline_maps/build_offline_maps.py` cuts the same areas on a PC and
/// is the only place the bounding boxes below are defined a second time - keep
/// the two in step (`test/offline_catalog_test.dart` checks it).
@immutable
class OfflinePack {
  const OfflinePack({
    required this.id,
    required this.name,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.maxZoom,
    required this.approxBytes,
    this.detail = false,
  });

  /// Also the file name stem: `<id>.pmtiles`.
  final String id;
  final String name;

  final double south;
  final double west;
  final double north;
  final double east;

  /// Highest zoom stored in the archive; the map draws sharper than this by
  /// scaling the vector data, it does not become more detailed.
  final int maxZoom;

  /// Size of the file as shipped. The installed file's real size wins.
  final int approxBytes;

  /// A city-detail archive that sits on top of a statewide overview and is only
  /// worth drawing when zoomed in (the overview has no data past its own
  /// [maxZoom]).
  final bool detail;

  String get fileName => '$id.pmtiles';

  bool contains(LatLng p) =>
      p.latitude >= south &&
      p.latitude <= north &&
      p.longitude >= west &&
      p.longitude <= east;

  /// Whether the archive overlaps the given viewport.
  bool intersects({
    required double south,
    required double west,
    required double north,
    required double east,
  }) =>
      this.south <= north &&
      this.north >= south &&
      this.west <= east &&
      this.east >= west;

  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);
}

/// A named place on the Offline Maps screen: one or more packs.
@immutable
class OfflineRegion {
  const OfflineRegion({
    required this.id,
    required this.name,
    required this.summary,
    required this.packs,
  });

  final String id;
  final String name;
  final String summary;
  final List<OfflinePack> packs;

  int get approxBytes => packs.fold(0, (sum, p) => sum + p.approxBytes);

  double get south => packs.map((p) => p.south).reduce((a, b) => a < b ? a : b);
  double get west => packs.map((p) => p.west).reduce((a, b) => a < b ? a : b);
  double get north => packs.map((p) => p.north).reduce((a, b) => a > b ? a : b);
  double get east => packs.map((p) => p.east).reduce((a, b) => a > b ? a : b);

  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);

  /// Where to fly the map to show this region: its first pack's centre (the
  /// main city for a region that has several).
  LatLng get focus => packs.firstWhere((p) => !p.detail, orElse: () => packs.first).center;
}

/// The regions the app ships with.
class OfflineCatalog {
  const OfflineCatalog._();

  /// Date of the Protomaps build the bundled archives were cut from.
  static const String dataBuild = '2026-09-20';

  /// Where the Protomaps builds are listed, and where each one is served. The
  /// app cuts a region out of the newest build with range requests, so nothing
  /// larger than the region itself is ever downloaded.
  static const String buildsIndexUrl =
      'https://build-metadata.protomaps.dev/builds.json';

  static String buildUrl(String build) =>
      'https://build.protomaps.com/$build.pmtiles';

  /// "OpenStreetMap contributors" is a licence requirement (ODbL); Protomaps
  /// asks for its name next to it.
  static const String attribution = '© OpenStreetMap contributors · Protomaps';

  static const OfflinePack delhiNcr = OfflinePack(
    id: 'delhi-ncr',
    name: 'Delhi NCR',
    south: 28.38,
    west: 76.83,
    north: 28.90,
    east: 77.45,
    maxZoom: 15,
    approxBytes: 36834779,
  );

  static const OfflinePack maharashtraState = OfflinePack(
    id: 'maharashtra-state',
    name: 'Maharashtra statewide',
    south: 15.60,
    west: 72.60,
    north: 22.10,
    east: 80.90,
    maxZoom: 12,
    approxBytes: 78940173,
  );

  static const OfflinePack mumbai = OfflinePack(
    id: 'mumbai',
    name: 'Mumbai, Thane & Navi Mumbai',
    south: 18.85,
    west: 72.72,
    north: 19.45,
    east: 73.30,
    maxZoom: 15,
    approxBytes: 25655850,
    detail: true,
  );

  static const OfflinePack pune = OfflinePack(
    id: 'pune',
    name: 'Pune & Pimpri-Chinchwad',
    south: 18.35,
    west: 73.65,
    north: 18.70,
    east: 74.05,
    maxZoom: 15,
    approxBytes: 17347753,
    detail: true,
  );

  static const OfflinePack nagpur = OfflinePack(
    id: 'nagpur',
    name: 'Nagpur',
    south: 20.98,
    west: 78.95,
    north: 21.28,
    east: 79.25,
    maxZoom: 15,
    approxBytes: 5452389,
    detail: true,
  );

  static const OfflinePack nashik = OfflinePack(
    id: 'nashik',
    name: 'Nashik',
    south: 19.90,
    west: 73.68,
    north: 20.08,
    east: 73.92,
    maxZoom: 15,
    approxBytes: 4013194,
    detail: true,
  );

  static const OfflinePack sambhajinagar = OfflinePack(
    id: 'sambhajinagar',
    name: 'Chhatrapati Sambhajinagar',
    south: 19.78,
    west: 75.22,
    north: 19.95,
    east: 75.42,
    maxZoom: 15,
    approxBytes: 2955647,
    detail: true,
  );

  static const OfflineRegion delhi = OfflineRegion(
    id: 'delhi',
    name: 'Delhi NCR',
    summary: 'Delhi with Gurugram, Noida, Faridabad and parts of Ghaziabad. '
        'Every street, to zoom 15.',
    packs: [delhiNcr],
  );

  static const OfflineRegion maharashtra = OfflineRegion(
    id: 'maharashtra',
    name: 'Maharashtra',
    summary: 'Roads, towns and coast across the whole state, plus every street '
        'in Mumbai, Pune, Nagpur, Nashik and Chhatrapati Sambhajinagar.',
    packs: [maharashtraState, mumbai, pune, nagpur, nashik, sambhajinagar],
  );

  static const List<OfflineRegion> regions = [delhi, maharashtra];

  static List<OfflinePack> get packs =>
      [for (final region in regions) ...region.packs];

  /// Every pack whose box contains [point].
  static List<OfflinePack> packsAt(LatLng point) =>
      [for (final pack in packs) if (pack.contains(point)) pack];
}
