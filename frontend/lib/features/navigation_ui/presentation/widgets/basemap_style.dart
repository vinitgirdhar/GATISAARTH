import 'dart:convert';

import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;
// ignore: implementation_imports
import 'package:vector_map_tiles_pmtiles/src/themes/v4/_package.dart' as v4;

/// Protomaps' own v4 map styles, adjusted so the on-device renderer can draw
/// their labels.
///
/// The styles' *shapes* (roads, buildings, water, parks) are used untouched.
/// Their *label* rules use MapLibre expressions (`format`, `case` over a
/// `is-supported-script` test, `in` against a literal list) that the renderer
/// cannot parse, and a layer it cannot parse is silently dropped - the map came
/// out with no street, place or water names at all. This keeps the same label
/// layers, colours, sizes and zoom ranges, and replaces only the expressions
/// with equivalent ones it understands: the English name when OpenStreetMap has
/// one, otherwise the local name (Devanagari included: Flutter draws it with the
/// phone's own fonts).
class BasemapStyle {
  const BasemapStyle._();

  /// English name first, then whatever the place is called locally.
  static const List<Object> _label = [
    'coalesce',
    ['get', 'name:en'],
    ['get', 'name'],
  ];

  static const List<Object> _font = ['Noto Sans Regular'];

  /// Bumped whenever the styling changes. The renderer keeps finished tile
  /// pictures on disk under the style's id and version, so without this a new
  /// style would keep showing the old pictures.
  static const int revision = 2;

  /// The light style.
  static vtr.Theme light({bool overlay = false, vtr.Logger? logger}) => _build(
        v4.themeLight,
        name: 'light',
        overlay: overlay,
        logger: logger,
      );

  /// The dark style.
  static vtr.Theme dark({bool overlay = false, vtr.Logger? logger}) => _build(
        v4.themeDark,
        name: 'dark',
        overlay: overlay,
        logger: logger,
      );

  /// [overlay]: a style without its background layer, for archives drawn over a
  /// base map (an empty tile must stay transparent).
  ///
  /// Every style gets its own id. The renderer keys its tile-picture cache, and
  /// its check for "has the theme changed", on the id; `ProtomapsThemes.build`
  /// gives them all the same one (`default`), so light and dark tiles were
  /// served for each other and a brightness flip never redrew the map.
  static vtr.Theme _build(
    List<Map<String, Object>> layers, {
    required String name,
    required bool overlay,
    vtr.Logger? logger,
  }) =>
      vtr.ThemeReader(logger: logger).read({
        'version': 8,
        'id': 'gatisaarth-$name-${overlay ? 'overlay' : 'base'}',
        'metadata': {'version': revision},
        'layers': adapt(layers, overlay: overlay),
      });

  /// The adapted layer list. Public so tests can check what the renderer is
  /// given.
  static List<Map<String, Object>> adapt(
    List<Map<String, Object>> layers, {
    bool overlay = false,
  }) {
    return [
      for (final source in layers)
        if (!(overlay && source['type'] == 'background'))
          _adaptLayer(_copy(source)),
    ];
  }

  static Map<String, Object> _copy(Map<String, Object> layer) =>
      Map<String, Object>.from(jsonDecode(jsonEncode(layer)) as Map);

  static Map<String, Object> _adaptLayer(Map<String, Object> layer) {
    if (layer['type'] != 'symbol') return layer;

    final layout = Map<String, Object>.from((layer['layout'] as Map?) ?? {});
    final paint = Map<String, Object>.from((layer['paint'] as Map?) ?? {});

    layout['text-field'] = _label;
    layout['text-font'] = _font;
    // Icons need a sprite sheet the app does not carry.
    for (final key in const [
      'icon-image',
      'icon-size',
      'icon-padding',
      'text-variable-anchor',
      'text-offset',
      'text-radial-offset',
    ]) {
      layout.remove(key);
    }

    // Sizes and colours that switch on a feature property: keep the zoom ramp,
    // drop the per-feature branch.
    final size = layout['text-size'];
    if (size != null && _usesUnsupported(size)) {
      layout['text-size'] = _rampFor(layer['id'] as String);
    }
    final anchor = layout['text-anchor'];
    if (anchor is List) layout['text-anchor'] = 'center';

    final color = paint['text-color'];
    if (color is List) paint['text-color'] = _firstColor(color) ?? '#666666';

    if (layer['id'] == 'pois') {
      // The style's filter compares against `min_zoom` per feature; a plain
      // minimum zoom does the same job for the few kinds it labels.
      layer['filter'] = const [
        'in',
        'kind',
        'beach',
        'forest',
        'marina',
        'park',
        'peak',
        'zoo',
      ];
      layer['minzoom'] = 14;
      layout['text-anchor'] = 'center';
    }

    layer['layout'] = layout;
    layer['paint'] = paint;
    return layer;
  }

  /// Whether an expression uses anything other than a number or a zoom
  /// interpolation of numbers.
  static bool _usesUnsupported(Object value) {
    if (value is! List) return false;
    return value.any((e) =>
        e is List && (e.first == 'case' || e.first == 'get' || _usesUnsupported(e)));
  }

  /// Zoom-based text size for the layers whose own ramp branched per feature.
  static List<Object> _rampFor(String id) => switch (id) {
        'places_country' => const [
            'interpolate', ['linear'], ['zoom'], 2, 9, 6, 13, //
          ],
        'places_locality' => const [
            'interpolate', ['linear'], ['zoom'], 4, 10, 10, 14, 14, 18, //
          ],
        _ => const [
            'interpolate', ['linear'], ['zoom'], 3, 10, 10, 12, //
          ],
      };

  /// The first colour literal in a `case` expression: `["case", test, "#fff",
  /// ...]` -> `"#fff"`.
  static String? _firstColor(List<Object?> expression) {
    for (final e in expression) {
      if (e is String && e.startsWith('#')) return e;
      if (e is List) {
        final nested = _firstColor(e);
        if (nested != null) return nested;
      }
    }
    return null;
  }
}
