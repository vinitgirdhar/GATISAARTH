import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gatisaarth/core/platform/network/backend_telemetry_client.dart';

/// Scriptable fake backend behind a [MockClient]. Records every request.
class _FakeBackend {
  bool up = false;
  bool telemetryUp = true;
  Completer<void>? registerGate;
  final List<Uri> requests = [];

  int count(String pathSuffix) =>
      requests.where((u) => u.path.endsWith(pathSuffix)).length;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request.url);
    final path = request.url.path;
    final isTelemetry = path.endsWith('/telemetry');
    if (!up || (isTelemetry && !telemetryUp)) {
      throw http.ClientException('unreachable', request.url);
    }
    if (path.endsWith('/devices/register')) {
      await registerGate?.future;
      return http.Response(jsonEncode({'access_token': 'tok'}), 200);
    }
    if (path.endsWith('/session/start')) {
      return http.Response(jsonEncode({'id': 'sess-1'}), 200);
    }
    if (isTelemetry) return http.Response('{}', 201);
    return http.Response('{}', 200);
  }
}

void main() {
  late _FakeBackend backend;
  late DateTime now;
  late BackendTelemetryClient client;

  Future<bool> send({double latitude = 12.9}) => client.sendTelemetry(
        latitude: latitude,
        longitude: 77.6,
        heading: 90,
        speed: 10,
        confidence: 0.9,
        gnssAvailable: false,
        mode: 'DR',
      );

  void advance(Duration d) => now = now.add(d);

  /// Asserts the client stays silent for [delay] - 1 ms, then makes exactly
  /// one full candidate round (3 registrations against a dead backend).
  Future<void> expectRetryAfter(Duration delay) async {
    final before = backend.requests.length;
    advance(delay - const Duration(milliseconds: 1));
    expect(await send(), isFalse);
    expect(backend.requests.length, before, reason: 'inside backoff');

    advance(const Duration(milliseconds: 1));
    expect(await send(), isFalse);
    expect(backend.requests.length, before + 3, reason: 'one retry round');
  }

  setUp(() {
    backend = _FakeBackend();
    now = DateTime.utc(2026, 1, 1);
    client = BackendTelemetryClient.forTesting(
      client: MockClient(backend.handle),
      clock: () => now,
    );
  });

  group('offline backoff', () {
    test('20 rapid sends against a dead backend make one round of attempts',
        () async {
      for (var i = 0; i < 20; i++) {
        expect(await send(), isFalse);
      }

      expect(backend.requests.length, 3);
      expect(backend.requests.map((u) => u.host).toSet(),
          {'127.0.0.1', '172.20.10.3', '10.0.2.2'});
      expect(client.recordsSent, 0);
    });

    test('initialize() inside the backoff window makes no network call',
        () async {
      await send();
      final before = backend.requests.length;

      expect(await client.initialize(), isFalse);
      expect(backend.requests.length, before);
    });

    test('retries at 5 s, then the next backoff is 10 s', () async {
      await send();
      expect(backend.requests.length, 3);

      await expectRetryAfter(const Duration(seconds: 5));
      await expectRetryAfter(const Duration(seconds: 10));
    });

    test('backoff doubles 5,10,20,40 and caps at 60 s', () async {
      await send();
      for (final seconds in [5, 10, 20, 40, 60, 60, 60]) {
        await expectRetryAfter(Duration(seconds: seconds));
      }
    });

    test('a clock that jumps backwards does not strand the client offline',
        () async {
      await send();
      advance(const Duration(hours: -1));
      final before = backend.requests.length;

      await send();
      expect(backend.requests.length, before + 3);
    });

    test('setBaseUrl clears the backoff for an immediate retry', () async {
      await send();
      final before = backend.requests.length;

      client.setBaseUrl('http://192.168.1.50:8000');
      await send();
      expect(backend.requests.length, before + 4); // new URL + 3 candidates
    });
  });

  group('single-flight initialize', () {
    test('concurrent sends and initialize() share one registration', () async {
      backend
        ..up = true
        ..registerGate = Completer<void>();

      final first = client.initialize();
      final second = client.initialize();
      expect(identical(first, second), isTrue);
      final sends = List.generate(10, (_) => send());
      await pumpEventQueue();
      expect(backend.count('/devices/register'), 1);

      backend.registerGate!.complete();
      final results = await Future.wait(sends);

      expect(await first, isTrue);
      expect(results, everyElement(isTrue));
      expect(backend.count('/devices/register'), 1);
      expect(backend.count('/session/start'), 1);
      expect(backend.count('/telemetry'), 10);
      expect(client.recordsSent, 10);
    });
  });

  group('recovery and state', () {
    test('success resets the backoff and counts frames', () async {
      await send(); // fails -> 5 s
      await expectRetryAfter(const Duration(seconds: 5)); // fails -> 10 s

      backend.up = true;
      advance(const Duration(seconds: 10));
      expect(await send(), isTrue);
      expect(client.recordsSent, 1);
      expect(client.sessionId, 'sess-1');
      expect(client.lastError, isEmpty);

      // Backend dies mid-session: backoff restarts at 5 s, not 20 s.
      backend.up = false;
      expect(await send(), isFalse);
      final before = backend.requests.length;
      advance(const Duration(milliseconds: 4999));
      expect(await send(), isFalse);
      expect(backend.requests.length, before);
      advance(const Duration(milliseconds: 1));
      await send();
      expect(backend.requests.length, greaterThan(before));
    });

    test('syncState: uninitialized -> connecting -> connected', () async {
      expect(client.syncState, BackendSyncState.uninitialized);

      backend.registerGate = Completer<void>();
      backend.up = true;
      final pending = client.initialize();
      expect(client.syncState, BackendSyncState.connecting);
      backend.registerGate!.complete();
      expect(await pending, isTrue);
      expect(client.syncState, BackendSyncState.connected);
    });

    test('syncState goes offline on init failure and on a failed POST',
        () async {
      await send();
      expect(client.syncState, BackendSyncState.offline);
      expect(client.sessionId, isNull);

      backend.up = true;
      advance(const Duration(seconds: 5));
      expect(await send(), isTrue);
      expect(client.syncState, BackendSyncState.connected);

      backend.telemetryUp = false;
      expect(await send(), isFalse);
      expect(client.syncState, BackendSyncState.offline);
      expect(client.sessionId, isNull, reason: 'next attempt re-registers');

      backend.telemetryUp = true;
      final registersBefore = backend.count('/devices/register');
      advance(const Duration(seconds: 5));
      expect(await send(), isTrue);
      expect(backend.count('/devices/register'), registersBefore + 1);
    });

    test('a TimeoutException on the POST also goes offline', () async {
      var throwTimeout = false;
      client = BackendTelemetryClient.forTesting(
        client: MockClient((r) {
          if (throwTimeout && r.url.path.endsWith('/telemetry')) {
            throw TimeoutException('slow');
          }
          return backend.handle(r);
        }),
        clock: () => now,
      );
      backend.up = true;
      expect(await send(), isTrue);

      throwTimeout = true;
      expect(await send(), isFalse);
      expect(client.syncState, BackendSyncState.offline);
    });

    test('lastError says standalone, not buffering', () async {
      await send();

      expect(client.lastError, contains('unreachable'));
      expect(client.lastError, contains('standalone'));
      expect(client.lastError.toLowerCase(), isNot(contains('buffer')));
    });

    test('a non-encodable frame is dropped without going offline', () async {
      backend.up = true;
      expect(await send(), isTrue);

      expect(await send(latitude: double.nan), isFalse);
      expect(client.syncState, BackendSyncState.connected);
      expect(backend.count('/devices/register'), 1);
    });

    test('stopSession uses the injected client', () async {
      backend.up = true;
      await send();
      await client.stopSession();

      expect(backend.count('/session/sess-1/stop'), 1);
    });
  });
}
