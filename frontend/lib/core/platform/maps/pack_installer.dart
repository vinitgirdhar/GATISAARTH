import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pmtiles/pmtiles.dart';

import 'offline_catalog.dart';
import 'region_extractor.dart';

/// A big archive that regions can be cut from, opened and ready.
class ArchiveSource {
  ArchiveSource({
    required this.archive,
    required this.reader,
    required this.build,
    this.onClose,
  });

  final PmTilesArchive archive;
  final ReadAt reader;

  /// Which build this is, e.g. `20260920`. Recorded in the downloaded file.
  final String build;
  final Future<void> Function()? onClose;

  Future<void> close() async => onClose?.call();
}

typedef SourceOpener = Future<ArchiveSource> Function();

/// Cuts one region out of the Protomaps planet build and stores it where the
/// app looks for offline maps.
///
/// Files are written as `<id>.pmtiles.part` and renamed only once complete and
/// checked, so the map never sees half a file, and an interrupted download
/// leaves nothing behind but a `.part` that is removed next time.
class PackInstaller {
  PackInstaller({
    Future<Directory> Function()? folder,
    SourceOpener? openSource,
    this.retryDelay = const Duration(milliseconds: 400),
  })  : _folder = folder ?? _defaultFolder,
        _openSource = openSource ?? _openProtomaps;

  final Future<Directory> Function() _folder;
  final SourceOpener _openSource;

  /// Pause before the first retry of a dropped request (it grows per retry).
  final Duration retryDelay;

  /// `<app files>/offline_maps`: the folder the Android side searches (see
  /// `locateMapPack` in MainActivity).
  static Future<Directory> _defaultFolder() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/offline_maps');
  }

  /// The latest Protomaps build, read with range requests.
  static Future<ArchiveSource> _openProtomaps() async {
    final client = http.Client();
    try {
      final build = await _latestBuild(client);
      final reader = HttpAt(client, Uri.parse(OfflineCatalog.buildUrl(build)));
      // ignore: invalid_use_of_visible_for_testing_member
      final archive = await PmTilesArchive.fromReadAt(reader);
      return ArchiveSource(
        archive: archive,
        reader: reader,
        build: build,
        onClose: () async => client.close(),
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  static Future<String> _latestBuild(http.Client client) async {
    try {
      final response = await client
          .get(Uri.parse(OfflineCatalog.buildsIndexUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final builds = jsonDecode(response.body) as List<dynamic>;
        final key = (builds.last as Map<String, dynamic>)['key'] as String;
        return key.replaceAll('.pmtiles', '');
      }
    } catch (_) {
      // Fall through: the build the app was made with usually still exists.
    }
    return OfflineCatalog.dataBuild.replaceAll('-', '');
  }

  /// Downloads [pack]. Returns the finished file. Throws [ExtractCancelled] when
  /// [cancel] is triggered.
  Future<File> install(
    OfflinePack pack, {
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    final dir = await _folder();
    await dir.create(recursive: true);
    final part = File('${dir.path}/${pack.id}.pmtiles.part');
    final dest = File('${dir.path}/${pack.fileName}');

    final source = await _openSource();
    try {
      await RegionExtractor(
        source: source.archive,
        reader: source.reader,
        retryDelay: retryDelay,
      ).extract(
        output: part,
        west: pack.west,
        south: pack.south,
        east: pack.east,
        north: pack.north,
        minZoom: 0,
        maxZoom: pack.maxZoom,
        extraMetadata: {
          'gatisaarth': {
            'pack': pack.id,
            'build': source.build,
            'downloadedAt': DateTime.now().toUtc().toIso8601String(),
          },
        },
        onProgress: onProgress,
        cancel: cancel,
      );
      await _verify(part);
      if (await dest.exists()) await dest.delete();
      await part.rename(dest.path);
      return dest;
    } catch (_) {
      await _deleteQuietly(part);
      rethrow;
    } finally {
      await source.close();
    }
  }

  /// Opens the finished file the way the map will, so a bad write is caught
  /// here and not on the first drive.
  Future<void> _verify(File file) async {
    final archive = await PmTilesArchive.fromFile(file);
    try {
      if (archive.header.tileType != TileType.mvt ||
          archive.header.numberOfAddressedTiles == 0) {
        throw StateError('The downloaded map file is not usable.');
      }
    } finally {
      await archive.close();
    }
  }

  /// Deletes an installed copy. Returns whether a file was removed.
  Future<bool> remove(File file) async {
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  /// Removes `.part` files left by a download the app did not survive.
  Future<void> cleanUp() async {
    final dir = await _folder();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.part')) {
        await _deleteQuietly(entity);
      }
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
