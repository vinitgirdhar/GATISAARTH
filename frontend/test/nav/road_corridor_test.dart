import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/map/map_matcher.dart';

import 'map_matching_test.dart' show at, parallelRoads;

void main() {
  test('ambiguous HMM candidates retain drawable top-k road corridors', () {
    final matcher = MapMatcher(graph: parallelRoads());
    final point = at(400, 12.5);

    matcher.update(
      lat: point[0],
      lon: point[1],
      sigmaM: 20,
      headingRad: 0,
      speedMps: 12,
    );
    final result = matcher.update(
      lat: at(430, 12.5)[0],
      lon: at(430, 12.5)[1],
      sigmaM: 20,
      headingRad: 0,
      speedMps: 12,
    )!;

    expect(result.snapped, isFalse);
    expect(result.candidates, hasLength(2));
    expect(result.candidates.first.corridorPolyline, hasLength(4));
    expect(result.candidates.last.corridorPolyline, hasLength(4));
    expect(result.candidates.first.posterior,
        greaterThanOrEqualTo(result.candidates.last.posterior));
    expect(
      result.candidates.first.corridorPolyline,
      isNot(equals(result.candidates.last.corridorPolyline)),
    );
  });
}
