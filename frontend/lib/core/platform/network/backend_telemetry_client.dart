import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

enum BackendSyncState {
  uninitialized,
  connecting,
  connected,
  offline,
  error,
}

/// Live client connecting the phone to the optional FastAPI + PostgreSQL backend.
///
/// Handles:
/// 1. Device registration (POST /devices/register)
/// 2. Drive session initialization (POST /session/start)
/// 3. Continuous telemetry streaming (POST /telemetry)
/// 4. Cheap standalone operation: the backend is optional, so while it is
///    unreachable the client backs off exponentially (5 s .. 60 s) and makes
///    NO network calls inside the backoff window. Frames sent while offline
///    are dropped, not buffered.
class BackendTelemetryClient {
  static final BackendTelemetryClient _instance =
      BackendTelemetryClient._internal();
  factory BackendTelemetryClient() => _instance;

  BackendTelemetryClient._internal() : this._(http.Client(), DateTime.now);

  /// Non-singleton instance with an injected HTTP client and clock.
  @visibleForTesting
  BackendTelemetryClient.forTesting({
    http.Client? client,
    DateTime Function()? clock,
  }) : this._(client ?? http.Client(), clock ?? DateTime.now);

  BackendTelemetryClient._(this._http, this._clock);

  final http.Client _http;
  final DateTime Function() _clock;

  static const String _defaultDeviceId = 'CPH2745_PHYSICAL';
  static const Duration _requestTimeout = Duration(seconds: 2);
  static const Duration _stopTimeout = Duration(seconds: 3);
  static const Duration _initialBackoff = Duration(seconds: 5);
  static const Duration _maxBackoff = Duration(seconds: 60);
  static const String _unreachableMessage =
      'Backend unreachable; running standalone on-device '
      '(telemetry not uploaded)';

  static const List<String> _candidateUrls = [
    'http://127.0.0.1:8000',
    'http://172.20.10.3:8000',
    'http://10.0.2.2:8000',
  ];

  String _baseUrl = 'http://127.0.0.1:8000';
  String? _deviceId;
  String? _authToken;
  String? _sessionId;
  BackendSyncState _syncState = BackendSyncState.uninitialized;
  int _recordsSent = 0;
  String _lastError = '';

  Future<bool>? _initInFlight;
  DateTime? _retryAt;
  Duration _nextBackoff = _initialBackoff;

  BackendSyncState get syncState => _syncState;
  int get recordsSent => _recordsSent;
  String? get sessionId => _sessionId;
  String get lastError => _lastError;

  void setBaseUrl(String url) {
    _baseUrl = url;
    _resetBackoff(); // a new target deserves an immediate attempt
  }

  /// Register the device and start a drive session.
  ///
  /// Concurrent callers share one in-progress attempt. Inside the backoff
  /// window after a failure this returns `false` without touching the network.
  Future<bool> initialize({String deviceId = _defaultDeviceId}) {
    final running = _initInFlight;
    if (running != null) return running;
    if (_inBackoff) return Future<bool>.value(false);

    final attempt = _connect(deviceId).whenComplete(() => _initInFlight = null);
    _initInFlight = attempt;
    return attempt;
  }

  Future<bool> _connect(String deviceId) async {
    _deviceId = deviceId;
    _syncState = BackendSyncState.connecting;

    final urlsToTry = [_baseUrl, ..._candidateUrls.where((u) => u != _baseUrl)];
    for (final url in urlsToTry) {
      if (await _registerAndStart(url)) {
        _resetBackoff();
        _syncState = BackendSyncState.connected;
        _lastError = '';
        return true;
      }
    }

    _enterOffline();
    return false;
  }

  Future<bool> _registerAndStart(String baseUrl) async {
    try {
      final token = await _register(baseUrl);
      if (token == null) return false;
      final id = await _startSession(baseUrl, token);
      if (id == null) return false;

      _authToken = token;
      _sessionId = id;
      _baseUrl = baseUrl;
      return true;
    } catch (_) {
      return false; // try the next candidate URL
    }
  }

  Future<String?> _register(String baseUrl) async {
    final response = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/devices/register'),
          headers: _headers(),
          body: jsonEncode({'device_id': _deviceId}),
        )
        .timeout(_requestTimeout);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['access_token'] as String?;
  }

  Future<String?> _startSession(String baseUrl, String token) async {
    final response = await _http
        .post(
          Uri.parse('$baseUrl/api/v1/session/start'),
          headers: _headers(token),
          body: jsonEncode({
            'metadata': {
              'hardware': _deviceId,
              'client': 'flutter_mobile',
              'source': 'real_hardware_sensors',
            }
          }),
        )
        .timeout(_requestTimeout);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as String?;
  }

  /// Send a real-time telemetry frame. Returns `false` (frame dropped) when the
  /// backend is unreachable or inside the backoff window.
  Future<bool> sendTelemetry({
    required double latitude,
    required double longitude,
    required double heading,
    required double speed,
    required double confidence,
    required bool gnssAvailable,
    required String mode,
    double? altitude,
  }) async {
    final capturedAt = _clock().toUtc().toIso8601String();

    if (_authToken == null || _sessionId == null) {
      if (!await initialize(deviceId: _deviceId ?? _defaultDeviceId)) {
        return false;
      }
    }
    final token = _authToken;
    final session = _sessionId;
    if (token == null || session == null) return false;

    final String body;
    try {
      body = jsonEncode({
        'session_id': session,
        'timestamp': capturedAt,
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'speed': speed,
        'heading': heading.clamp(0.0, 359.9),
        'confidence': confidence.clamp(0.0, 1.0),
        'gnss_available': gnssAvailable,
        'mode': mode,
      });
    } catch (e) {
      // A bad frame (e.g. NaN) is a local problem, not a reason to go offline.
      _lastError = 'Telemetry frame not encodable: $e';
      return false;
    }
    return _postFrame(token, body);
  }

  Future<bool> _postFrame(String token, String body) async {
    try {
      final response = await _http
          .post(
            Uri.parse('$_baseUrl/api/v1/telemetry'),
            headers: _headers(token),
            body: body,
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 201) {
        _recordsSent++;
        _syncState = BackendSyncState.connected;
        return true;
      }
      _lastError = 'Telemetry POST returned ${response.statusCode}';
      return false;
    } catch (_) {
      // Socket/Client/Timeout/anything else: the backend is gone. Overlapping
      // failed POSTs escalate the backoff only once (first one drops the token).
      if (_authToken == token) _enterOffline();
      return false;
    }
  }

  /// Stop current active drive session
  Future<void> stopSession() async {
    final token = _authToken;
    final session = _sessionId;
    if (session == null || token == null) return;
    try {
      await _http.post(
        Uri.parse(
            '$_baseUrl/api/v1/session/${Uri.encodeComponent(session)}/stop'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_stopTimeout);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Offline backoff: 5 s, 10 s, 20 s, 40 s, then 60 s until a success resets it.
  // ponytail: Future.timeout abandons a stalled connect rather than aborting the
  // socket; the backoff bounds the strays. Use an IOClient with
  // HttpClient.connectionTimeout if they ever matter.
  // ---------------------------------------------------------------------------

  /// True while `now < retryAt`. A clock that jumped backwards (remaining time
  /// larger than the cap) counts as expired so we can't get stuck offline.
  bool get _inBackoff {
    final retryAt = _retryAt;
    if (retryAt == null) return false;
    final remaining = retryAt.difference(_clock());
    return remaining > Duration.zero && remaining <= _maxBackoff;
  }

  void _enterOffline() {
    _authToken = null;
    _sessionId = null;
    _syncState = BackendSyncState.offline;
    _lastError = _unreachableMessage;

    _retryAt = _clock().add(_nextBackoff);
    final doubled = _nextBackoff * 2;
    _nextBackoff = doubled > _maxBackoff ? _maxBackoff : doubled;
  }

  void _resetBackoff() {
    _retryAt = null;
    _nextBackoff = _initialBackoff;
  }

  static Map<String, String> _headers([String? token]) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
}
