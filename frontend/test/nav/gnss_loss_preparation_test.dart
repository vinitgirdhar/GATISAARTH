import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/outage/gnss_loss_preparation.dart';

void main() {
  group('GnssLossPreparation', () {
    test('arms within the prepare distance, not inside', () {
      final prep = GnssLossPreparation();
      prep.updateTunnel(distanceM: 500, inside: false);
      expect(prep.isActive, isTrue);
    });

    test('stays disarmed beyond the prepare distance', () {
      final prep = GnssLossPreparation();
      prep.updateTunnel(distanceM: 900, inside: false);
      expect(prep.isActive, isFalse);
    });

    test('disarms and drops the snapshot once inside the tunnel', () {
      final prep = GnssLossPreparation();
      final now = DateTime(2026, 1, 1);
      prep.updateTunnel(distanceM: 200, inside: false);
      prep.capture(
          speedMps: 20, headingDeg: 90, lat: 1, lon: 2, now: now, courseDeg: 90);
      expect(prep.preLockState, isNotNull);

      prep.updateTunnel(distanceM: 0, inside: true);
      expect(prep.isActive, isFalse);
      expect(prep.preLockState, isNull);
    });

    test('disarms when the tunnel is gone (passed or route diverged)', () {
      final prep = GnssLossPreparation();
      prep.updateTunnel(distanceM: 300, inside: false);
      expect(prep.isActive, isTrue);
      prep.updateTunnel(distanceM: null, inside: false);
      expect(prep.isActive, isFalse);
    });

    test('capture is a no-op while not armed', () {
      final prep = GnssLossPreparation();
      prep.capture(
          speedMps: 20,
          headingDeg: 90,
          lat: 1,
          lon: 2,
          now: DateTime(2026, 1, 1));
      expect(prep.preLockState, isNull);
    });

    test('seedAt returns the snapshot while fresh, null once stale', () {
      final prep = GnssLossPreparation();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      prep.updateTunnel(distanceM: 400, inside: false);
      prep.capture(speedMps: 15, headingDeg: 45, lat: 10, lon: 20, now: t0);

      final fresh = prep.seedAt(t0.add(const Duration(seconds: 3)));
      expect(fresh, isNotNull);
      expect(fresh!.speedMps, 15);

      final stale = prep.seedAt(t0.add(const Duration(seconds: 30)));
      expect(stale, isNull);
    });

    test('later good captures overwrite the earlier snapshot', () {
      final prep = GnssLossPreparation();
      final t0 = DateTime(2026, 1, 1);
      prep.updateTunnel(distanceM: 400, inside: false);
      prep.capture(speedMps: 10, headingDeg: 0, lat: 1, lon: 1, now: t0);
      prep.capture(
          speedMps: 12,
          headingDeg: 5,
          lat: 1.001,
          lon: 1.001,
          now: t0.add(const Duration(seconds: 1)));
      expect(prep.preLockState!.speedMps, 12);
    });
  });

  group('SpeedStdWindow', () {
    test('null with fewer than two samples', () {
      final w = SpeedStdWindow();
      expect(w.stdMps, isNull);
      w.add(DateTime(2026, 1, 1), 10);
      expect(w.stdMps, isNull);
    });

    test('zero for a constant speed', () {
      final w = SpeedStdWindow();
      final t0 = DateTime(2026, 1, 1);
      for (var i = 0; i < 5; i++) {
        w.add(t0.add(Duration(seconds: i)), 10);
      }
      expect(w.stdMps, closeTo(0, 1e-9));
    });

    test('drops samples outside the window', () {
      final w = SpeedStdWindow(windowMax: const Duration(seconds: 5));
      final t0 = DateTime(2026, 1, 1);
      w.add(t0, 100); // will fall out of the window
      w.add(t0.add(const Duration(seconds: 6)), 10);
      w.add(t0.add(const Duration(seconds: 7)), 10);
      expect(w.stdMps, closeTo(0, 1e-9));
    });

    test('positive for varying speed', () {
      final w = SpeedStdWindow();
      final t0 = DateTime(2026, 1, 1);
      w.add(t0, 10);
      w.add(t0.add(const Duration(seconds: 1)), 20);
      expect(w.stdMps, greaterThan(0));
    });
  });
}
