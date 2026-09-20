import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'offline_catalog.dart';
import 'offline_map_service.dart';
import 'pack_installer.dart';
import 'region_extractor.dart';

enum PackPhase {
  /// Waiting its turn: one map downloads at a time.
  queued,

  /// Being downloaded now.
  downloading,

  /// The last attempt failed; [PackTask.error] says why in plain words.
  failed,
}

@immutable
class PackTask {
  const PackTask(this.phase, {this.fraction = 0, this.error});

  final PackPhase phase;

  /// 0..1 while downloading.
  final double fraction;
  final String? error;
}

/// Downloads maps on request and removes them again.
///
/// Nothing is fetched on its own: a download starts only from a tap (or from the
/// "download maps for where you are" prompt, which also needs a tap). One map
/// downloads at a time so a phone on mobile data is not flooded; the rest wait
/// in a queue. Finished maps are picked up by the [OfflineMapService] at once.
class MapDownloadService extends ChangeNotifier {
  MapDownloadService({
    required this.installer,
    required this.maps,
    Future<bool> Function()? isOnline,
    this.offerOnFirstFix = false,
  }) : _isOnline = isOnline ?? _probeInternet;

  final PackInstaller installer;
  final OfflineMapService maps;

  /// Whether the app may ask "download maps for where you are?" once it has a
  /// position. Off unless the app root turns it on, so screens under test do not
  /// find a sheet in the way.
  final bool offerOnFirstFix;
  final Future<bool> Function() _isOnline;

  final Map<String, PackTask> _tasks = {};
  final List<OfflinePack> _queue = [];
  OfflinePack? _current;
  CancelToken? _token;
  bool _pumping = false;
  bool _disposed = false;

  PackTask? taskFor(String packId) => _tasks[packId];

  /// The map being downloaded right now, if any.
  OfflinePack? get current => _current;

  /// Whether anything is downloading or waiting.
  bool get isBusy => _current != null || _queue.isNotEmpty;

  /// How many are downloading or waiting.
  int get pending => _queue.length + (_current == null ? 0 : 1);

  /// Progress of everything queued so far, 0..1: bytes done over bytes wanted.
  double get overallFraction {
    var total = 0;
    var done = 0.0;
    for (final entry in _tasks.entries) {
      final task = entry.value;
      if (task.phase == PackPhase.failed) continue;
      final bytes = _catalogPack(entry.key)?.approxBytes ?? 1;
      total += bytes;
      done += bytes * (task.phase == PackPhase.downloading ? task.fraction : 0);
    }
    return total == 0 ? 0 : done / total;
  }

  static OfflinePack? _catalogPack(String id) {
    for (final p in OfflineCatalog.packs) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Whether the phone can reach the map server right now.
  Future<bool> checkOnline() => _isOnline();

  /// Queues [pack]. Does nothing when it is already installed or already
  /// queued.
  void download(OfflinePack pack) => downloadAll([pack]);

  void downloadAll(Iterable<OfflinePack> packs) {
    for (final pack in packs) {
      if (maps.isInstalled(pack.id)) continue;
      final existing = _tasks[pack.id];
      if (existing != null && existing.phase != PackPhase.failed) continue;
      _tasks[pack.id] = const PackTask(PackPhase.queued);
      _queue.add(pack);
    }
    _notify();
    unawaited(_pump());
  }

  /// Stops a download or removes a queued one.
  void cancel(String packId) {
    if (_current?.id == packId) {
      _token?.cancel();
      return;
    }
    final before = _queue.length;
    _queue.removeWhere((p) => p.id == packId);
    if (_queue.length != before) {
      _tasks.remove(packId);
      _notify();
    }
  }

  void cancelAll() {
    for (final pack in List.of(_queue)) {
      cancel(pack.id);
    }
    _token?.cancel();
  }

  /// Forgets a failed attempt so its "try again" message goes away.
  void dismiss(String packId) {
    if (_tasks[packId]?.phase == PackPhase.failed) {
      _tasks.remove(packId);
      _notify();
    }
  }

  /// Removes a downloaded (or hand-copied) map from this phone. A map that ships
  /// inside the app cannot be removed and is left alone. Returns whether a file
  /// was deleted.
  Future<bool> delete(OfflinePack pack) async {
    final installed = maps.installedPack(pack.id);
    final path = installed?.path;
    if (installed == null || path == null) return false;
    final removed = await installer.remove(File(path));
    await maps.load();
    _notify();
    return removed;
  }

  // ----------------------------------------------------------------- worker

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      await installer.cleanUp();
      while (_queue.isNotEmpty && !_disposed) {
        final pack = _queue.removeAt(0);
        _current = pack;
        _token = CancelToken();
        _tasks[pack.id] = const PackTask(PackPhase.downloading);
        _notify();
        try {
          await installer.install(
            pack,
            cancel: _token,
            onProgress: (f) {
              _tasks[pack.id] = PackTask(PackPhase.downloading, fraction: f);
              _notify();
            },
          );
          _tasks.remove(pack.id);
          await maps.load();
        } on ExtractCancelled {
          _tasks.remove(pack.id);
        } catch (e) {
          _tasks[pack.id] =
              PackTask(PackPhase.failed, error: describeDownloadError(e));
          debugPrint('[MapDownload] ${pack.id} failed: $e');
        } finally {
          _current = null;
          _token = null;
          _notify();
        }
      }
    } finally {
      _pumping = false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }

  static Future<bool> _probeInternet() async {
    try {
      final hosts = await InternetAddress.lookup('build.protomaps.com')
          .timeout(const Duration(seconds: 3));
      return hosts.isNotEmpty && hosts.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

/// A download failure as one plain sentence for the person holding the phone.
String describeDownloadError(Object error) {
  if (error is FileSystemException) {
    // ENOSPC: the disk is full.
    if (error.osError?.errorCode == 28) {
      return 'Not enough free space on this phone.';
    }
    return 'The map could not be saved on this phone.';
  }
  if (error is SocketException ||
      error is HttpException ||
      error is TimeoutException ||
      error is HandshakeException) {
    return 'No connection. Check your internet and try again.';
  }
  if (error is StateError && '${error.message}'.contains('no map data')) {
    return 'There is no map data for this area.';
  }
  if (error is StateError &&
      '${error.message}'.toLowerCase().contains('map data')) {
    return '${error.message}';
  }
  return 'The download did not finish. Try again.';
}

/// Makes the [MapDownloadService] reachable from any screen.
class MapDownloadsScope extends InheritedNotifier<MapDownloadService> {
  const MapDownloadsScope({
    super.key,
    required MapDownloadService service,
    required super.child,
  }) : super(notifier: service);

  /// The service, or null where none was provided (widget tests that do not
  /// exercise downloads).
  static MapDownloadService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MapDownloadsScope>()
      ?.notifier;
}
