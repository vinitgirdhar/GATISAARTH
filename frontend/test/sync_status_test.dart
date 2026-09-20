import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/sync_status.dart';

SyncStatus _status({
  bool sensors = true,
  bool model = true,
  LocationStatus location = LocationStatus.live,
  bool reacquiring = false,
}) =>
    syncStatusOf(
      sensorsLive: sensors,
      modelReady: model,
      location: location,
      reacquiring: reacquiring,
    );

void main() {
  test('everything ready means nothing is syncing', () {
    expect(_status().isSyncing, isFalse);
    expect(_status().done, SyncStatus.total);
  });

  test('a cold start walks sensors, then the model, then satellites', () {
    final cold = _status(
      sensors: false,
      model: false,
      location: LocationStatus.initializing,
    );
    expect(cold.phase, SyncPhase.sensors);
    expect(cold.label, 'Starting sensors');
    expect(cold.done, 0);

    final sensorsUp = _status(
      model: false,
      location: LocationStatus.initializing,
    );
    expect(sensorsUp.phase, SyncPhase.model);
    expect(sensorsUp.done, 1);

    final modelUp = _status(location: LocationStatus.searching);
    expect(modelUp.phase, SyncPhase.satellites);
    expect(modelUp.label, 'Finding satellites');
    expect(modelUp.done, 2);
  });

  test('the fix arriving finishes the sync', () {
    expect(_status(location: LocationStatus.live).isSyncing, isFalse);
  });

  test('settling onto a returned fix is a (re-)sync', () {
    final s = _status(reacquiring: true);
    expect(s.phase, SyncPhase.resync);
    expect(s.label, 'Re-syncing position');
  });

  test('an outage is not syncing: navigation is deliberately without GNSS',
      () {
    expect(_status(location: LocationStatus.stale).isSyncing, isFalse);
  });

  test('a problem only the user can fix is left to its banner', () {
    for (final location in [
      LocationStatus.serviceOff,
      LocationStatus.permissionDenied,
      LocationStatus.permissionBlocked,
    ]) {
      expect(_status(location: location, sensors: false).isSyncing, isFalse,
          reason: '$location');
    }
  });

  test('equal states compare equal, so an unchanged state never re-animates',
      () {
    expect(_status(location: LocationStatus.searching),
        _status(location: LocationStatus.searching));
    expect(_status(location: LocationStatus.searching),
        isNot(_status(model: false, location: LocationStatus.searching)));
  });
}
