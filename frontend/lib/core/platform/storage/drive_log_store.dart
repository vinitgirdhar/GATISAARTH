import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One recorded drive on disk.
@immutable
class DriveLogFile {
  const DriveLogFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modified,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;

  double get sizeMb => sizeBytes / (1024 * 1024);
}

/// What a drive recorder needs from storage.
///
/// An interface so the session controller can be tested without a file system,
/// and so a log could later go somewhere else entirely without the controller
/// knowing.
abstract class DriveLogSink {
  /// Opens a log and returns its path, or null when storage is unavailable.
  Future<String?> open(String sessionId);

  /// Receives one JSONL line.
  void write(String line);

  /// Flushes and closes, returning the finished file.
  Future<DriveLogFile?> close();

  /// The last write error, or null.
  Object? get lastError;
}

/// Writes drive logs to the app's private storage (§36, §48).
///
/// **Privacy.** A drive log is a complete record of where the phone went. It
/// therefore lives in the app's private directory, is never uploaded, is only
/// written when the driver asks for it, and can be deleted from here. Nothing
/// in the navigation core knows this class exists — the core hands lines to a
/// callback and has no idea whether they reach a file, a socket, or nowhere.
class DriveLogStore implements DriveLogSink {
  DriveLogStore({this.flushEvery = 256});

  /// Lines buffered before touching the file. At 50 Hz this is a write every
  /// five seconds rather than fifty a second.
  final int flushEvery;

  IOSink? _sink;
  File? _file;
  final List<String> _buffer = [];
  int _writtenLines = 0;
  Object? _lastError;

  bool get isOpen => _sink != null;
  String? get currentPath => _file?.path;
  int get writtenLines => _writtenLines;

  /// The last write error, or null. Recording failures must be visible, not
  /// swallowed — a driver who thinks they recorded a drive and did not has
  /// lost the drive.
  @override
  Object? get lastError => _lastError;

  static Future<Directory> _directory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/drives');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Opens a new log. Returns the path, or null when storage is unavailable.
  @override
  Future<String?> open(String sessionId) async {
    if (_sink != null) return _file?.path;
    try {
      final dir = await _directory();
      final file = File('${dir.path}/$sessionId.jsonl');
      _file = file;
      _sink = file.openWrite(mode: FileMode.writeOnly);
      _writtenLines = 0;
      _lastError = null;
      return file.path;
    } catch (e) {
      _lastError = e;
      _sink = null;
      _file = null;
      debugPrint('[DriveLogStore] could not open a log: $e');
      return null;
    }
  }

  /// The sink handed to `DriveRecorder`.
  @override
  void write(String line) {
    if (_sink == null) return;
    _buffer.add(line);
    _writtenLines++;
    if (_buffer.length >= flushEvery) _drain();
  }

  void _drain() {
    final sink = _sink;
    if (sink == null || _buffer.isEmpty) return;
    try {
      sink.write('${_buffer.join('\n')}\n');
      _buffer.clear();
    } catch (e) {
      _lastError = e;
      _buffer.clear();
      debugPrint('[DriveLogStore] write failed: $e');
    }
  }

  /// Flushes and closes. Safe to call twice.
  @override
  Future<DriveLogFile?> close() async {
    final sink = _sink;
    final file = _file;
    if (sink == null || file == null) return null;
    _drain();
    _sink = null;
    _file = null;
    try {
      await sink.flush();
      await sink.close();
      final stat = file.statSync();
      return DriveLogFile(
        path: file.path,
        name: file.uri.pathSegments.last,
        sizeBytes: stat.size,
        modified: stat.modified,
      );
    } catch (e) {
      _lastError = e;
      debugPrint('[DriveLogStore] close failed: $e');
      return null;
    }
  }

  /// Every recorded drive, newest first.
  static Future<List<DriveLogFile>> list() async {
    try {
      final dir = await _directory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl'))
          .map((f) {
        final stat = f.statSync();
        return DriveLogFile(
          path: f.path,
          name: f.uri.pathSegments.last,
          sizeBytes: stat.size,
          modified: stat.modified,
        );
      }).toList();
      files.sort((a, b) => b.modified.compareTo(a.modified));
      return files;
    } catch (e) {
      debugPrint('[DriveLogStore] list failed: $e');
      return const [];
    }
  }

  /// Reads a log back for replay. Streams rather than loading whole: an hour
  /// of driving is tens of megabytes.
  static Stream<String> readLines(String path) =>
      File(path).openRead().transform(const SystemEncoding().decoder).transform(
            const LineSplitter(),
          );

  /// Deletes one drive. The driver owns this data and can remove it (§48).
  static Future<bool> delete(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      await file.delete();
      return true;
    } catch (e) {
      debugPrint('[DriveLogStore] delete failed: $e');
      return false;
    }
  }

  static Future<int> totalBytes() async {
    final files = await list();
    return files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
  }
}

/// `dart:convert`'s LineSplitter, imported through a name that does not clash
/// with anything in the navigation core.
class LineSplitter extends StreamTransformerBase<String, String> {
  const LineSplitter();

  @override
  Stream<String> bind(Stream<String> stream) async* {
    var carry = '';
    await for (final chunk in stream) {
      final combined = carry + chunk;
      final parts = combined.split('\n');
      carry = parts.removeLast();
      for (final part in parts) {
        if (part.isNotEmpty) yield part;
      }
    }
    if (carry.isNotEmpty) yield carry;
  }
}
