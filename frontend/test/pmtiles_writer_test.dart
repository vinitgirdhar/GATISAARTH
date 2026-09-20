import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/pmtiles_writer.dart';
import 'package:pmtiles/pmtiles.dart';

/// Writes a complete archive (head, then the given tile bytes) to [file].
Future<void> _writeArchive(
  File file,
  List<int> tileIds,
  List<Uint8List> tiles, {
  int leafSize = 4096,
  Map<String, Object?> metadata = const {'name': 'test'},
}) async {
  var offset = 0;
  final entries = <PmTileEntry>[];
  for (var i = 0; i < tileIds.length; i++) {
    entries.add(PmTileEntry(
      tileId: tileIds[i],
      offset: offset,
      length: tiles[i].length,
    ));
    offset += tiles[i].length;
  }
  final head = PmTilesWriter.head(
    entries: entries,
    metadata: metadata,
    west: 76.83,
    south: 28.38,
    east: 77.45,
    north: 28.90,
    minZoom: 0,
    maxZoom: 15,
    leafSize: leafSize,
  );
  final raf = await openArchiveForWriting(file, head);
  await raf.setPosition(head.tileDataOffset);
  for (final t in tiles) {
    await raf.writeFrom(t);
  }
  await raf.close();
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pmtiles_writer_'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('PmTilesWriter', () {
    test('a small archive reads back with the official reader', () async {
      final ids = [
        const ZXY(0, 0, 0).toTileId(),
        const ZXY(1, 0, 1).toTileId(),
        const ZXY(3, 5, 2).toTileId(),
        const ZXY(12, 2896, 1815).toTileId(),
      ]..sort();
      final originals = [
        for (var i = 0; i < ids.length; i++) 'tile-$i-${'x' * (10 + i * 7)}',
      ];
      final tiles = [
        for (final s in originals) Uint8List.fromList(gzip.encode(utf8.encode(s))),
      ];
      final file = File('${dir.path}/small.pmtiles');
      await _writeArchive(file, ids, tiles);

      final archive = await PmTilesArchive.fromFile(file);
      final h = archive.header;
      expect(h.version, 3);
      expect(h.clustered, Clustered.clustered);
      expect(h.tileType, TileType.mvt);
      expect(h.tileCompression, Compression.gzip);
      expect(h.internalCompression, Compression.gzip);
      expect(h.minZoom, 0);
      expect(h.maxZoom, 15);
      expect(h.numberOfAddressedTiles, 4);
      expect(h.minPosition.longitude, closeTo(76.83, 1e-6));
      expect(h.minPosition.latitude, closeTo(28.38, 1e-6));
      expect(h.maxPosition.longitude, closeTo(77.45, 1e-6));
      expect(h.maxPosition.latitude, closeTo(28.90, 1e-6));
      expect(file.lengthSync(), h.tileDataOffset + h.tileDataLength);

      for (var i = 0; i < ids.length; i++) {
        final tile = await archive.tile(ids[i]);
        expect(utf8.decode(tile.bytes()), originals[i], reason: 'tile $i');
      }
      // A tile that is not in the archive is reported as missing.
      final missing = await archive.tile(const ZXY(5, 1, 1).toTileId());
      expect(() => missing.bytes(), throwsA(isA<TileNotFoundException>()));
    });

    test('metadata survives', () async {
      final file = File('${dir.path}/meta.pmtiles');
      await _writeArchive(
        file,
        [const ZXY(0, 0, 0).toTileId()],
        [Uint8List.fromList(gzip.encode([1, 2, 3]))],
        metadata: const {
          'name': 'Delhi',
          'attribution': '© OpenStreetMap',
          'nested': {'a': 1},
        },
      );
      final archive = await PmTilesArchive.fromFile(file);
      expect(await archive.metadata, {
        'name': 'Delhi',
        'attribution': '© OpenStreetMap',
        'nested': {'a': 1},
      });
    });

    test('a long tile list goes into leaf directories and every tile is found',
        () async {
      final rnd = math.Random(3);
      // Twenty thousand tiles at zoom 14, scattered, with uneven lengths so the
      // directory does not compress to nothing.
      final ids = <int>{};
      while (ids.length < 20000) {
        ids.add(ZXY(14, rnd.nextInt(1 << 14), rnd.nextInt(1 << 14)).toTileId());
      }
      final sorted = ids.toList()..sort();
      final lengths = [for (final _ in sorted) 5 + rnd.nextInt(200)];
      var offset = 0;
      final entries = <PmTileEntry>[];
      for (var i = 0; i < sorted.length; i++) {
        entries.add(PmTileEntry(
            tileId: sorted[i], offset: offset, length: lengths[i]));
        offset += lengths[i];
      }
      final head = PmTilesWriter.head(
        entries: entries,
        metadata: const {},
        west: 0,
        south: 0,
        east: 1,
        north: 1,
        minZoom: 14,
        maxZoom: 14,
      );
      // Must fit the first 16 KiB, or a reader cannot even find the root.
      expect(head.bytes.length - 127, greaterThan(0));
      final file = File('${dir.path}/big.pmtiles');
      final raf = await openArchiveForWriting(file, head);
      await raf.close();

      final archive = await PmTilesArchive.fromFile(file);
      expect(archive.header.leafDirectoriesLength, greaterThan(0));
      expect(archive.header.rootDirectoryLength + 127,
          lessThanOrEqualTo(PmTilesWriter.headAndRootLimit));
      expect(archive.header.numberOfAddressedTiles, 20000);
      for (final i in [0, 1, 4095, 4096, 4097, 10000, 19998, 19999]) {
        final e = await archive.lookup(sorted[i]);
        expect(e, isNotNull, reason: 'entry $i');
        expect(e!.offset, entries[i].offset, reason: 'offset $i');
        expect(e.length, entries[i].length, reason: 'length $i');
      }
      // Ids between the stored ones are absent.
      expect(await archive.lookup(sorted[100] + 1), sorted[101] == sorted[100] + 1 ? isNotNull : isNull);
    });

    test('refuses entries a reader could not use', () {
      PmTilesHead build(List<PmTileEntry> e) => PmTilesWriter.head(
            entries: e,
            metadata: const {},
            west: 0,
            south: 0,
            east: 1,
            north: 1,
            minZoom: 0,
            maxZoom: 1,
          );
      expect(() => build(const []), throwsArgumentError);
      expect(
        () => build(const [
          PmTileEntry(tileId: 5, offset: 0, length: 3),
          PmTileEntry(tileId: 2, offset: 3, length: 3),
        ]),
        throwsArgumentError,
        reason: 'unsorted',
      );
      expect(
        () => build(const [
          PmTileEntry(tileId: 1, offset: 0, length: 3),
          PmTileEntry(tileId: 2, offset: 9, length: 3),
        ]),
        throwsArgumentError,
        reason: 'gap in the tile data',
      );
    });
  });

  group('TileMath', () {
    test('known tiles', () {
      // West Delhi, the point the app's tests use.
      expect(TileMath.tileX(77.0661, 15), 23398);
      expect(TileMath.tileY(28.639, 15), 13661);
      expect(TileMath.tileX(0, 0), 0);
      expect(TileMath.tileY(0, 1), 1);
      expect(TileMath.tileY(89, 3), 0, reason: 'clamped at the pole');
    });

    test('counts what the official pmtiles tool reported for each area', () {
      int count(OfflinePack p, {int? maxZoom}) => TileMath.count(
            west: p.west,
            south: p.south,
            east: p.east,
            north: p.north,
            minZoom: 0,
            maxZoom: maxZoom ?? p.maxZoom,
          );
      // "Region tiles N" from `pmtiles extract --dry-run` on the same boxes.
      expect(count(OfflineCatalog.delhiNcr), 4270);
      expect(count(OfflineCatalog.delhiNcr, maxZoom: 14), 1135);
      expect(count(OfflineCatalog.maharashtraState), 10170);
      expect(count(OfflineCatalog.mumbai), 4262);
      expect(count(OfflineCatalog.pune), 1859);
      expect(count(OfflineCatalog.nagpur), 1188);
      expect(count(OfflineCatalog.nashik), 625);
      expect(count(OfflineCatalog.sambhajinagar), 474);
    });
  });
}
