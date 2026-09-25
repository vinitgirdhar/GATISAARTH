import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/features/about/presentation/engine_spec_screen.dart';

/// Serves the app's asset files straight from disk, immediately.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final file = File(key);
    if (!file.existsSync()) throw FlutterError('Unable to load asset: $key');
    return ByteData.sublistView(file.readAsBytesSync());
  }
}

void main() {
  test('the model card is built from the shipped model files', () async {
    final facts = (await ModelFacts.load(bundle: _DiskBundle()))!;
    expect(facts.version, 'v4.0.0');
    expect(facts.windowSamples, 20);
    expect(facts.rateHz, 10);
    expect(facts.features, 13);
    expect(facts.quantization, 'fp32');
    expect(
        facts.sizeBytes, File('assets/models/speed_estimator.tflite').lengthSync());
    expect(facts.sizeBytes, greaterThan(100000));
    expect(facts.speedMaeMps, isNotNull);
    expect(facts.parity, contains('PASSED'));
  });

  test('a missing metadata file gives no facts rather than an error', () async {
    final facts = await ModelFacts.load(bundle: _EmptyBundle());
    expect(facts, isNull);
  });
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future<ByteData>.error(FlutterError('no asset'));
}
