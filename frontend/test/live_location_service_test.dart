import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:gatisaarth/core/platform/location/live_location_service.dart';

import 'support/fake_location_gateway.dart';

const _fix = GnssFix(
  latitude: 19.45,
  longitude: 72.81,
  altitude: 12,
  accuracy: 6,
  speed: 0,
);

void main() {
  late FakeLocationGateway gateway;
  late DateTime now;
  late LiveLocationService service;

  setUp(() {
    gateway = FakeLocationGateway();
    now = DateTime(2026, 9, 18, 12);
    service = LiveLocationService(
      gateway: gateway,
      clock: () => now,
      errorRetryDelay: Duration.zero,
    );
  });

  tearDown(() => service.dispose());

  test('starts in initializing, then searching once permitted', () async {
    expect(service.status, LocationStatus.initializing);
    await service.start();
    expect(service.status, LocationStatus.searching);
    expect(gateway.hasFixListener, isTrue);
  });

  test('a real fix makes it live and exposes the fix', () async {
    await service.start();
    gateway.fixController.add(_fix);
    await settle();
    expect(service.status, LocationStatus.live);
    expect(service.isLive, isTrue);
    expect(service.lastLiveFix?.latitude, 19.45);
    expect(service.hasBeenLive, isTrue);
  });

  test('cached last-known position never counts as live', () async {
    gateway.lastKnown = _fix;
    await service.start();
    expect(service.status, LocationStatus.searching);
    expect(service.isLive, isFalse);
    expect(service.lastLiveFix, isNull);
    expect(service.lastKnownFix?.longitude, 72.81);
    expect(service.hasBeenLive, isFalse);
  });

  test('goes stale after staleAfter without a fix, recovers on next fix',
      () async {
    await service.start();
    gateway.fixController.add(_fix);
    await settle();

    now = now.add(const Duration(seconds: 5));
    service.checkStaleness();
    expect(service.status, LocationStatus.live);

    now = now.add(const Duration(seconds: 2));
    service.checkStaleness();
    expect(service.status, LocationStatus.stale);

    gateway.fixController.add(_fix);
    await settle();
    expect(service.status, LocationStatus.live);
  });

  test('location service off reports serviceOff and recovers when enabled',
      () async {
    gateway.serviceEnabled = false;
    await service.start();
    expect(service.status, LocationStatus.serviceOff);
    expect(gateway.hasFixListener, isFalse);

    gateway.serviceEnabled = true;
    gateway.serviceChanges.add(true);
    await settle();
    expect(service.status, LocationStatus.searching);
    expect(gateway.hasFixListener, isTrue);
  });

  test('denied permission is requested once and reported when refused',
      () async {
    gateway.permission = LocationPermission.denied;
    gateway.permissionAfterRequest = LocationPermission.denied;
    await service.start();
    expect(gateway.permissionRequests, 1);
    expect(service.status, LocationStatus.permissionDenied);

    await service.recheck();
    expect(gateway.permissionRequests, 1, reason: 'recheck must not re-prompt');
  });

  test('denied then granted proceeds to searching', () async {
    gateway.permission = LocationPermission.denied;
    gateway.permissionAfterRequest = LocationPermission.whileInUse;
    await service.start();
    expect(service.status, LocationStatus.searching);
  });

  test('permanently denied is reported as blocked', () async {
    gateway.permission = LocationPermission.deniedForever;
    await service.start();
    expect(service.status, LocationStatus.permissionBlocked);
    expect(gateway.hasFixListener, isFalse);
  });

  test('pause releases the GPS subscription; resume restores it', () async {
    await service.start();
    gateway.fixController.add(_fix);
    await settle();
    expect(service.status, LocationStatus.live);

    await service.pause();
    expect(gateway.hasFixListener, isFalse);
    expect(service.status, LocationStatus.searching);

    await service.resume();
    expect(gateway.hasFixListener, isTrue);
    gateway.fixController.add(_fix);
    await settle();
    expect(service.status, LocationStatus.live);
  });

  test('stream error triggers a re-check instead of dying silently', () async {
    await service.start();
    gateway.serviceEnabled = false;
    gateway.fixController.addError(StateError('location switched off'));
    await settle();
    expect(service.status, LocationStatus.serviceOff);
  });

  test('pausing mid-check never opens the GPS stream in the background',
      () async {
    gateway.permissionGate = Completer<LocationPermission>();
    final starting = service.start(); // blocked inside checkPermission
    await settle();
    await service.pause();
    gateway.permissionGate!.complete(LocationPermission.whileInUse);
    await starting;
    expect(gateway.hasFixListener, isFalse);

    await service.resume();
    expect(gateway.hasFixListener, isTrue);
  });

  test('a stream that keeps failing is retried with growing delays', () async {
    service.dispose();
    service = LiveLocationService(
      gateway: gateway,
      clock: () => now,
      errorRetryDelay: const Duration(milliseconds: 20),
    );
    await service.start();

    final clock = Stopwatch()..start();
    for (var i = 0; i < 3; i++) {
      gateway.fixController.addError(StateError('boom'));
      await settle();
      while (!gateway.hasFixListener) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }
    // 20 + 40 + 80 ms; a fixed delay would take only 60 ms.
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(135));
  });

  test('dispose stops listening and further events are ignored', () async {
    await service.start();
    service.dispose();
    expect(gateway.hasFixListener, isFalse);
    gateway.fixController.add(_fix);
    await settle();
    expect(service.status, LocationStatus.searching);
  });
}
