import 'dart:typed_data';

/// What an on-device model file turned out to be.
enum AssetState {
  /// No such asset in the bundle.
  missing,

  /// A Git-LFS pointer (a ~130-byte text file) checked out in place of the
  /// model: the repository ships the vibration and motion-quality assets this
  /// way until a real export replaces them.
  lfsPointer,

  /// Present but not a TFLite flatbuffer, or one the runtime refused.
  invalid,

  /// A float32-in, float32-out `[1, 20, 13]` model this app can run.
  loaded,

  /// A model the runtime loaded but whose input or output is not float32
  /// (an integer-quantised export): not run, rather than run wrongly.
  unsupportedIo,
}

extension AssetStateLabel on AssetState {
  String get label {
    switch (this) {
      case AssetState.missing:
        return 'not in the app';
      case AssetState.lfsPointer:
        return 'placeholder (Git-LFS pointer)';
      case AssetState.invalid:
        return 'not a valid model';
      case AssetState.loaded:
        return 'loaded';
      case AssetState.unsupportedIo:
        return 'integer I/O not supported yet';
    }
  }
}

/// Recognises a real TFLite file from its bytes alone.
class TfliteAsset {
  const TfliteAsset._();

  /// A TFLite flatbuffer carries the file identifier "TFL3" at byte 4. Anything
  /// starting with the Git-LFS pointer preamble is a stub; anything else too
  /// small or without the identifier is not a model.
  static AssetState inspect(Uint8List? bytes) {
    if (bytes == null) return AssetState.missing;
    if (_startsWith(bytes, 'version https://git-lfs')) {
      return AssetState.lfsPointer;
    }
    if (bytes.length < 64) return AssetState.invalid;
    const magic = 'TFL3';
    for (var i = 0; i < magic.length; i++) {
      if (bytes[4 + i] != magic.codeUnitAt(i)) return AssetState.invalid;
    }
    return AssetState.loaded;
  }

  static bool _startsWith(Uint8List bytes, String text) {
    if (bytes.length < text.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (bytes[i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }
}

/// One loaded model that takes a `[1, 20, 13]` float window.
abstract class WindowModel {
  /// Runs [window] (frames, oldest first; padded with zeros, which are the
  /// training mean once standardised, up to 20) and returns every output tensor
  /// flattened, or null when inference failed. Never throws.
  List<List<double>>? run(List<List<double>> window);

  void close();
}

/// The result of trying to load one model: the model when there is one, and
/// always what state the file was in.
class WindowModelLoad {
  const WindowModelLoad(this.state, [this.model]);

  final AssetState state;
  final WindowModel? model;
}

typedef WindowModelLoader = Future<WindowModelLoad> Function(String asset);
