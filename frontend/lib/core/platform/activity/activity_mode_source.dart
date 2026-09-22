import 'package:flutter/services.dart';

import '../../nav/motion/activity_mode.dart';

abstract interface class ActivityModeSource {
  Stream<ActivityObservation> get observations;
  Future<void> start();
  Future<void> stop();
}

class PlatformActivityModeSource implements ActivityModeSource {
  static const _events = EventChannel('com.gatisaarth.app/activity_updates');
  static const _control = MethodChannel('com.gatisaarth.app/activity_control');

  @override
  Stream<ActivityObservation> get observations =>
      _events.receiveBroadcastStream().map((event) {
        switch (event) {
          case 'inVehicle':
            return ActivityObservation.inVehicle;
          case 'bicycle':
            return ActivityObservation.bicycle;
          case 'walking':
            return ActivityObservation.walking;
          case 'running':
            return ActivityObservation.running;
          case 'still':
            return ActivityObservation.still;
          default:
            return ActivityObservation.unknown;
        }
      });

  @override
  Future<void> start() async {
    try {
      await _control.invokeMethod<void>('start');
    } on PlatformException {
      // Recognition is optional; permission denial or unavailable Play
      // Services must never prevent the navigation session from starting.
    } on MissingPluginException {
      // Non-Android platforms keep the manually selected profile.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _control.invokeMethod<void>('stop');
    } on PlatformException {
      // Best-effort teardown of an optional source.
    } on MissingPluginException {
      // No native activity source on this platform.
    }
  }
}

class NoopActivityModeSource implements ActivityModeSource {
  const NoopActivityModeSource();

  @override
  Stream<ActivityObservation> get observations => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
