import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/model/nav_snapshot.dart';
import 'package:gatisaarth/features/navigation_engine/domain/navigation_safety.dart';

TrustInput _input({
  bool hadFix = true,
  bool locationLive = true,
  double secondsSinceLastFix = 0,
  double? uncertaintyM = 8,
  double? uncertaintyGrowthMPerS,
  bool engineLeading = false,
  NavIntegrity integrity = NavIntegrity.high,
  bool roadLocked = false,
  double? gnssAccuracyM = 8,
}) =>
    TrustInput(
      hadFix: hadFix,
      locationLive: locationLive,
      secondsSinceLastFix: secondsSinceLastFix,
      uncertaintyM: uncertaintyM,
      uncertaintyGrowthMPerS: uncertaintyGrowthMPerS,
      engineLeading: engineLeading,
      integrity: integrity,
      roadLocked: roadLocked,
      gnssAccuracyM: gnssAccuracyM,
    );

void main() {
  group('classifyRaw (table-driven)', () {
    final cases = <String, (TrustInput, TrustLevel)>{
      'no fix yet -> waiting, not RED or GREEN': (
        _input(hadFix: false, uncertaintyM: null, gnssAccuracyM: null),
        TrustLevel.waiting,
      ),
      'no fix yet, even with stray numbers -> waiting': (
        _input(hadFix: false, uncertaintyM: 5, integrity: NavIntegrity.invalid),
        TrustLevel.waiting,
      ),
      'live, accurate, high integrity -> GREEN': (
        _input(
          locationLive: true,
          secondsSinceLastFix: 0,
          uncertaintyM: 6,
          integrity: NavIntegrity.high,
          gnssAccuracyM: 6,
        ),
        TrustLevel.green,
      ),
      'engine leading on live GNSS with small sigma -> GREEN': (
        _input(
          locationLive: true,
          engineLeading: true,
          uncertaintyM: 10,
          integrity: NavIntegrity.high,
          gnssAccuracyM: 90, // ignored while the engine leads
        ),
        TrustLevel.green,
      ),
      'short outage, modest sigma -> AMBER': (
        _input(
          locationLive: false,
          secondsSinceLastFix: 5,
          uncertaintyM: 9,
          integrity: NavIntegrity.medium,
        ),
        TrustLevel.amber,
      ),
      'road-locked outage stays AMBER': (
        _input(
          locationLive: false,
          secondsSinceLastFix: 20,
          uncertaintyM: 15,
          integrity: NavIntegrity.medium,
          roadLocked: true,
        ),
        TrustLevel.amber,
      ),
      'outage with sigma past the AMBER ceiling -> ORANGE': (
        _input(
          locationLive: false,
          secondsSinceLastFix: 40,
          uncertaintyM: 90,
          integrity: NavIntegrity.medium,
        ),
        TrustLevel.orange,
      ),
      'low integrity -> ORANGE even with tiny sigma': (
        _input(
          locationLive: false,
          secondsSinceLastFix: 3,
          uncertaintyM: 5,
          integrity: NavIntegrity.low,
        ),
        TrustLevel.orange,
      ),
      'live but GNSS accuracy poor -> ORANGE': (
        _input(
          locationLive: true,
          secondsSinceLastFix: 0,
          uncertaintyM: 40,
          integrity: NavIntegrity.high,
          gnssAccuracyM: 65,
        ),
        TrustLevel.orange,
      ),
      'uncertainty growing fast -> ORANGE': (
        _input(
          locationLive: false,
          secondsSinceLastFix: 10,
          uncertaintyM: 20,
          uncertaintyGrowthMPerS: 5,
          integrity: NavIntegrity.medium,
        ),
        TrustLevel.orange,
      ),
      'integrity invalid -> RED even if sigma is small': (
        _input(
          locationLive: false,
          secondsSinceLastFix: 2,
          uncertaintyM: 3,
          integrity: NavIntegrity.invalid,
        ),
        TrustLevel.red,
      ),
      'sigma past the hard limit -> RED': (
        _input(
          locationLive: false,
          secondsSinceLastFix: 60,
          uncertaintyM: 500,
          integrity: NavIntegrity.low,
        ),
        TrustLevel.red,
      ),
      'no usable sigma at all -> RED': (
        _input(
          locationLive: false,
          secondsSinceLastFix: 30,
          uncertaintyM: null,
          integrity: NavIntegrity.medium,
        ),
        TrustLevel.red,
      ),
      'dead reckoning far too long -> RED': (
        _input(
          locationLive: false,
          secondsSinceLastFix: 400,
          uncertaintyM: 40, // still under the hard sigma limit
          integrity: NavIntegrity.medium,
        ),
        TrustLevel.red,
      ),
    };

    cases.forEach((name, spec) {
      final (input, expected) = spec;
      test(name, () => expect(classifyRaw(input), expected));
    });
  });

  group('TrustAssessment content', () {
    test('RED sets limited and a coarse display precision', () {
      final a = NavigationSafetyController().update(
        _input(integrity: NavIntegrity.invalid),
        DateTime(2026, 1, 1),
      );
      expect(a.level, TrustLevel.red);
      expect(a.limited, isTrue);
      expect(a.displayPrecisionM, isNotNull);
    });

    test('never says "spoofing"', () {
      final a = NavigationSafetyController().update(
        _input(
          locationLive: false,
          secondsSinceLastFix: 3,
          uncertaintyM: 5,
          integrity: NavIntegrity.low,
        ),
        DateTime(2026, 1, 1),
      );
      expect(a.reason.toLowerCase(), isNot(contains('spoof')));
      expect(a.reason, contains('Navigation integrity low'));
    });

    test('waiting is neither limited nor a made-up number', () {
      expect(TrustAssessment.waitingForFix.limited, isFalse);
      expect(TrustAssessment.waitingForFix.displayPrecisionM, isNull);
    });
  });

  group('formatUncertainty', () {
    test('shows -- when there is nothing to measure', () {
      expect(formatUncertainty(TrustAssessment.waitingForFix, null), '--');
    });

    test('rounds up to the display precision, normally with ±', () {
      const green = TrustAssessment(
        level: TrustLevel.green,
        headline: 'Position reliable',
        reason: 'x',
        limited: false,
        displayPrecisionM: 1,
      );
      expect(formatUncertainty(green, 4.2), '± 5 m');
    });

    test('shows > once limited, never a crisp number', () {
      const red = TrustAssessment(
        level: TrustLevel.red,
        headline: 'Position unreliable',
        reason: 'x',
        limited: true,
        displayPrecisionM: 50,
      );
      expect(formatUncertainty(red, 301), '> 350 m');
    });
  });

  group('NavigationSafetyController hysteresis', () {
    test('escalation from GREEN to RED is immediate', () {
      final controller = NavigationSafetyController();
      final t0 = DateTime(2026, 1, 1);
      expect(controller.update(_input(), t0).level, TrustLevel.green);
      final redInput = _input(integrity: NavIntegrity.invalid);
      expect(
        controller.update(redInput, t0.add(const Duration(milliseconds: 100)))
            .level,
        TrustLevel.red,
      );
    });

    test('de-escalation only sticks after the delay holds', () {
      final controller = NavigationSafetyController(
        deescalateDelay: const Duration(seconds: 4),
      );
      final t0 = DateTime(2026, 1, 1);
      final badInput = _input(integrity: NavIntegrity.invalid);
      final goodInput = _input();

      expect(controller.update(badInput, t0).level, TrustLevel.red);

      // A single good tick shortly after must NOT flip it back yet.
      final t1 = t0.add(const Duration(seconds: 1));
      expect(controller.update(goodInput, t1).level, TrustLevel.red);

      // Still within the delay window.
      final t2 = t0.add(const Duration(seconds: 3));
      expect(controller.update(goodInput, t2).level, TrustLevel.red);

      // A worse tick in between resets the "better" clock.
      final t3 = t0.add(const Duration(seconds: 3, milliseconds: 500));
      expect(controller.update(badInput, t3).level, TrustLevel.red);
      final t4 = t3.add(const Duration(seconds: 1));
      expect(controller.update(goodInput, t4).level, TrustLevel.red);

      // Now the good condition has held for the full delay from t4.
      final t5 = t4.add(const Duration(seconds: 4, milliseconds: 1));
      expect(controller.update(goodInput, t5).level, TrustLevel.green);
    });

    test('waiting transitions are immediate in both directions', () {
      final controller = NavigationSafetyController();
      final t0 = DateTime(2026, 1, 1);
      expect(
        controller.update(_input(hadFix: false, uncertaintyM: null), t0).level,
        TrustLevel.waiting,
      );
      expect(
        controller
            .update(_input(), t0.add(const Duration(milliseconds: 50)))
            .level,
        TrustLevel.green,
      );
    });
  });
}
