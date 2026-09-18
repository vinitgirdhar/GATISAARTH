import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/features/navigation_engine/domain/uncertainty_model.dart';

void main() {
  group('UncertaintyModel', () {
    test('a good GNSS fix gives high confidence', () {
      final e = UncertaintyModel.live(gnssAccuracyMeters: 5);
      expect(e.marginMeters, 5);
      expect(e.confidence, closeTo(0.967, 0.001));
    });

    test('margin never drops below the receiver floor', () {
      final e = UncertaintyModel.live(gnssAccuracyMeters: 0.4);
      expect(e.marginMeters, UncertaintyModel.minMarginMeters);
      expect(e.confidence, lessThanOrEqualTo(UncertaintyModel.maxConfidence));
    });

    test('confidence is clamped to the floor for very poor fixes', () {
      final e = UncertaintyModel.live(gnssAccuracyMeters: 5000);
      expect(e.confidence, UncertaintyModel.minConfidence);
    });

    test('multipath degradation lowers confidence', () {
      final clean = UncertaintyModel.live(gnssAccuracyMeters: 8);
      final canyon =
          UncertaintyModel.live(gnssAccuracyMeters: 8, degradeFactor: 3);
      expect(canyon.marginMeters, closeTo(24, 0.001));
      expect(canyon.confidence, lessThan(clean.confidence));
    });

    test('dead-reckoning margin grows with distance and with time', () {
      const base = Duration(seconds: 10);
      final near = UncertaintyModel.deadReckoning(
        accuracyAtLossMeters: 5,
        distanceSinceLossMeters: 50,
        sinceLoss: base,
      );
      final far = UncertaintyModel.deadReckoning(
        accuracyAtLossMeters: 5,
        distanceSinceLossMeters: 500,
        sinceLoss: base,
      );
      final later = UncertaintyModel.deadReckoning(
        accuracyAtLossMeters: 5,
        distanceSinceLossMeters: 50,
        sinceLoss: const Duration(seconds: 100),
      );
      expect(far.marginMeters, greaterThan(near.marginMeters));
      expect(later.marginMeters, greaterThan(near.marginMeters));
      expect(far.confidence, lessThan(near.confidence));
    });

    test('dead-reckoning margin follows the documented model', () {
      final e = UncertaintyModel.deadReckoning(
        accuracyAtLossMeters: 5,
        distanceSinceLossMeters: 200,
        sinceLoss: const Duration(seconds: 20),
      );
      // 5 + 0.05*200 + 0.15*20 = 18
      expect(e.marginMeters, closeTo(18, 0.001));
    });

    test('modelled drift stays inside the 10 percent acceptance bar', () {
      // Long outage at ~14 m/s (50 km/h) for 5 minutes.
      final distance = 14.0 * 300;
      final e = UncertaintyModel.deadReckoning(
        accuracyAtLossMeters: 5,
        distanceSinceLossMeters: distance,
        sinceLoss: const Duration(seconds: 300),
      );
      expect(e.marginMeters / distance, lessThan(0.10));
    });
  });

  group('OutageTracker', () {
    final t0 = DateTime(2026, 9, 18, 12);

    test('is inactive until an outage starts', () {
      final tracker = OutageTracker();
      tracker.update(outage: false, now: t0, accuracyMeters: 5);
      expect(tracker.isActive, isFalse);
      expect(tracker.elapsed(t0), Duration.zero);
    });

    test('captures start time and accuracy once; repeated updates are no-ops',
        () {
      final tracker = OutageTracker();
      tracker.update(outage: true, now: t0, accuracyMeters: 7);
      tracker.update(
        outage: true,
        now: t0.add(const Duration(seconds: 5)),
        accuracyMeters: 99,
      );
      expect(tracker.isActive, isTrue);
      expect(tracker.accuracyAtLossMeters, 7);
      expect(
        tracker.elapsed(t0.add(const Duration(seconds: 5))),
        const Duration(seconds: 5),
      );
    });

    test('accumulates distance only while active', () {
      final tracker = OutageTracker();
      tracker.addDistance(50);
      expect(tracker.distanceMeters, 0);
      tracker.update(outage: true, now: t0, accuracyMeters: 5);
      tracker.addDistance(12.5);
      tracker.addDistance(-3);
      tracker.addDistance(7.5);
      expect(tracker.distanceMeters, 20);
    });

    test('recovery resets everything', () {
      final tracker = OutageTracker();
      tracker.update(outage: true, now: t0, accuracyMeters: 5);
      tracker.addDistance(40);
      tracker.update(
        outage: false,
        now: t0.add(const Duration(seconds: 9)),
        accuracyMeters: 5,
      );
      expect(tracker.isActive, isFalse);
      expect(tracker.distanceMeters, 0);
    });

    test('estimate reflects tracked distance and time', () {
      final tracker = OutageTracker();
      tracker.update(outage: true, now: t0, accuracyMeters: 5);
      tracker.addDistance(200);
      final e = tracker.estimate(t0.add(const Duration(seconds: 20)));
      expect(e.marginMeters, closeTo(18, 0.001));
    });
  });
}
