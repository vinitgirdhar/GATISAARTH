import 'dart:async';

import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:gatisaarth/core/platform/location/live_location_service.dart';

/// Scriptable [LocationGateway] for tests.
class FakeLocationGateway implements LocationGateway {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission permissionAfterRequest = LocationPermission.whileInUse;
  GnssFix? lastKnown;
  int permissionRequests = 0;

  /// When set, [checkPermission] blocks until it completes (models a slow
  /// platform call so tests can pause/resume mid-evaluation).
  Completer<LocationPermission>? permissionGate;
  final serviceChanges = StreamController<bool>.broadcast();
  final fixController = StreamController<GnssFix>.broadcast();

  bool get hasFixListener => fixController.hasListener;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Stream<bool> serviceEnabledChanges() => serviceChanges.stream;

  @override
  Future<LocationPermission> checkPermission() async {
    final gate = permissionGate;
    if (gate == null) return permission;
    return await gate.future;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    permission = permissionAfterRequest;
    return permission;
  }

  @override
  Future<GnssFix?> lastKnownFix() async => lastKnown;

  @override
  Stream<GnssFix> fixes() => fixController.stream;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<bool> openAppSettings() async => true;
}

/// Let queued microtasks/stream events run.
Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
