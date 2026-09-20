import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:vector_map_tiles_pmtiles/src/themes/v4/_package.dart' as v4;
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;
import 'package:gatisaarth/features/navigation_ui/presentation/widgets/basemap_style.dart';

/// Parses with the renderer's own console logger and returns what it warned
/// about: an unsupported expression means a layer it silently drops.
List<String> _parseWarnings(void Function(vtr.Logger logger) parse) {
  final lines = <String>[];
  runZoned(
    () => parse(const vtr.Logger.console()),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines.where((l) => l.startsWith('WARN')).toList();
}

List<Map<String, Object>> _symbols(List<Map<String, Object>> layers) =>
    [for (final l in layers) if (l['type'] == 'symbol') l];

void main() {
  test('the renderer understands every rule of the light style', () {
    expect(_parseWarnings((log) => BasemapStyle.light(logger: log)), isEmpty);
  });

  test('...and of the dark style, and of both overlay variants', () {
    expect(_parseWarnings((log) => BasemapStyle.dark(logger: log)), isEmpty);
    expect(
      _parseWarnings((log) => BasemapStyle.light(overlay: true, logger: log)),
      isEmpty,
    );
    expect(
      _parseWarnings((log) => BasemapStyle.dark(overlay: true, logger: log)),
      isEmpty,
    );
  });

  test('every style has its own id, and a version to invalidate old pictures',
      () {
    final themes = [
      BasemapStyle.light(),
      BasemapStyle.dark(),
      BasemapStyle.light(overlay: true),
      BasemapStyle.dark(overlay: true),
    ];
    // The renderer caches finished tiles on disk under this id: two styles
    // sharing it serve each other's pictures (light tiles in dark mode).
    expect(themes.map((t) => t.id).toSet().length, themes.length);
    for (final t in themes) {
      expect(t.id, isNot('default'));
      expect(t.version, '${BasemapStyle.revision}');
    }
  });

  test('the original Protomaps label rules were the problem', () {
    // Pins why the adapter exists: if a package upgrade makes the raw style
    // parse cleanly this fails, and the adapter can be dropped.
    final warnings = _parseWarnings(
      (log) => ProtomapsThemes(logger: log).build(v4.themeLight),
    );
    expect(warnings, isNotEmpty);
  });

  test('every label layer is kept, with a name expression it can read', () {
    final original = _symbols(v4.themeLight);
    final adapted = _symbols(BasemapStyle.adapt(v4.themeLight));
    expect(adapted.map((l) => l['id']), original.map((l) => l['id']));
    expect(adapted, isNotEmpty);
    for (final layer in adapted) {
      final layout = layer['layout']! as Map;
      expect(layout['text-field'], [
        'coalesce',
        ['get', 'name:en'],
        ['get', 'name'],
      ], reason: '${layer['id']}');
      expect(layout['text-font'], ['Noto Sans Regular']);
      expect(layout.containsKey('icon-image'), isFalse,
          reason: 'no sprite sheet ships');
    }
  });

  test('road, place and water names are all there', () {
    final ids = _symbols(BasemapStyle.adapt(v4.themeLight))
        .map((l) => l['id'] as String)
        .toSet();
    expect(
      ids,
      containsAll([
        'roads_labels_major',
        'roads_labels_minor',
        'places_locality',
        'places_subplace',
        'places_region',
        'places_country',
        'water_waterway_label',
      ]),
    );
  });

  test('shapes are untouched: only symbol layers change', () {
    final original = v4.themeLight;
    final adapted = BasemapStyle.adapt(original);
    expect(adapted.length, original.length);
    for (var i = 0; i < original.length; i++) {
      if (original[i]['type'] == 'symbol') continue;
      expect(adapted[i], original[i], reason: '${original[i]['id']}');
    }
  });

  test('adapting never edits the shared style constants', () {
    final before = _symbols(v4.themeLight).first['layout'].toString();
    BasemapStyle.adapt(v4.themeLight);
    BasemapStyle.adapt(v4.themeDark, overlay: true);
    expect(_symbols(v4.themeLight).first['layout'].toString(), before);
  });

  test('an overlay has no background, a base map has one', () {
    bool hasBackground(List<Map<String, Object>> l) =>
        l.any((e) => e['type'] == 'background');
    expect(hasBackground(BasemapStyle.adapt(v4.themeLight)), isTrue);
    expect(hasBackground(BasemapStyle.adapt(v4.themeDark)), isTrue);
    expect(hasBackground(BasemapStyle.adapt(v4.themeLight, overlay: true)),
        isFalse);
    expect(hasBackground(BasemapStyle.adapt(v4.themeDark, overlay: true)),
        isFalse);
  });

  test('label colours stay plain colours the renderer can use', () {
    for (final layer in _symbols(BasemapStyle.adapt(v4.themeDark))) {
      final color = (layer['paint']! as Map)['text-color'];
      expect(color, isA<String>(), reason: '${layer['id']}');
      expect(color as String, startsWith('#'));
    }
  });
}
