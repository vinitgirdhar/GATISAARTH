import 'dart:typed_data';

import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_reader.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// A tile source with no data, so a map can be drawn without a real archive.
class EmptyTileProvider extends VectorTileProvider {
  EmptyTileProvider({this.maxZoom = 15});

  final int maxZoom;

  @override
  int get maximumZoom => maxZoom;

  @override
  int get minimumZoom => 0;

  /// An empty protobuf message is a valid, empty tile.
  @override
  Future<Uint8List> provide(TileIdentity tile) async => Uint8List(0);
}

/// Knows a fixed set of archives by file name.
class FakeMapPackLocator implements MapPackLocator {
  FakeMapPackLocator(this.found);

  final Map<String, PackLocation> found;

  @override
  Future<PackLocation?> locate(String fileName) async => found[fileName];
}

PackLocation fakeLocation(int length,
        {PackOrigin origin = PackOrigin.bundled}) =>
    PackLocation(path: '/fake.apk', offset: 0, length: length, origin: origin);

/// A service that says every archive in the catalogue is installed.
Future<OfflineMapService> allPacksInstalled() async {
  final service = OfflineMapService(
    locator: FakeMapPackLocator({
      for (final p in OfflineCatalog.packs)
        p.fileName: fakeLocation(p.approxBytes),
    }),
    opener: (location, pack) async => EmptyTileProvider(maxZoom: pack.maxZoom),
  );
  await service.load();
  return service;
}

/// A service that has finished looking and found nothing.
Future<OfflineMapService> noPacksInstalled() async {
  final service = OfflineMapService(
    locator: FakeMapPackLocator(const {}),
    opener: (location, pack) async => EmptyTileProvider(),
  );
  await service.load();
  return service;
}
