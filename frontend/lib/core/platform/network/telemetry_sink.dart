/// State of a telemetry link. The shipped app has none: every drive stays on
/// the phone unless the driver shares a recording.
enum BackendSyncState {
  uninitialized,
  connecting,
  connected,
  offline,
  error,
}

/// Where live telemetry frames go. The app is fully functional with none.
abstract class TelemetrySink {
  Future<bool> send({
    required double latitude,
    required double longitude,
    required double heading,
    required double speed,
    required double confidence,
    required bool gnssAvailable,
    required String mode,
    double? altitude,
  });

  BackendSyncState get syncState;
  int get recordsSent;
  Future<void> stop();
}

/// The shipped sink: nothing leaves the phone.
class LocalOnlyTelemetrySink implements TelemetrySink {
  const LocalOnlyTelemetrySink();

  @override
  Future<bool> send({
    required double latitude,
    required double longitude,
    required double heading,
    required double speed,
    required double confidence,
    required bool gnssAvailable,
    required String mode,
    double? altitude,
  }) async =>
      false;

  @override
  BackendSyncState get syncState => BackendSyncState.offline;

  @override
  int get recordsSent => 0;

  @override
  Future<void> stop() async {}
}
