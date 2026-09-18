import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/utils/geo_format.dart';

void main() {
  test('northern/eastern hemispheres', () {
    expect(formatLatitude(19.45), '19.4500°N');
    expect(formatLongitude(72.81), '72.8100°E');
  });

  test('western longitude is shown as W, not a negative east value', () {
    expect(formatLongitude(-122.084), '122.0840°W');
  });

  test('southern latitude is shown as S', () {
    expect(formatLatitude(-33.8688), '33.8688°S');
  });

  test('digits are configurable', () {
    expect(formatLatitude(28.639012, digits: 5), '28.63901°N');
  });
}
