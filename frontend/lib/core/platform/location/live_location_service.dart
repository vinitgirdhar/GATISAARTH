import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;

/// Why the app does (or does not) have a usable satellite fix right now.
enum LocationStatus {
  /// Permission/service checks have not finished yet.
  initializing,

  /// The phone's location switch is off.
  serviceOff,

  /// Permission not granted yet (can still be asked for).
  permissionDenied,

  /// Permission denied permanently — only the system settings can fix it.
  permissionBlocked,

  /// Everything is granted; waiting for the first satellite fix.
  searching,

  /// A fix arrived within [LiveLocationService.staleAfter].
  live,

  /// We had a fix, but none has arrived recently (an outage).
  stale,
}

/// One location fix, independent of the underlying plugin.
@immutable
class GnssFix {
  const GnssFix({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.speed,
    this.isMocked = false,
    this.bearing,
    this.bearingAccuracy,
    this.speedAccuracy,
  });

  final double latitude;
  final double longitude;
  final double altitude;

  /// Horizontal accuracy radius in metres (smaller is better).
  final double accuracy;

  /// Ground speed in m/s (never negative).
  final double speed;
  final bool isMocked;

  /// Course over ground, degrees from north, or null when the receiver has
  /// none (standing still, or a chipset that never reports it). Without it
  /// the navigation core has to wait for the fixes to trace a course.
  final double? bearing;
  final double? bearingAccuracy;
  final double? speedAccuracy;
}

/// Thin seam over the location plugin so the state machine is unit-testable.
abstract class LocationGateway {
  Future<bool> isServiceEnabled();
  Stream<bool> serviceEnabledChanges();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<GnssFix?> lastKnownFix();
  Stream<GnssFix> fixes();
  Future<bool> openLocationSettings();
  Future<bool> openAppSettings();
}

/// Owns the location lifecycle: permission, service on/off, subscription,
/// and freshness. "Live" only ever means a real fix arrived recently — a
/// cached last-known position never counts.
class LiveLocationService extends ChangeNotifier {
  LiveLocationService({
    required LocationGateway gateway,
    DateTime Function()? clock,
    this.staleAfter = const Duration(seconds: 6),
    this.errorRetryDelay = const Duration(seconds: 2),
  })  : _gateway = gateway,
        _clock = clock ?? DateTime.now;

  final LocationGateway _gateway;
  final DateTime Function() _clock;

  /// How long without a fix before [LocationStatus.live] becomes stale.
  final Duration staleAfter;

  /// Pause before re-checking after the fix stream errors, so a persistently
  /// failing stream cannot cause a tight resubscribe loop.
  final Duration errorRetryDelay;

  LocationStatus _status = LocationStatus.initializing;
  GnssFix? _lastLiveFix;
  GnssFix? _seedFix;
  DateTime? _lastFixAt;
  bool _hasBeenLive = false;
  int _fixCount = 0;
  int _errorStreak = 0;

  StreamSubscription<GnssFix>? _fixSub;
  StreamSubscription<bool>? _serviceSub;
  bool _started = false;
  bool _paused = false;
  bool _disposed = false;
  bool _evaluating = false;
  bool _recheckQueued = false;
  bool _promptQueued = false;

  LocationStatus get status => _status;
  bool get isLive => _status == LocationStatus.live;
  bool get hasBeenLive => _hasBeenLive;

  /// Number of real fixes received; lets observers detect a *new* fix
  /// without relying on object identity.
  int get fixCount => _fixCount;

  /// Most recent real fix, if any.
  GnssFix? get lastLiveFix => _lastLiveFix;

  /// Best position to draw on a map: the last real fix, else the cached seed.
  GnssFix? get lastKnownFix => _lastLiveFix ?? _seedFix;

  Duration? get timeSinceLastFix =>
      _lastFixAt == null ? null : _clock().difference(_lastFixAt!);

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _serviceSub = _gateway.serviceEnabledChanges().listen(
          (_) => _evaluate(prompt: false),
          onError: (Object _) {},
        );
    await _evaluate(prompt: true);
  }

  /// Re-run the permission/service checks (e.g. after returning from the
  /// system settings). Never shows a permission prompt by itself.
  Future<void> recheck() => _evaluate(prompt: false);

  /// User-initiated "grant permission" action.
  Future<void> requestPermission() => _evaluate(prompt: true);

  Future<bool> openLocationSettings() => _gateway.openLocationSettings();
  Future<bool> openAppSettings() => _gateway.openAppSettings();

  /// Cheap; call from a periodic UI tick.
  void checkStaleness() {
    if (_status != LocationStatus.live || _lastFixAt == null) return;
    if (_clock().difference(_lastFixAt!) > staleAfter) {
      _status = LocationStatus.stale;
      _notify();
    }
  }

  /// Stop the GPS radio while the app is in the background.
  Future<void> pause() async {
    if (_paused || _disposed) return;
    _paused = true;
    await _cancelFixes();
    if (_status == LocationStatus.live || _status == LocationStatus.stale) {
      _status = LocationStatus.searching;
      _notify();
    }
  }

  Future<void> resume() async {
    if (!_paused || _disposed) return;
    _paused = false;
    await _evaluate(prompt: false);
  }

  Future<void> _evaluate({required bool prompt}) async {
    if (_disposed || _paused) return;
    if (_evaluating) {
      _recheckQueued = true;
      _promptQueued = _promptQueued || prompt;
      return;
    }
    _evaluating = true;
    try {
      await _evaluateOnce(prompt: prompt);
      while (_recheckQueued && !_disposed && !_paused) {
        final queuedPrompt = _promptQueued;
        _recheckQueued = false;
        _promptQueued = false;
        await _evaluateOnce(prompt: queuedPrompt);
      }
    } finally {
      _evaluating = false;
    }
  }

  Future<void> _evaluateOnce({required bool prompt}) async {
    final bool enabled = await _safe(_gateway.isServiceEnabled, false);
    if (_disposed || _paused) return;
    if (!enabled) {
      await _cancelFixes();
      _setStatus(LocationStatus.serviceOff);
      return;
    }

    var permission = await _safe(
      _gateway.checkPermission,
      LocationPermission.unableToDetermine,
    );
    if (permission == LocationPermission.denied && prompt) {
      permission = await _safe(
        _gateway.requestPermission,
        LocationPermission.denied,
      );
    }
    if (_disposed || _paused) return;

    switch (permission) {
      case LocationPermission.deniedForever:
        await _cancelFixes();
        _setStatus(LocationStatus.permissionBlocked);
        return;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        await _cancelFixes();
        _setStatus(LocationStatus.permissionDenied);
        return;
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }

    _seedFix ??= await _safe<GnssFix?>(_gateway.lastKnownFix, null);
    if (_disposed || _paused) return;
    _fixSub ??= _gateway.fixes().listen(
          _onFix,
          onError: _onFixError,
          cancelOnError: false,
        );
    if (_status != LocationStatus.live && _status != LocationStatus.stale) {
      _setStatus(LocationStatus.searching);
    } else {
      _notify();
    }
  }

  void _onFix(GnssFix fix) {
    if (_disposed) return;
    _lastLiveFix = fix;
    _lastFixAt = _clock();
    _fixCount++;
    _errorStreak = 0;
    _hasBeenLive = true;
    _status = LocationStatus.live;
    _notify();
  }

  void _onFixError(Object _) {
    // Typically the location switch was turned off mid-session. Back off
    // (x2 per consecutive failure, up to 16x) so a stream that keeps failing
    // does not recreate the platform location client every couple of seconds.
    final delay = errorRetryDelay * (1 << min(_errorStreak, 4));
    _errorStreak++;
    _cancelFixes()
        .then((_) => Future<void>.delayed(delay))
        .then((_) => _evaluate(prompt: false));
  }

  Future<void> _cancelFixes() async {
    final sub = _fixSub;
    _fixSub = null;
    await sub?.cancel();
  }

  void _setStatus(LocationStatus next) {
    if (_status == next) return;
    _status = next;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _safe<T>(Future<T> Function() call, T fallback) async {
    try {
      return await call();
    } catch (e) {
      debugPrint('[LiveLocationService] $e');
      return fallback;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fixSub?.cancel();
    _serviceSub?.cancel();
    _fixSub = null;
    _serviceSub = null;
    super.dispose();
  }
}
