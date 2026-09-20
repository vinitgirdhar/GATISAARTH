import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/maps/map_download_service.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_installer.dart';
import 'package:gatisaarth/core/platform/maps/pack_reader.dart';
import 'package:gatisaarth/core/platform/maps/region_extractor.dart';

import 'support/fake_map_packs.dart';

/// Stands in for the network: writes a small file instead of cutting a region,
/// can be held open, and can be told to fail.
class _FakeInstaller extends PackInstaller {
  _FakeInstaller(this.dir) : super(folder: () async => dir);

  final Directory dir;
  final List<String> started = [];
  int cleanUps = 0;
  Completer<void>? gate;
  Object? failWith;

  @override
  Future<File> install(
    OfflinePack pack, {
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    started.add(pack.id);
    onProgress?.call(0.25);
    await gate?.future;
    cancel?.throwIfCancelled();
    final error = failWith;
    if (error != null) throw error;
    onProgress?.call(1);
    return File('${dir.path}/${pack.fileName}')..writeAsBytesSync([1, 2, 3]);
  }

  @override
  Future<void> cleanUp() async => cleanUps++;
}

/// Finds archives in the fake installer's folder, like the real one does.
class _FolderLocator implements MapPackLocator {
  _FolderLocator(this.dir);

  final Directory dir;

  @override
  Future<PackLocation?> locate(String fileName) async {
    final file = File('${dir.path}/$fileName');
    if (!file.existsSync()) return null;
    return PackLocation(
      path: file.path,
      offset: 0,
      length: file.lengthSync(),
      origin: PackOrigin.downloaded,
    );
  }
}

void main() {
  late Directory dir;
  late OfflineMapService maps;
  late _FakeInstaller installer;
  late MapDownloadService downloads;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('map_downloads_');
    maps = OfflineMapService(
      locator: _FolderLocator(dir),
      opener: (l, p) async => EmptyTileProvider(),
    );
    await maps.load();
    installer = _FakeInstaller(dir);
    downloads = MapDownloadService(
      installer: installer,
      maps: maps,
      isOnline: () async => true,
    );
  });

  tearDown(() {
    downloads.dispose();
    maps.dispose();
    dir.deleteSync(recursive: true);
  });

  /// Lets queued async work run.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('a download goes queued, downloading, then installed', () async {
    installer.gate = Completer<void>();
    final states = <PackPhase?>[];
    downloads.addListener(() => states.add(downloads.taskFor('pune')?.phase));

    downloads.download(OfflineCatalog.pune);
    expect(downloads.taskFor('pune')!.phase, PackPhase.queued);
    await settle();
    expect(downloads.taskFor('pune')!.phase, PackPhase.downloading);
    expect(downloads.taskFor('pune')!.fraction, 0.25);
    expect(downloads.isBusy, isTrue);
    expect(downloads.current!.id, 'pune');

    installer.gate!.complete();
    await settle();
    expect(downloads.taskFor('pune'), isNull, reason: 'done: no task left');
    expect(downloads.isBusy, isFalse);
    expect(maps.isInstalled('pune'), isTrue);
    expect(maps.installedPack('pune')!.origin, PackOrigin.downloaded);
    expect(states, contains(PackPhase.downloading));
    expect(installer.cleanUps, greaterThanOrEqualTo(1),
        reason: 'leftovers of an interrupted run are cleared first');
  });

  test('maps download one at a time, in the order asked', () async {
    installer.gate = Completer<void>();
    downloads.downloadAll(
        [OfflineCatalog.pune, OfflineCatalog.nagpur, OfflineCatalog.nashik]);
    await settle();

    expect(installer.started, ['pune'], reason: 'only one at once');
    expect(downloads.taskFor('nagpur')!.phase, PackPhase.queued);
    expect(downloads.taskFor('nashik')!.phase, PackPhase.queued);
    expect(downloads.pending, 3);

    installer.gate!.complete();
    await settle();
    await settle();
    expect(installer.started, ['pune', 'nagpur', 'nashik']);
    expect(downloads.isBusy, isFalse);
    for (final id in ['pune', 'nagpur', 'nashik']) {
      expect(maps.isInstalled(id), isTrue, reason: id);
    }
  });

  test('asking twice, or for a map already on the phone, downloads once',
      () async {
    installer.gate = Completer<void>();
    downloads.download(OfflineCatalog.pune);
    downloads.download(OfflineCatalog.pune);
    await settle();
    installer.gate!.complete();
    await settle();
    expect(installer.started, ['pune']);

    downloads.download(OfflineCatalog.pune); // already installed
    await settle();
    expect(installer.started, ['pune']);
  });

  test('a failure is explained in plain words and can be retried', () async {
    installer.failWith = const SocketException('unreachable');
    downloads.download(OfflineCatalog.pune);
    await settle();

    final task = downloads.taskFor('pune')!;
    expect(task.phase, PackPhase.failed);
    expect(task.error, contains('No connection'));
    expect(maps.isInstalled('pune'), isFalse);
    expect(downloads.isBusy, isFalse, reason: 'a failure is not "busy"');

    installer.failWith = null;
    downloads.download(OfflineCatalog.pune); // retry
    await settle();
    expect(maps.isInstalled('pune'), isTrue);
    expect(downloads.taskFor('pune'), isNull);
  });

  test('dismissing a failure clears its message', () async {
    installer.failWith = StateError('boom');
    downloads.download(OfflineCatalog.pune);
    await settle();
    expect(downloads.taskFor('pune')!.phase, PackPhase.failed);
    downloads.dismiss('pune');
    expect(downloads.taskFor('pune'), isNull);
  });

  test('cancelling the running download leaves nothing installed', () async {
    installer.gate = Completer<void>();
    downloads.download(OfflineCatalog.pune);
    await settle();
    downloads.cancel('pune');
    installer.gate!.complete();
    await settle();

    expect(downloads.taskFor('pune'), isNull, reason: 'cancelled, not failed');
    expect(maps.isInstalled('pune'), isFalse);
    expect(downloads.isBusy, isFalse);
  });

  test('cancelling a queued map just removes it from the queue', () async {
    installer.gate = Completer<void>();
    downloads.downloadAll([OfflineCatalog.pune, OfflineCatalog.nagpur]);
    await settle();
    downloads.cancel('nagpur');
    expect(downloads.taskFor('nagpur'), isNull);

    installer.gate!.complete();
    await settle();
    expect(installer.started, ['pune']);
    expect(maps.isInstalled('nagpur'), isFalse);
  });

  test('overall progress is weighted by size', () async {
    installer.gate = Completer<void>();
    downloads.downloadAll([OfflineCatalog.pune, OfflineCatalog.nashik]);
    await settle();
    // Pune (17 MB) at 25 %, Nashik (4 MB) not started.
    final total = OfflineCatalog.pune.approxBytes + OfflineCatalog.nashik.approxBytes;
    expect(downloads.overallFraction,
        closeTo(OfflineCatalog.pune.approxBytes * 0.25 / total, 1e-9));
    installer.gate!.complete();
    await settle();
    await settle();
  });

  group('delete', () {
    test('removes a downloaded map from the phone', () async {
      downloads.download(OfflineCatalog.pune);
      await settle();
      final file = File('${dir.path}/pune.pmtiles');
      expect(file.existsSync(), isTrue);

      expect(await downloads.delete(OfflineCatalog.pune), isTrue);
      expect(file.existsSync(), isFalse);
      expect(maps.isInstalled('pune'), isFalse);
    });

    test('leaves a map that ships inside the app alone', () async {
      final bundled = OfflineMapService(
        locator: FakeMapPackLocator({
          'delhi-ncr.pmtiles': fakeLocation(100), // bundled
        }),
        opener: (l, p) async => EmptyTileProvider(),
      );
      await bundled.load();
      final service =
          MapDownloadService(installer: installer, maps: bundled);
      expect(await service.delete(OfflineCatalog.delhiNcr), isFalse);
      expect(bundled.isInstalled('delhi-ncr'), isTrue);
      service.dispose();
      bundled.dispose();
    });

    test('a map that is not installed has nothing to delete', () async {
      expect(await downloads.delete(OfflineCatalog.nashik), isFalse);
    });
  });

  test('a bundled map is never downloaded again', () async {
    final bundled = OfflineMapService(
      locator: FakeMapPackLocator({'delhi-ncr.pmtiles': fakeLocation(100)}),
      opener: (l, p) async => EmptyTileProvider(),
    );
    await bundled.load();
    final service = MapDownloadService(installer: installer, maps: bundled);
    service.download(OfflineCatalog.delhiNcr);
    await settle();
    expect(installer.started, isEmpty);
    service.dispose();
    bundled.dispose();
  });

  test('disposing mid-download does not throw', () async {
    installer.gate = Completer<void>();
    final local = MapDownloadService(installer: installer, maps: maps);
    local.download(OfflineCatalog.pune);
    await settle();
    local.dispose();
    installer.gate!.complete();
    await settle();
  });

  group('describeDownloadError', () {
    test('turns failures into sentences a person can act on', () {
      expect(describeDownloadError(const SocketException('x')),
          contains('No connection'));
      expect(describeDownloadError(TimeoutException('slow')),
          contains('No connection'));
      expect(describeDownloadError(const HttpException('503')),
          contains('No connection'));
      expect(
        describeDownloadError(FileSystemException(
            'write', '/x', const OSError('No space left on device', 28))),
        contains('free space'),
      );
      expect(describeDownloadError(const FileSystemException('write', '/x')),
          contains('could not be saved'));
      expect(describeDownloadError(StateError('There is no map data in this area.')),
          contains('no map data'));
      expect(describeDownloadError(Exception('anything')),
          contains('did not finish'));
    });
  });
}
