import 'package:flutter/foundation.dart';

import '../../../../core/platform/location/live_location_service.dart'
    show LocationStatus;

/// What the app is waiting for while it "syncs".
enum SyncPhase {
  /// The first motion-sensor readings have not arrived.
  sensors,

  /// The on-device motion model has not finished loading.
  model,

  /// Everything is granted and running; waiting for satellites to give a fix.
  satellites,

  /// A fix is back after an outage and the position is settling onto it.
  resync,
}

/// Whether the app is still getting itself ready, and on what.
///
/// Derived only from real state - a sensor that is delivering, a model that has
/// loaded, a fix that has arrived - never from a timer, so the capsule that
/// shows it can be believed.
@immutable
class SyncStatus {
  const SyncStatus._(this.phase, this.done, this.label);

  /// Sensors, model and GNSS: the three things that must all be ready.
  static const int total = 3;

  static const SyncStatus idle = SyncStatus._(null, total, '');

  /// What is being waited for, or null when nothing is.
  final SyncPhase? phase;

  /// How many of the [total] things are ready.
  final int done;

  /// Short human label for [phase].
  final String label;

  bool get isSyncing => phase != null;

  @override
  bool operator ==(Object other) =>
      other is SyncStatus && other.phase == phase && other.done == done;

  @override
  int get hashCode => Object.hash(phase, done);
}

/// Works out the sync state from the session's signals.
///
/// Location problems only the user can fix (switched off, permission missing)
/// are not "syncing" - the banner that tells them how to fix it is the honest
/// message, and a spinner would suggest waiting helps. An outage in progress is
/// not syncing either: navigation is deliberately running without GNSS.
SyncStatus syncStatusOf({
  required bool sensorsLive,
  required bool modelReady,
  required LocationStatus location,
  required bool reacquiring,
}) {
  switch (location) {
    case LocationStatus.serviceOff:
    case LocationStatus.permissionDenied:
    case LocationStatus.permissionBlocked:
      return SyncStatus.idle;
    case LocationStatus.initializing:
    case LocationStatus.searching:
    case LocationStatus.live:
    case LocationStatus.stale:
      break;
  }

  final gnssReady = location == LocationStatus.live;
  final done = (sensorsLive ? 1 : 0) + (modelReady ? 1 : 0) + (gnssReady ? 1 : 0);

  if (!sensorsLive) {
    return SyncStatus._(SyncPhase.sensors, done, 'Starting sensors');
  }
  if (!modelReady) {
    return SyncStatus._(SyncPhase.model, done, 'Loading motion model');
  }
  if (location == LocationStatus.initializing ||
      location == LocationStatus.searching) {
    return SyncStatus._(SyncPhase.satellites, done, 'Finding satellites');
  }
  if (gnssReady && reacquiring) {
    return SyncStatus._(SyncPhase.resync, done, 'Re-syncing position');
  }
  return SyncStatus.idle;
}
