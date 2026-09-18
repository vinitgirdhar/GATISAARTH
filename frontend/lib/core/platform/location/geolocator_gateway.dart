import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'live_location_service.dart';

/// Production [LocationGateway] backed by the geolocator plugin.
///
/// Navigation-grade settings: high-accuracy priority, no distance filter and
/// a 1 s interval, so a stationary phone still reports a fix every second
/// (needed to tell "stationary" apart from "GNSS lost").
class GeolocatorGateway implements LocationGateway {
  const GeolocatorGateway();

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        // Sea-level altitude; the default is ellipsoidal (tens of metres off).
        useMSLAltitude: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Stream<bool> serviceEnabledChanges() => Geolocator.getServiceStatusStream()
      .map((status) => status == ServiceStatus.enabled);

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<GnssFix?> lastKnownFix() async {
    final position = await Geolocator.getLastKnownPosition();
    return position == null ? null : _toFix(position);
  }

  @override
  Stream<GnssFix> fixes() =>
      Geolocator.getPositionStream(locationSettings: _settings()).map(_toFix);

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  static GnssFix _toFix(Position p) => GnssFix(
        latitude: p.latitude,
        longitude: p.longitude,
        altitude: p.altitude,
        accuracy: p.accuracy,
        speed: p.speed < 0 ? 0 : p.speed,
        isMocked: p.isMocked,
      );
}
