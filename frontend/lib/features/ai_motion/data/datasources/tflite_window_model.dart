import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'tflite_asset.dart';

/// Loads [asset] from the bundle. Every way that can go wrong (missing, a
/// pointer file, a corrupt flatbuffer, a runtime that refuses it, integer I/O)
/// comes back as a state and no model, never an exception.
Future<WindowModelLoad> loadWindowModelFromAsset(String asset) async {
  final Uint8List bytes;
  try {
    bytes = (await rootBundle.load(asset)).buffer.asUint8List();
  } catch (_) {
    return const WindowModelLoad(AssetState.missing);
  }
  final state = TfliteAsset.inspect(bytes);
  if (state != AssetState.loaded) return WindowModelLoad(state);
  try {
    final interpreter = Interpreter.fromBuffer(bytes,
        options: InterpreterOptions()..threads = 1);
    if (!_isFloat(interpreter)) {
      interpreter.close();
      return const WindowModelLoad(AssetState.unsupportedIo);
    }
    return WindowModelLoad(AssetState.loaded, _TfliteWindowModel(interpreter));
  } catch (_) {
    return const WindowModelLoad(AssetState.invalid);
  }
}

bool _isFloat(Interpreter interpreter) =>
    interpreter.getInputTensors().every((t) => t.type == TensorType.float32) &&
    interpreter.getOutputTensors().every((t) => t.type == TensorType.float32);

class _TfliteWindowModel implements WindowModel {
  _TfliteWindowModel(this._interpreter);

  final Interpreter _interpreter;

  @override
  List<List<double>>? run(List<List<double>> window) {
    try {
      final input = [
        [
          for (var t = 0; t < 20; t++)
            t < window.length ? window[t] : List<double>.filled(13, 0.0),
        ],
      ];
      final outputs = _interpreter.getOutputTensors();
      final buffers = [for (final t in outputs) _zeros(t.shape)];
      _interpreter.runForMultipleInputs(
        [input],
        {for (var i = 0; i < buffers.length; i++) i: buffers[i]},
      );
      return [for (final b in buffers) _flatten(b)];
    } catch (_) {
      return null;
    }
  }

  @override
  void close() => _interpreter.close();

  static Object _zeros(List<int> shape) => shape.length <= 1
      ? List<double>.filled(shape.isEmpty ? 1 : shape.first, 0.0)
      : List.generate(shape.first, (_) => _zeros(shape.sublist(1)));

  static List<double> _flatten(Object tensor) {
    if (tensor is List<double>) return tensor;
    return [for (final part in tensor as List) ..._flatten(part as Object)];
  }
}
