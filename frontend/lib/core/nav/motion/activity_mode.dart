enum ActivityObservation {
  inVehicle,
  bicycle,
  walking,
  running,
  still,
  unknown
}

enum ActivityMode { unknown, car, bicycle, pedestrian, running, still }

extension ActivityModeSafety on ActivityMode {
  bool get vehicleConstraintsAllowed =>
      this == ActivityMode.car || this == ActivityMode.bicycle;
}

class ActivityModeClassifier {
  // Android Activity Transition events are already debounced by Play Services.
  // Callers feeding raw, noisy samples can request extra hysteresis.
  ActivityModeClassifier({this.requiredObservations = 1})
      : assert(requiredObservations > 0);

  final int requiredObservations;
  ActivityMode _mode = ActivityMode.unknown;
  ActivityMode? _candidate;
  int _candidateCount = 0;

  ActivityMode get mode => _mode;

  ActivityMode add(ActivityObservation observation) {
    final next = _fromObservation(observation);
    if (next == ActivityMode.unknown || next == _mode) {
      _candidate = null;
      _candidateCount = 0;
      return _mode;
    }
    if (_candidate == next) {
      _candidateCount++;
    } else {
      _candidate = next;
      _candidateCount = 1;
    }
    if (_candidateCount >= requiredObservations) {
      _mode = next;
      _candidate = null;
      _candidateCount = 0;
    }
    return _mode;
  }

  static ActivityMode _fromObservation(ActivityObservation observation) {
    switch (observation) {
      case ActivityObservation.inVehicle:
        return ActivityMode.car;
      case ActivityObservation.bicycle:
        return ActivityMode.bicycle;
      case ActivityObservation.walking:
        return ActivityMode.pedestrian;
      case ActivityObservation.running:
        return ActivityMode.running;
      case ActivityObservation.still:
        return ActivityMode.still;
      case ActivityObservation.unknown:
        return ActivityMode.unknown;
    }
  }
}
