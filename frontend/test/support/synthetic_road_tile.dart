import 'dart:typed_data';

import 'package:vector_tile/raw/raw_vector_tile.dart' as raw;

/// One feature of a hand-made `roads` layer.
///
/// [lines] are in tile units (0..extent); more than one makes it a
/// MultiLineString. [props] values are `String` or `bool`, like the Protomaps
/// properties they imitate (`kind`, `kind_detail`, `oneway`, `is_bridge`...).
class SynthRoad {
  const SynthRoad(this.lines, [this.props = const {}, this.brokenTags = false]);

  final List<List<(int, int)>> lines;
  final Map<String, Object> props;

  /// Points its tags at keys and values the layer does not have, the way a
  /// damaged tile would.
  final bool brokenTags;
}

int _zigZag(int v) => (v << 1) ^ (v >> 63);

/// MVT geometry commands: MoveTo to the first point, LineTo for the rest, the
/// cursor carrying on from line to line as the spec requires.
List<int> _encodeLines(List<List<(int, int)>> lines) {
  final out = <int>[];
  var cx = 0, cy = 0;
  for (final line in lines) {
    out
      ..add((1 & 7) | (1 << 3))
      ..add(_zigZag(line.first.$1 - cx))
      ..add(_zigZag(line.first.$2 - cy))
      ..add((2 & 7) | ((line.length - 1) << 3));
    cx = line.first.$1;
    cy = line.first.$2;
    for (final p in line.skip(1)) {
      out
        ..add(_zigZag(p.$1 - cx))
        ..add(_zigZag(p.$2 - cy));
      cx = p.$1;
      cy = p.$2;
    }
  }
  return out;
}

/// A vector tile whose only layer is [layer] (default `roads`).
Uint8List syntheticRoadTile(
  List<SynthRoad> roads, {
  int extent = 4096,
  String layer = 'roads',
}) {
  final keys = <String>[];
  final values = <raw.VectorTile_Value>[];
  final valueIndex = <Object, int>{};

  int keyOf(String k) {
    final i = keys.indexOf(k);
    if (i >= 0) return i;
    keys.add(k);
    return keys.length - 1;
  }

  int valueOf(Object v) => valueIndex.putIfAbsent(v, () {
        values.add(v is bool
            ? raw.VectorTile_Value(boolValue: v)
            : raw.VectorTile_Value(stringValue: v as String));
        return values.length - 1;
      });

  final features = [
    for (final r in roads)
      raw.VectorTile_Feature(
        type: raw.VectorTile_GeomType.LINESTRING,
        tags: r.brokenTags
            ? const [90, 91]
            : [
                for (final e in r.props.entries)
                  ...[keyOf(e.key), valueOf(e.value)],
              ],
        geometry: _encodeLines(r.lines),
      ),
  ];
  final tile = raw.VectorTile(layers: [
    raw.VectorTile_Layer(
      name: layer,
      version: 2,
      extent: extent,
      keys: keys,
      values: values,
      features: features,
    ),
  ]);
  return tile.writeToBuffer();
}
