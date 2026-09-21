import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ByteStream;
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/pack_installer.dart';
import 'package:gatisaarth/core/platform/maps/region_extractor.dart';
import 'package:pmtiles/pmtiles.dart';

/// A pack whose box is the fixture's 3 km square of West Delhi, so the fixture
/// can play the part of the planet build.
const OfflinePack _testPack = OfflinePack(
  id: 'test-delhi',
  name: 'Test area',
  south: 28.630,
  west: 77.050,
  north: 28.650,
  east: 77.080,
  maxZoom: 15,
  approxBytes: 1300000,
);

final File _fixture = File('test/fixtures/mini_delhi.pmtiles');

/// Reads normally until told it is [dead], then fails every request.
class _DeadAfterOpen implements ReadAt {
  _DeadAfterOpen(this.inner);

  final ReadAt inner;
  bool dead = false;

  @override
  Future<ByteStream> readAt(int offset, int length) async {
    if (dead) throw const SocketException('network is gone');
    return inner.readAt(offset, length);
  }

  @override
  Future<void> close() => inner.close();
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pack_installer_'));
  tearDown(() => dir.deleteSync(recursive: true));

  int closed = 0;

  PackInstaller installer({int opens = 1}) => PackInstaller(
        folder: () async => Directory('${dir.path}/offline_maps'),
        openSource: () async {
          final reader = FileAt(_fixture);
          // ignore: invalid_use_of_visible_for_testing_member
          final archive = await PmTilesArchive.fromReadAt(reader);
          return ArchiveSource(
            archive: archive,
            reader: reader,
            build: '20260920',
            onClose: () async => closed++,
          );
        },
      );

  File installed() => File('${dir.path}/offline_maps/test-delhi.pmtiles');
  File part() => File('${dir.path}/offline_maps/test-delhi.pmtiles.part');

  setUp(() => closed = 0);

  test('installs a region as a finished, readable file', () async {
    final fractions = <double>[];
    final file = await installer().install(_testPack, onProgress: fractions.add);

    expect(file.path, installed().path);
    expect(installed().existsSync(), isTrue);
    expect(part().existsSync(), isFalse, reason: 'no half-file left behind');
    expect(fractions.last, 1);
    expect(closed, 1, reason: 'the connection is closed');

    final archive = await PmTilesArchive.fromFile(installed());
    expect(archive.header.tileType, TileType.mvt);
    expect(archive.header.maxZoom, 15);
    expect(archive.header.numberOfAddressedTiles, 27);
    // The download records where it came from.
    final meta = await archive.metadata as Map<String, dynamic>;
    final ours = meta['gatisaarth'] as Map<String, dynamic>;
    expect(ours['pack'], 'test-delhi');
    expect(ours['build'], '20260920');
    expect(ours['downloadedAt'], isNotNull);
    await archive.close();
  }, skip: _fixture.existsSync() ? false : 'fixture missing');

  test('replaces an older copy of the same map', () async {
    Directory('${dir.path}/offline_maps').createSync();
    installed().writeAsBytesSync([9, 9, 9]);
    await installer().install(_testPack);
    expect(installed().lengthSync(), greaterThan(1000));
  }, skip: _fixture.existsSync() ? false : 'fixture missing');

  test('a failed download leaves no partial file', () async {
    // The archive opens, then every tile request fails.
    final failing = PackInstaller(
      retryDelay: Duration.zero,
      folder: () async => Directory('${dir.path}/offline_maps'),
      openSource: () async {
        final inner = FileAt(_fixture);
        final reader = _DeadAfterOpen(inner);
        // ignore: invalid_use_of_visible_for_testing_member
        final archive = await PmTilesArchive.fromReadAt(reader);
        reader.dead = true;
        return ArchiveSource(
          archive: archive,
          reader: reader,
          build: 'x',
          onClose: () async => closed++,
        );
      },
    );
    await expectLater(failing.install(_testPack), throwsA(isA<SocketException>()));
    expect(part().existsSync(), isFalse);
    expect(installed().existsSync(), isFalse);
    expect(closed, 1, reason: 'closed even on failure');
  }, skip: _fixture.existsSync() ? false : 'fixture missing');

  test('cancelling removes the partial file', () async {
    final token = CancelToken();
    await expectLater(
      installer().install(
        _testPack,
        cancel: token,
        // Cancel as soon as the work has started.
        onProgress: (_) => token.cancel(),
      ),
      throwsA(isA<ExtractCancelled>()),
    );
    expect(part().existsSync(), isFalse);
    expect(installed().existsSync(), isFalse);
    expect(closed, 1);
  }, skip: _fixture.existsSync() ? false : 'fixture missing');

  test('cleanUp removes what an interrupted download left', () async {
    Directory('${dir.path}/offline_maps').createSync();
    part().writeAsBytesSync([1]);
    installed().writeAsBytesSync([2]); // a finished map must survive
    await installer().cleanUp();
    expect(part().existsSync(), isFalse);
    expect(installed().existsSync(), isTrue);
  });

  test('cleanUp on a phone with no maps folder is harmless', () async {
    await installer().cleanUp();
  });

  test('remove deletes the file and says whether it did', () async {
    Directory('${dir.path}/offline_maps').createSync();
    installed().writeAsBytesSync([1, 2]);
    final i = installer();
    expect(await i.remove(installed()), isTrue);
    expect(installed().existsSync(), isFalse);
    expect(await i.remove(installed()), isFalse);
  });
}
