import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/motion/activity_mode.dart';

void main() {
  test('requires repeated activity evidence before changing mode', () {
    final classifier = ActivityModeClassifier(requiredObservations: 2);

    expect(classifier.add(ActivityObservation.walking), ActivityMode.unknown);
    expect(classifier.add(ActivityObservation.inVehicle), ActivityMode.unknown);
    expect(classifier.add(ActivityObservation.inVehicle), ActivityMode.car);
    expect(classifier.add(ActivityObservation.walking), ActivityMode.car);
    expect(classifier.add(ActivityObservation.walking), ActivityMode.pedestrian);
  });

  test('maps bicycle separately and disables vehicle constraints on foot', () {
    expect(ActivityMode.bicycle.vehicleConstraintsAllowed, isTrue);
    expect(ActivityMode.pedestrian.vehicleConstraintsAllowed, isFalse);
    expect(ActivityMode.running.vehicleConstraintsAllowed, isFalse);
    expect(ActivityMode.still.vehicleConstraintsAllowed, isFalse);
  });
}
