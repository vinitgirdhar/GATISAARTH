import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/position_share.dart';

void main() {
  test('a dead-reckoned position carries its radius and its age', () {
    final text = positionShareText(
      latitude: 28.613912,
      longitude: 77.209021,
      marginM: 34.6,
      deadReckoning: true,
      sinceGnssLost: const Duration(seconds: 80),
      at: DateTime(2026, 9, 24, 7, 5),
    );
    expect(text, contains('07:05: 28.61391, 77.20902'));
    expect(text, contains('± 35 m'));
    expect(text, contains('GNSS lost 1 min 20 s ago'));
    expect(text, contains('mlat=28.61391&mlon=77.20902'));
  });

  test('a live fix says so, and an unknown margin is never invented', () {
    final text = positionShareText(
      latitude: 1,
      longitude: 2,
      marginM: null,
      deadReckoning: false,
      sinceGnssLost: Duration.zero,
      at: DateTime(2026),
    );
    expect(text, contains('live GNSS fix'));
    expect(text, contains('uncertainty unknown'));
  });
}
