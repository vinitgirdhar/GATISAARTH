import 'backend_telemetry_client.dart';

/// Where live telemetry frames go. Optional by design: the app is fully
/// functional with no backend reachable.
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

/// Sends frames to the optional FastAPI backend.
class BackendTelemetrySink implements TelemetrySink {
  BackendTelemetrySink([BackendTelemetryClient? client])
      : _client = client ?? BackendTelemetryClient();

  final BackendTelemetryClient _client;

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
  }) =>
      _client.sendTelemetry(
        latitude: latitude,
        longitude: longitude,
        heading: heading,
        speed: speed,
        confidence: confidence,
        gnssAvailable: gnssAvailable,
        mode: mode,
        altitude: altitude,
      );

  @override
  BackendSyncState get syncState => _client.syncState;

  @override
  int get recordsSent => _client.recordsSent;

  @override
  Future<void> stop() => _client.stopSession();
}
