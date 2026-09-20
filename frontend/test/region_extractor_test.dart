import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/maps/pmtiles_writer.dart';
import 'package:gatisaarth/core/platform/maps/region_extractor.dart';
import 'package:http/http.dart' show ByteStream;
import 'package:pmtiles/pmtiles.dart';

/// A real 3 km square of West Delhi cut from the bundled archive (27 tiles, zoom
/// 0-15, 1.3 MB). The extractor is tested by cutting from it: the same code path
/// as cutting from the planet over HTTP, with a file as the "server".
final File _source = File('test/fixtures/mini_delhi.pmtiles');
final bool _present = _source.existsSync();
const String _skip = 'fixture missing';

/// The fixture's box.
const double _west = 77.050;
const double _south = 28.630;
const double _east = 77.080;
const double _north = 28.650;

/// A reader that fails a set number of times first, and counts its requests.
class _FlakyReader implements ReadAt {
  _FlakyReader(this.inner, {this.failures = 0});

  final ReadAt inner;
  int failures;
  int requests = 0;

  @override
  Future<ByteStream> readAt(int offset, int length) async {
    requests++;
    if (failures > 0) {
      failures--;
      throw const SocketException('connection reset');
    }
    return inner.readAt(offset, length);
  }

  @override
  Future<void> close() => inner.close();
}

Future<Uint8List> _tileBytes(PmTilesArchive a, int id) async =>
    Uint8List.fromList((await a.tile(id)).bytes());

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('extractor_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(PmTilesArchive, _FlakyReader)> open({int failures = 0}) async {
    final reader = _FlakyReader(FileAt(_source), failures: failures);
    // ignore: invalid_use_of_visible_for_testing_member
    final archive = await PmTilesArchive.fromReadAt(reader);
    return (archive, reader);
  }

  test('cutting the whole box reproduces every tile exactly', () async {
    final (archive, reader) = await open();
    final out = File('${dir.path}/all.pmtiles');
    final result = await RegionExtractor(source: archive, reader: reader)
        .extract(
      output: out,
      west: _west,
      south: _south,
      east: _east,
      north: _north,
      minZoom: 0,
      maxZoom: 15,
    );

    final copy = await PmTilesArchive.fromFile(out);
    expect(copy.header.numberOfAddressedTiles, archive.header.numberOfAddressedTiles);
    expect(result.tiles, archive.header.numberOfAddressedTiles);
    expect(out.lengthSync(), result.fileBytes);
    expect(copy.header.minZoom, 0);
    expect(copy.header.maxZoom, 15);
    expect(copy.header.tileType, TileType.mvt);
    expect(copy.header.tileCompression, Compression.gzip);

    // Every tile of the source, byte for byte.
    var checked = 0;
    for (var z = 0; z <= 15; z++) {
      final (x0, y0, x1, y1) = TileMath.range(
        west: _west,
        south: _south,
        east: _east,
        north: _north,
        zoom: z,
      );
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          final id = ZXY(z, x, y).toTileId();
          final want = await archive.lookup(id);
          if (want == null) continue;
          expect(await _tileBytes(copy, id), await _tileBytes(archive, id),
              reason: 'tile $z/$x/$y');
          checked++;
        }
      }
    }
    expect(checked, result.tiles);
  }, skip: _present ? false : _skip);

  test('a smaller box and a lower zoom keep only what is asked for', () async {
    final (archive, reader) = await open();
    final out = File('${dir.path}/sub.pmtiles');
    // The middle of the box, to zoom 13.
    final w = _west + (_east - _west) * 0.35;
    final e = _west + (_east - _west) * 0.65;
    final s = _south + (_north - _south) * 0.35;
    final n = _south + (_north - _south) * 0.65;
    final result = await RegionExtractor(source: archive, reader: reader)
        .extract(
      output: out,
      west: w,
      south: s,
      east: e,
      north: n,
      minZoom: 0,
      maxZoom: 13,
    );

    expect(result.tiles, lessThan(archive.header.numberOfAddressedTiles));
    final copy = await PmTilesArchive.fromFile(out);
    expect(copy.header.maxZoom, 13);
    expect(copy.header.minPosition.longitude, closeTo(w, 1e-6));
    expect(copy.header.maxPosition.latitude, closeTo(n, 1e-6));

    // No tile deeper than zoom 13, and everything inside the box is there.
    final deepId = ZXY(15, TileMath.tileX(77.065, 15), TileMath.tileY(28.64, 15))
        .toTileId();
    expect(await archive.lookup(deepId), isNotNull, reason: 'in the source');
    expect(await copy.lookup(deepId), isNull, reason: 'deeper than asked');
    var expected = 0;
    for (var z = 0; z <= 13; z++) {
      final (x0, y0, x1, y1) =
          TileMath.range(west: w, south: s, east: e, north: n, zoom: z);
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          final id = ZXY(z, x, y).toTileId();
          if (await archive.lookup(id) == null) continue;
          expected++;
          expect(await _tileBytes(copy, id), await _tileBytes(archive, id));
        }
      }
    }
    expect(result.tiles, expected);
  }, skip: _present ? false : _skip);

  test('progress only moves forward and ends at one', () async {
    final (archive, reader) = await open();
    final seen = <double>[];
    await RegionExtractor(source: archive, reader: reader).extract(
      output: File('${dir.path}/p.pmtiles'),
      west: _west,
      south: _south,
      east: _east,
      north: _north,
      minZoom: 0,
      maxZoom: 15,
      onProgress: seen.add,
    );
    expect(seen, isNotEmpty);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
    expect(seen.first, greaterThanOrEqualTo(0));
    expect(seen.last, 1);
  }, skip: _present ? false : _skip);

  test('requests are batched, not one per tile', () async {
    final (archive, reader) = await open();
    final before = reader.requests; // opening the archive
    final result = await RegionExtractor(source: archive, reader: reader)
        .extract(
      output: File('${dir.path}/b.pmtiles'),
      west: _west,
      south: _south,
      east: _east,
      north: _north,
      minZoom: 0,
      maxZoom: 15,
    );
    final used = reader.requests - before;
    expect(used, lessThan(result.tiles ~/ 2),
        reason: '$used requests for ${result.tiles} tiles');
  }, skip: _present ? false : _skip);

  test('tiny requests give the same archive as big ones', () async {
    Future<Uint8List> cut(int gap, int chunk, String name) async {
      final (archive, reader) = await open();
      final out = File('${dir.path}/$name.pmtiles');
      await RegionExtractor(
        source: archive,
        reader: reader,
        maxGapBytes: gap,
        maxChunkBytes: chunk,
        concurrency: 2,
      ).extract(
        output: out,
        west: _west,
        south: _south,
        east: _east,
        north: _north,
        minZoom: 0,
        maxZoom: 12,
      );
      return out.readAsBytesSync();
    }

    final perTile = await cut(0, 1, 'a');
    final bulk = await cut(1 << 30, 1 << 30, 'b');
    expect(perTile, bulk);
  }, skip: _present ? false : _skip);

  test('a dropped connection is retried, a dead one is reported', () async {
    final (archive, reader) = await open();
    reader.failures = 2; // fewer than the three tries
    final ok = await RegionExtractor(
      source: archive,
      reader: reader,
      retryDelay: Duration.zero,
    ).extract(
      output: File('${dir.path}/r.pmtiles'),
      west: _west,
      south: _south,
      east: _east,
      north: _north,
      minZoom: 0,
      maxZoom: 8,
    );
    expect(ok.tiles, greaterThan(0));

    final (archive2, reader2) = await open();
    reader2.failures = 100;
    await expectLater(
      RegionExtractor(source: archive2, reader: reader2, retryDelay: Duration.zero)
          .extract(
        output: File('${dir.path}/dead.pmtiles'),
        west: _west,
        south: _south,
        east: _east,
        north: _north,
        minZoom: 0,
        maxZoom: 8,
      ),
      throwsA(isA<SocketException>()),
    );
  }, skip: _present ? false : _skip);

  test('cancelling stops it', () async {
    final (archive, reader) = await open();
    final token = CancelToken();
    await expectLater(
      // One tile per request, so there is a request left to stop.
      RegionExtractor(
        source: archive,
        reader: reader,
        maxGapBytes: 0,
        maxChunkBytes: 1,
        concurrency: 1,
      ).extract(
        output: File('${dir.path}/c.pmtiles'),
        west: _west,
        south: _south,
        east: _east,
        north: _north,
        minZoom: 0,
        maxZoom: 15,
        cancel: token,
        onProgress: (f) {
          if (f > 0.3) token.cancel();
        },
      ),
      throwsA(isA<ExtractCancelled>()),
    );
  }, skip: _present ? false : _skip);

  test('an area with no map data says so', () async {
    final (archive, reader) = await open();
    await expectLater(
      RegionExtractor(source: archive, reader: reader).extract(
        output: File('${dir.path}/none.pmtiles'),
        // Deep in the Atlantic, far outside the archive.
        west: -30,
        south: 0,
        east: -29,
        north: 1,
        minZoom: 10,
        maxZoom: 12,
      ),
      throwsA(isA<StateError>()),
    );
  }, skip: _present ? false : _skip);
}
