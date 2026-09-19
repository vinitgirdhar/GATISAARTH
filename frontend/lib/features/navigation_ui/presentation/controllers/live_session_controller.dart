import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/nav/gnss/gnss_quality.dart';
import '../../../../core/nav/math/nav_math.dart' show Vector3;
import '../../../../core/nav/model/nav_snapshot.dart';
import '../../../../core/nav/motion/motion_classifier.dart'
    show VehicleClass;
import '../../../../core/nav/navigation_engine.dart';
import '../../../../core/nav/replay/drive_log.dart';
import '../../../../core/nav/replay/drive_recorder.dart';
import '../../../../core/nav/sensors/sensor_sample.dart';
import '../../../../core/platform/storage/drive_log_store.dart';
import '../../../../core/platform/hardware/device_hardware.dart';
import '../../../../core/platform/hardware/sensor_api.dart';
import '../../../../core/platform/hardware/vehicle_alignment_engine.dart';
import '../../../../core/platform/location/live_location_service.dart';
import '../../../../core/platform/network/backend_telemetry_client.dart'
    show BackendSyncState;
import '../../../../core/platform/network/telemetry_sink.dart';
import '../../../ai_motion/domain/speed_estimator.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';
import '../../../navigation_engine/domain/uncertainty_model.dart';

// Delhi, shown only until a real fix or a cached position exists.
const double _defaultLat = 28.6390;
const double _defaultLon = 77.0661;

/// Below this the vehicle is treated as stopped (zero-velocity update).
const double _stationarySpeed = 0.35;
const double _metresPerDegree = 111000;
const Duration _uiTick = Duration(milliseconds: 100);
const Duration _telemetryEvery = Duration(seconds: 1);
const Duration _reacquireWindow = Duration(seconds: 3);
const Duration _sensorFresh = Duration(milliseconds: 500);
const Duration _cacheEvery = Duration(seconds: 15);
const double _easeTauSeconds = 0.6;
const double _snapDistanceMeters = 1000;

// The speed model was trained on 10 Hz raw accelerometer data (gravity
// included) — see assets/models/model_metadata.json — so it is fed at that
// rate, not at the 50 Hz sensor rate.
const double _mlFeedSeconds = 0.1;
const double _gravity = 9.81;
const int _mlWarmFrames = 10; // model ticks (= 1 s) before its output is used

// While GNSS is live, sensor-only changes repaint at 4 Hz; the map marker
// and dead reckoning still repaint at the full 10 Hz tick.
const Duration _imuNotifyEvery = Duration(milliseconds: 250);

// An outage is noticed `staleAfter` seconds late. Up to this long the missed
// travel is extrapolated onto the map; beyond it (e.g. after the app sat in
// the background) it only widens the uncertainty margin.
const Duration _maxCatchUp = Duration(seconds: 15);
const String _cacheLatKey = 'last_known_lat';
const String _cacheLonKey = 'last_known_lon';

/// The single live pipeline of the app: sensors, satellite fix, dead
/// reckoning, uncertainty and telemetry.
///
/// Both screens only *observe* this object, so there is exactly one sensor
/// subscription and one neural-model instance no matter which screen is open.
/// Sensor processing runs at full rate, but listeners are notified at most
/// every [_uiTick] (10 Hz) — the UI never rebuilds at the 50 Hz sensor rate.
class LiveSessionController extends ChangeNotifier {
  LiveSessionController({
    required HardwareSensorInterface sensors,
    required VehicleAlignmentEngine alignment,
    required DeviceHardware hardware,
    required SpeedEstimator speedEstimator,
    required TelemetrySink telemetry,
    required this.location,
    DateTime Function()? clock,
    bool autoTick = true,
    DriveLogSink? logStore,
  })  : _sensors = sensors,
        _alignment = alignment,
        _hardware = hardware,
        _ml = speedEstimator,
        _telemetry = telemetry,
        _clock = clock ?? DateTime.now,
        _autoTick = autoTick,
        _logStore = logStore ?? DriveLogStore();

  final HardwareSensorInterface _sensors;
  final VehicleAlignmentEngine _alignment;
  final DeviceHardware _hardware;
  final SpeedEstimator _ml;
  final TelemetrySink _telemetry;
  final DateTime Function() _clock;
  final bool _autoTick;

  /// Owned by this controller (disposed with it).
  final LiveLocationService location;

  StreamSubscription<List<double>>? _imuSub;
  StreamSubscription<double>? _tempSub;
  Timer? _uiTimer;
  Timer? _telemetryTimer;

  bool _started = false;
  bool _running = false;
  bool _disposed = false;
  bool _dirty = false;
  bool _sendingTelemetry = false;

  // Position: `_target*` is the fused truth, `_lat/_lon` what we draw.
  double _targetLat = _defaultLat;
  double _targetLon = _defaultLon;
  double _lat = _defaultLat;
  double _lon = _defaultLon;
  double _altitude = 0;
  double _accuracy = 0;
  double _speed = 0;
  double _heading = 0;
  bool _positionSeeded = false;
  int _appliedFixCount = 0;
  DateTime? _lastEaseAt;
  DateTime? _lastCacheAt;

  // IMU snapshot.
  int _sampleCount = 0;
  DateTime? _lastSampleAt;
  double _lastFrameT = 0;
  double _accX = 0;
  double _accY = 0;
  double _accZ = 9.81;
  double _gyroZ = 0;
  double _magX = 0;
  double _magY = 0;
  double _magZ = 0;
  double _pressureHpa = double.nan;
  bool _hasMagnetometer = false;

  double _vibrationRms = 0;
  String _vibrationLevel = 'SMOOTH';
  double _stillSeconds = 0;
  double _mlClock = 0;
  int _mlFrames = 0;
  DateTime? _lastImuNotifyAt;

  bool _simTunnel = false;
  bool _simCanyon = false;
  VehicleProfile _vehicleProfile = VehicleProfile.car;
  LocationStatus _previousStatus = LocationStatus.initializing;
  DateTime? _reacquiringUntil;
  final OutageTracker _outage = OutageTracker();
  final List<AnomalyEventModel> _anomalies = [];

  /// The new navigation core (`lib/core/nav/`), running alongside the
  /// pipeline above rather than replacing it.
  ///
  /// It is fed the same sensors and fixes and produces its own estimate,
  /// but **nothing on screen comes from it yet**. The migration plan
  /// (docs/architecture/EVOLUTION_PLAN.md, step 0.10) hands the position
  /// over only once a replay of a recorded drive shows it beating the
  /// heuristic on real phone data — simulation is not that evidence.
  final NavigationEngine _engine = NavigationEngine();
  NavigationSnapshot? _navSnapshot;
  int _engineFeedCount = 0;
  int _engineMicrosTotal = 0;
  int _engineMicrosPeak = 0;
  int _appliedEngineFixCount = 0;

  /// The newest IMU event handed to the core, and when it was handed over.
  ///
  /// The core integrates against one monotonic timeline. `sensors_plus`
  /// timestamps come from the platform sensor event (device uptime) while
  /// `DateTime.now()` is epoch, so a GNSS fix has to be translated into the
  /// sensor's base — mixing them left the core comparing 1e8 against 1.8e15,
  /// and the mount alignment could never converge.
  ///
  /// Stamping a fix with the newest IMU timestamp *alone* is not enough either:
  /// when frames queue up (a GC pause, a resume, a slow frame) several fixes
  /// inherit nearly the same timestamp, their apparent spacing collapses to
  /// milliseconds, and the GNSS quality engine rightly rejects them all as
  /// impossible jumps. Adding the wall time elapsed since that sample restores
  /// the real spacing, and needs no long-lived offset estimate that a clock
  /// step could latch wrong.
  int? _lastEngineImuUs;
  DateTime? _lastEngineImuAt;

  /// Drive recording (§36). Off unless the driver starts it: a drive log is
  /// a complete record of where they went, so it is opt-in, local-only, and
  /// deletable (§48).
  final DriveLogSink _logStore;
  DriveRecorder? _recorder;
  String? _recordingPath;

  // ---------------------------------------------------------------- lifecycle

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _running = true;

    unawaited(_ml.initialize());
    _hardware.start();
    _tempSub = _hardware.temperatureStream.listen((_) => _dirty = true);
    _imuSub = _sensors.imuStream.listen(_onImu);
    _sensors.start();
    location.addListener(_onLocationChanged);
    if (_autoTick) _startTimers();

    await _loadCachedPosition();
    await location.start();
  }

  /// App went to the background: stop every radio and sensor.
  Future<void> pause() async {
    if (!_running || _disposed) return;
    _running = false;
    _lastFrameT = 0;
    _mlClock = 0;
    _stopTimers();
    _sensors.stop();
    _hardware.stop();
    if (_positionSeeded && location.hasBeenLive) {
      unawaited(_writeCache(_targetLat, _targetLon));
    }
    await location.pause();
  }

  Future<void> resume() async {
    if (!_started || _disposed) return;
    if (!_running) {
      _running = true;
      _sensors.start();
      _hardware.start();
      if (_autoTick) _startTimers();
      await location.resume();
    }
    await location.recheck();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopTimers();
    _imuSub?.cancel();
    _tempSub?.cancel();
    _sensors.stop();
    _hardware.stop();
    location.removeListener(_onLocationChanged);
    location.dispose();
    // A half-written log is still worth keeping; close it properly.
    unawaited(stopRecording());
    unawaited(_telemetry.stop());
    super.dispose();
  }

  void _startTimers() {
    _uiTimer ??= Timer.periodic(_uiTick, (_) => tick());
    _telemetryTimer ??=
        Timer.periodic(_telemetryEvery, (_) => sendTelemetryNow());
  }

  void _stopTimers() {
    _uiTimer?.cancel();
    _telemetryTimer?.cancel();
    _uiTimer = null;
    _telemetryTimer = null;
  }

  // ------------------------------------------------------------------ actions

  void setVehicleProfile(VehicleProfile profile) {
    _vehicleProfile = profile;
    _alignment.vehicleProfile = profile;
    _engine.vehicleClass = profile == VehicleProfile.twoWheeler
        ? VehicleClass.twoWheeler
        : VehicleClass.car;
    _touch();
  }

  void startTunnelTest() {
    _simTunnel = true;
    _simCanyon = false;
    _outage.reset();
    _syncOutage(_clock());
    _stillSeconds = 0;
    unawaited(_hardware.triggerOutageAlarmVibration());
    _touch();
  }

  void startUrbanCanyon() {
    _simTunnel = false;
    _simCanyon = true;
    _outage.reset();
    unawaited(_hardware.vibrate(durationMs: 150, amplitude: 180));
    _touch();
  }

  void resetSimulation() {
    if (_simTunnel) _reacquiringUntil = _clock().add(_reacquireWindow);
    _simTunnel = false;
    _simCanyon = false;
    _outage.reset();
    _speed = 0;
    unawaited(_hardware.vibrate(durationMs: 80, amplitude: 100));
    _touch();
  }

  void _touch() {
    _dirty = false;
    if (!_disposed) notifyListeners();
  }

  // -------------------------------------------------------------------- tick

  /// One UI frame: freshness checks, outage bookkeeping, position easing and
  /// (if anything changed) a listener notification. Public for tests.
  @visibleForTesting
  void tick() {
    if (_disposed) return;
    final now = _clock();
    location.checkStaleness();
    _syncOutage(now);
    // The core's answer replaces the heuristic one before the marker is
    // eased, so the map draws the filtered position, not the raw fix.
    _applyEngineSolution();
    _easePosition(now);
    if (_dirty) _touch();
  }

  void _easePosition(DateTime now) {
    final last = _lastEaseAt;
    _lastEaseAt = now;
    if (_drActive) {
      _lat = _targetLat;
      _lon = _targetLon;
      return;
    }
    final dLatM = (_targetLat - _lat) * _metresPerDegree;
    final dLonM = (_targetLon - _lon) * _metresPerDegree * cos(_lat * pi / 180);
    final distance = sqrt(dLatM * dLatM + dLonM * dLonM);
    if (distance < 0.05 || distance > _snapDistanceMeters) {
      if (_lat != _targetLat || _lon != _targetLon) _dirty = true;
      _lat = _targetLat;
      _lon = _targetLon;
      return;
    }
    final dt = last == null
        ? 0.1
        : (now.difference(last).inMilliseconds / 1000).clamp(0.0, 0.5);
    final alpha = 1 - exp(-dt / _easeTauSeconds);
    _lat += (_targetLat - _lat) * alpha;
    _lon += (_targetLon - _lon) * alpha;
    _dirty = true;
  }

  // --------------------------------------------------------------------- IMU

  void _onImu(List<double> v) {
    if (v.length < 6 || !_running) return;
    final now = _clock();
    final t = v.length > 6 ? v[6] : now.microsecondsSinceEpoch / 1e6;
    final dt = _lastFrameT == 0 ? 0.02 : (t - _lastFrameT).clamp(0.001, 1.0);
    _lastFrameT = t;

    final ax = v[0], ay = v[1], az = v[2];
    final gx = v[3], gy = v[4], gz = v[5];

    final vehicleAccel = _alignment.transformToVehicleFrame(ax, ay, az);
    final nhc = _alignment.applyNonHolonomicConstraints(vehicleAccel);
    final netAccel = (sqrt(ax * ax + ay * ay + az * az) - 9.81).abs();

    _sampleCount++;
    _lastSampleAt = now;
    _accX = _accX * 0.7 + ax * 0.3;
    _accY = _accY * 0.7 + ay * 0.3;
    _accZ = _accZ * 0.7 + az * 0.3;
    _gyroZ = _gyroZ * 0.7 + gz * 0.3;
    if (v.length >= 10) _updateHeading(v[7], v[8], v[9]);
    if (v.length >= 11) _pressureHpa = v[10];

    _vibrationRms = _vibrationRms * 0.85 + netAccel * 0.15;
    _vibrationLevel = _vibrationLevelFor(_vibrationRms);

    _advanceMotion(_feedModel(nhc, gx, gy, gz, dt), dt, now);
    _detectAnomaly(netAccel, now);
    _feedEngineImu(v, t);

    final last = _lastImuNotifyAt;
    if (_drActive || last == null || now.difference(last) >= _imuNotifyEvery) {
      _lastImuNotifyAt = now;
      _dirty = true;
    }
  }

  /// Feeds the speed model at its training rate and returns a fresh estimate
  /// on those ticks (null between them). The model is only needed when GNSS
  /// cannot supply speed, so it is idle — and its window dropped — otherwise.
  double? _feedModel(
      List<double> nhc, double gx, double gy, double gz, double dt) {
    if (!_drActive && location.isLive) {
      if (_mlFrames > 0) {
        _ml.reset();
        _mlFrames = 0;
        _mlClock = 0;
      }
      return null;
    }
    _mlClock += dt;
    if (_mlClock < _mlFeedSeconds - 0.005) return null;
    _mlClock = 0;
    _mlFrames++;
    return _ml.addImuFrame(
      ax: nhc[0],
      ay: nhc[1],
      // Levelled, gravity-free input is off-distribution: the scaler expects
      // raw accelerometer data with ~9.81 m/s² on the vertical axis.
      az: nhc[2] + _gravity,
      gx: gx,
      gy: gy,
      gz: gz,
      // The accelerations are already levelled, so the model sees a flat frame.
      pitch: 0,
      roll: 0,
    );
  }

  void _updateHeading(double mx, double my, double mz) {
    if (mx == 0 && my == 0 && mz == 0) return;
    _hasMagnetometer = true;
    _magX = mx;
    _magY = my;
    _magZ = mz;
    var target = atan2(-mx, my) * 180 / pi;
    if (target < 0) target += 360;
    var diff = target - _heading;
    while (diff < -180) {
      diff += 360;
    }
    while (diff > 180) {
      diff -= 360;
    }
    _heading = (_heading + diff * 0.45) % 360;
    if (_heading < 0) _heading += 360;
  }

  /// Called every IMU frame. [mlSpeed] is non-null only on model ticks.
  void _advanceMotion(double? mlSpeed, double dt, DateTime now) {
    _syncOutage(now);
    final bool mlReady = mlSpeed != null && _mlFrames >= _mlWarmFrames;

    // Once the core leads, its strapdown INS and EKF own the propagation.
    // Running the old speed-times-heading integration as well would move the
    // marker twice.
    if (isEngineLeading) return;

    if (_drActive) {
      // Zero-velocity update + AI dead reckoning. Until the model has a full
      // window, keep the last GNSS speed rather than snapping to zero.
      if (mlReady) _applyModelSpeed(mlSpeed);
      if (_speed > _stationarySpeed) _integrate(_speed * dt);
    } else if (!location.isLive && mlReady) {
      // No GNSS yet (or unavailable): show model speed, hold position.
      _speed = mlSpeed < _stationarySpeed ? 0 : mlSpeed;
    }
    // GNSS live: speed comes from the fix (see _applyFix).
  }

  void _applyModelSpeed(double mlSpeed) {
    if (mlSpeed >= _stationarySpeed) {
      _stillSeconds = 0;
      _speed = mlSpeed;
      return;
    }
    _stillSeconds += _mlFeedSeconds;
    // ponytail: the model's stationary gate is variance-only, so a smooth
    // steady cruise looks like a stop. Demand longer stillness before zeroing
    // a fast speed; a GNSS-speed prior or longitudinal-accel integration is
    // the real fix once driving data exists.
    final needed = _speed > 2 ? 3.0 : 1.0;
    if (_stillSeconds >= needed) _speed = 0;
  }

  /// Starts/stops the outage tracker to match [_drActive]. An outage is only
  /// noticed some time after the last real fix; that gap is backdated into the
  /// margin and (when short enough) the travelled distance is extrapolated.
  void _syncOutage(DateTime now) {
    final starting = _drActive && !_outage.isActive;
    final gap = starting && !_simTunnel
        ? location.timeSinceLastFix ?? Duration.zero
        : Duration.zero;
    _outage.update(
      outage: _drActive,
      now: now,
      accuracyMeters: _accuracy,
      alreadyElapsed: gap,
    );
    if (!starting) return;

    final missed = _speed * gap.inMilliseconds / 1000;
    if (isEngineLeading) {
      // The core backdates its own outage from the fix timestamps; adding
      // the missed travel here as well would double-count it.
      _outage.addDistance(missed);
    } else if (gap <= _maxCatchUp) {
      _integrate(missed);
    } else {
      _outage.addDistance(missed);
    }
  }

  void _integrate(double distanceMeters) {
    _outage.addDistance(distanceMeters);
    final headingRad = _heading * pi / 180;
    _targetLat += distanceMeters * cos(headingRad) / _metresPerDegree;
    _targetLon += distanceMeters *
        sin(headingRad) /
        (_metresPerDegree * cos(_targetLat * pi / 180));
  }

  void _detectAnomaly(double netAccel, DateTime now) {
    if (netAccel <= 4.5) return;
    final nowMs = now.millisecondsSinceEpoch;
    if (_anomalies.isNotEmpty && nowMs - _anomalies.first.timestamp <= 2500) {
      return;
    }
    final isPothole = netAccel > 7.0;
    _anomalies.insert(
      0,
      AnomalyEventModel(
        type: isPothole ? 'pothole' : 'speed_breaker',
        timestamp: nowMs,
        confidence: (0.85 + netAccel / 20.0).clamp(0.85, 0.99).toDouble(),
      ),
    );
    if (_anomalies.length > 5) _anomalies.removeLast();
    unawaited(_hardware.triggerRoadAnomalyVibration(isPothole));
  }

  // --------------------------------------------------------- handover

  /// True when the navigation core's solution leads the position the driver
  /// sees, instead of the heuristic pipeline above.
  ///
  /// Every condition here is a reason the core could be *worse* than the
  /// heuristic, so it hands back rather than degrading the app:
  ///
  /// * no position yet, or the mount transform has not converged — without
  ///   knowing which way the phone points in the car, the core cannot
  ///   dead-reckon at all, and this is the reason it takes a couple of
  ///   minutes of accelerating and braking before it takes over;
  /// * integrity INVALID, or the filter reported a numerical failure;
  /// * the minimum sensor set is gone.
  ///
  /// The consequence is the safety property worth stating plainly: the app
  /// can never be worse than it was before the core existed, because the
  /// core only ever takes over when it is demonstrably healthy.
  bool get isEngineLeading {
    final snapshot = _navSnapshot;
    if (snapshot == null || !snapshot.hasPosition) return false;
    if (snapshot.mode == NavMode.sensorFailure) return false;
    if (snapshot.integrity == NavIntegrity.invalid) return false;
    if (!snapshot.isMountCalibrated) return false;
    final sigma = snapshot.horizontalSigmaM;
    if (sigma == null || !sigma.isFinite) return false;
    return true;
  }

  /// Why the core is not leading yet, for the UI to show instead of leaving
  /// the driver guessing. Null once it is leading.
  String? get engineHandoverBlocker {
    if (isEngineLeading) return null;
    final snapshot = _navSnapshot;
    if (snapshot == null) return 'Navigation core starting';
    if (snapshot.mode == NavMode.sensorFailure) return 'Sensor failure';
    if (!snapshot.hasPosition) return 'Waiting for a first fix';
    if (!snapshot.isMountCalibrated) {
      final confidence = snapshot.alignmentConfidence;
      return confidence == null
          ? 'Calibrating the mount: drive straight, speed up and slow down'
          : 'Calibrating the mount '
              '(${(confidence * 100).round()} %)';
    }
    if (snapshot.integrity == NavIntegrity.invalid) {
      return 'Navigation integrity too low';
    }
    return 'Navigation core not ready';
  }

  /// Copies the core's solution into the position the UI draws.
  ///
  /// Deliberately writes the *same* fields the heuristic pipeline uses, so
  /// every screen, the map easing, telemetry and the last-position cache all
  /// keep working untouched. Nothing in the UI knows the source changed.
  void _applyEngineSolution() {
    if (!isEngineLeading) return;
    final snapshot = _navSnapshot!;
    _targetLat = snapshot.latitude!;
    _targetLon = snapshot.longitude!;
    final speed = snapshot.speedMps;
    if (speed != null && speed.isFinite) {
      _speed = speed < _stationarySpeed ? 0 : speed;
    }
    final heading = snapshot.headingDeg;
    if (heading != null && heading.isFinite) _heading = heading;
    final altitude = snapshot.altitude;
    if (altitude != null && altitude.isFinite) _altitude = altitude;
    _positionSeeded = true;
    _dirty = true;
  }

  // -------------------------------------------------------- recording

  bool get isRecording => _recorder?.isRecording ?? false;
  String? get recordingPath => _recordingPath;
  int get recordedLines => _recorder?.recordCount ?? 0;
  Duration get recordedDuration => _recorder?.duration ?? Duration.zero;

  /// Recording error, or null. Surfaced rather than swallowed: a driver
  /// who believes a drive was recorded and finds it was not has lost it.
  Object? get recordingError => _logStore.lastError;

  /// Starts recording this drive to the app's private storage.
  ///
  /// Returns the file path, or null when storage was unavailable. Nothing
  /// is uploaded and nothing starts on its own (§48).
  Future<String?> startRecording({
    String? mountDescription,
    String? roadType,
    String? notes,
  }) async {
    if (isRecording || _disposed) return _recordingPath;
    final startedAt = _clock();
    final sessionId = 'drive-${startedAt.toIso8601String().replaceAll(RegExp(r'[^0-9A-Za-z]'), '')}';
    final path = await _logStore.open(sessionId);
    if (path == null) return null;

    final recorder = DriveRecorder(sink: _logStore.write);
    recorder.start(DriveMeta(
      sessionId: sessionId,
      startedAtMs: startedAt.millisecondsSinceEpoch,
      vehicle: _vehicleProfile.name,
      mountDescription: mountDescription,
      roadType: roadType,
      notes: notes,
      configVersion: _engine.config.version,
    ));
    _recorder = recorder;
    _recordingPath = path;
    // Without this the drive ends at the screen timeout: backgrounding stops
    // the sensors, by design.
    unawaited(_hardware.setKeepScreenOn(true));
    _touch();
    return path;
  }

  /// Stops recording and closes the file.
  Future<DriveLogFile?> stopRecording() async {
    final recorder = _recorder;
    if (recorder == null) return null;
    recorder.stop();
    _recorder = null;
    _recordingPath = null;
    unawaited(_hardware.setKeepScreenOn(false));
    final file = await _logStore.close();
    if (!_disposed) _touch();
    return file;
  }

  /// Labels the moment: tunnel entry, pothole, whatever the driver taps
  /// (§42 event labels). Ignored when not recording.
  void markEvent(String label) {
    final us = _engineNowUs;
    if (us == null) return;
    _recorder?.recordMarker(monotonicUs: us, label: label);
  }

  // ---------------------------------------------------------- nav core

  /// Feeds one raw sensor frame to the navigation core.
  ///
  /// Deliberately raw and in the **phone** frame: the core does its own
  /// calibration and works out the phone-to-vehicle transform itself, which
  /// is the whole point of it (the pipeline above can only do pitch/roll).
  void _feedEngineImu(List<double> v, double tSeconds) {
    final stopwatch = Stopwatch()..start();
    try {
      final hasMag = v.length >= 10 && !(v[7] == 0 && v[8] == 0 && v[9] == 0);
      final us = (tSeconds * 1e6).round();
      _lastEngineImuUs = us;
      _lastEngineImuAt = _clock();
      _recorder?.recordImu(
        monotonicUs: us,
        accel: Vector3(v[0], v[1], v[2]),
        gyro: Vector3(v[3], v[4], v[5]),
        mag: hasMag ? Vector3(v[7], v[8], v[9]) : null,
        pressureHpa: v.length > 10 && !v[10].isNaN ? v[10] : null,
        temperatureC: _hardware.currentTemperature,
      );
      final snapshot = _engine.onImu(
        accelPhone: Vector3(v[0], v[1], v[2]),
        gyroPhone: Vector3(v[3], v[4], v[5]),
        monotonicUs: us,
        magPhone: hasMag ? Vector3(v[7], v[8], v[9]) : null,
        pressureHpa: v.length > 10 && !v[10].isNaN ? v[10] : null,
        temperatureC: _hardware.currentTemperature,
      );
      if (snapshot != null) _navSnapshot = snapshot;
    } catch (e) {
      // The core must never be able to take the app down with it while it
      // is still a passenger.
      debugPrint('[NavigationEngine] IMU feed failed: $e');
    }
    stopwatch.stop();
    _engineFeedCount++;
    _engineMicrosTotal += stopwatch.elapsedMicroseconds;
    if (stopwatch.elapsedMicroseconds > _engineMicrosPeak) {
      _engineMicrosPeak = stopwatch.elapsedMicroseconds;
    }
  }

  /// Now, on the sensor timeline: the newest IMU sample plus the wall time
  /// that has passed since it arrived. Null before the first sample.
  int? get _engineNowUs {
    final us = _lastEngineImuUs;
    final at = _lastEngineImuAt;
    if (us == null || at == null) return null;
    final elapsed = _clock().difference(at).inMicroseconds;
    return us + (elapsed > 0 ? elapsed : 0);
  }

  void _feedEngineFix(GnssFix fix) {
    // On the sensor timeline, but spaced by the wall clock: see the note on
    // [_clockOffsetUs]. Before the first IMU sample there is no shared
    // timeline, and the core could not use the fix for anything anyway.
    final us = _engineNowUs;
    if (us == null) return;
    try {
      final observation = GnssObservation(
        latitudeDeg: fix.latitude,
        longitudeDeg: fix.longitude,
        accuracyM: fix.accuracy,
        monotonicUs: us,
        altitudeM: fix.altitude == 0 ? null : fix.altitude,
        speedMps: fix.speed,
        isMocked: fix.isMocked,
      );
      _recorder?.recordGnss(observation);
      final snapshot = _engine.onGnss(observation);
      if (snapshot != null) _navSnapshot = snapshot;
      _appliedEngineFixCount++;
    } catch (e) {
      debugPrint('[NavigationEngine] fix feed failed: $e');
    }
  }

  static String _vibrationLevelFor(double rms) {
    if (rms < 0.45) return 'SMOOTH';
    if (rms < 1.6) return 'MODERATE';
    if (rms < 3.2) return 'ROUGH';
    return 'SEVERE';
  }

  // ---------------------------------------------------------------- location

  void _onLocationChanged() {
    final status = location.status;
    // Any return to live after having had a fix (stale, location switched
    // off, resumed from the background) blends in instead of jumping. The very
    // first fix has nothing to blend from.
    if (status == LocationStatus.live &&
        _previousStatus != LocationStatus.live &&
        _appliedFixCount > 0) {
      _reacquiringUntil = _clock().add(_reacquireWindow);
    }
    _previousStatus = status;

    final fix = location.lastLiveFix;
    if (fix != null && location.fixCount != _appliedFixCount) {
      _appliedFixCount = location.fixCount;
      if (!_simTunnel) _applyFix(fix);
    } else if (fix == null) {
      _seedFromLastKnown();
    }
    _syncOutage(_clock());
    _dirty = true;
  }

  void _applyFix(GnssFix fix) {
    _feedEngineFix(fix);
    _accuracy = fix.accuracy;
    _stillSeconds = 0;
    _positionSeeded = true;
    _maybeCache(fix);

    // While the core leads, a raw fix is a *measurement*, not the answer:
    // the filter has already gated it and folded in what survived. Writing
    // it straight to the marker here is exactly the teleport-on-one-bad-fix
    // behaviour the gate exists to prevent.
    if (isEngineLeading) return;

    _targetLat = fix.latitude;
    _targetLon = fix.longitude;
    _altitude = fix.altitude;
    _speed = fix.speed < 0.5 ? 0 : fix.speed;
  }

  void _seedFromLastKnown() {
    final seed = location.lastKnownFix;
    if (seed == null || location.hasBeenLive) return;
    _targetLat = _lat = seed.latitude;
    _targetLon = _lon = seed.longitude;
    _positionSeeded = true;
  }

  Future<void> _loadCachedPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_cacheLatKey);
      final lon = prefs.getDouble(_cacheLonKey);
      if (lat != null && lon != null && !_positionSeeded && !_disposed) {
        _targetLat = _lat = lat;
        _targetLon = _lon = lon;
        _positionSeeded = true;
        _dirty = true;
      }
    } catch (_) {}
  }

  void _maybeCache(GnssFix fix) {
    final now = _clock();
    final last = _lastCacheAt;
    if (last != null && now.difference(last) < _cacheEvery) return;
    _lastCacheAt = now;
    unawaited(_writeCache(fix.latitude, fix.longitude));
  }

  Future<void> _writeCache(double lat, double lon) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_cacheLatKey, lat);
      await prefs.setDouble(_cacheLonKey, lon);
    } catch (_) {}
  }

  // --------------------------------------------------------------- telemetry

  @visibleForTesting
  Future<void> sendTelemetryNow() async {
    // Before any real or cached position exists `_targetLat/_targetLon` is only
    // the placeholder map centre — never report that as the vehicle position.
    if (_sendingTelemetry || !_running || _disposed || !_positionSeeded) return;
    _sendingTelemetry = true;
    try {
      await _telemetry.send(
        latitude: _targetLat,
        longitude: _targetLon,
        heading: _heading,
        speed: _speed,
        confidence: uncertainty?.confidence ?? 0,
        gnssAvailable: hasLiveGnss,
        mode: fusionMode.nameString,
        // 0.0 is what the plugin reports when the fix has no altitude.
        altitude: location.hasBeenLive && _altitude != 0 ? _altitude : null,
      );
    } catch (_) {
      // Backend is optional; failures are handled inside the sink.
    } finally {
      _sendingTelemetry = false;
    }
  }

  // ------------------------------------------------------------------ getters

  /// Dead reckoning takes over whenever we have had a real fix and no longer
  /// have a fresh one — stale, location switched off, permission revoked, or
  /// still re-searching after a resume.
  bool get _drActive =>
      _simTunnel || (location.hasBeenLive && !location.isLive);

  bool get inOutage => _drActive;
  bool get isSimulatingTunnel => _simTunnel;
  bool get isSimulatingCanyon => _simCanyon;
  VehicleProfile get vehicleProfile => _vehicleProfile;

  double get speed => _speed;
  double get heading => _heading;
  double get latitude => _lat;
  double get longitude => _lon;
  double get altitude => _altitude;
  double get accuracy => _accuracy;

  LocationStatus get gnssStatus => location.status;

  /// True only while a real, fresh fix is arriving and we are not simulating
  /// a blackout.
  bool get hasLiveGnss => location.isLive && !_simTunnel;

  int get sampleCount => _sampleCount;
  bool get isSensorLive =>
      _running &&
      _lastSampleAt != null &&
      _clock().difference(_lastSampleAt!) < _sensorFresh;

  Duration get outageElapsed {
    final snapshot = _navSnapshot;
    if (isEngineLeading && snapshot != null && _drActive) {
      return snapshot.outageDuration;
    }
    return _outage.elapsed(_clock());
  }

  double get outageDistanceMeters {
    final snapshot = _navSnapshot;
    if (isEngineLeading && snapshot != null && _drActive) {
      return snapshot.outageDistanceM;
    }
    return _outage.distanceMeters;
  }

  double get vibrationRms => _vibrationRms;
  String get vibrationLevel => _vibrationLevel;
  double get temperature => _hardware.currentTemperature;
  double get thermalBias => _hardware.thermalBiasCorrection;
  List<AnomalyEventModel> get anomalies => List.unmodifiable(_anomalies);

  double get pitchDegrees => _alignment.pitch * 180 / pi;
  double get rollDegrees => _alignment.roll * 180 / pi;
  bool get isAlignmentCalibrated => _alignment.isCalibrated;

  /// True once the neural model has actually run; latency and confidence are
  /// meaningless (and shown as `--`) before that.
  bool get hasModelInference => _ml.hasModelInference;
  bool get isModelLoaded => _ml.isModelLoaded;
  bool get isSpeedEstimatorReady => _ml.isReady;
  int get inferenceLatencyMs => _ml.latencyMs;
  double get inferenceConfidence => _ml.confidence;
  double get inferenceSpeed => _ml.estimatedSpeed;

  double get accelX => _accX;
  double get accelY => _accY;
  double get accelZ => _accZ;
  double get gyroZ => _gyroZ;
  double get magX => _magX;
  double get magY => _magY;
  double get magZ => _magZ;

  /// Real barometer pressure, or NaN when the phone has no barometer.
  double get pressureHpa => _pressureHpa;

  BackendSyncState get backendState => _telemetry.syncState;
  int get backendRecords => _telemetry.recordsSent;

  FusionMode get fusionMode {
    if (_simTunnel) return FusionMode.deadReckoning;
    if (_simCanyon) return FusionMode.gnssDegraded;
    final until = _reacquiringUntil;
    if (until != null && _clock().isBefore(until)) {
      return FusionMode.reacquiring;
    }
    return location.isLive ? FusionMode.gnssLocked : FusionMode.deadReckoning;
  }

  /// Modelled position uncertainty, or null while there is no basis for one
  /// (no fix yet and no outage in progress).
  UncertaintyEstimate? get uncertainty {
    // Covariance beats the closed-form model whenever the core is leading:
    // the old margin was `accuracy + 5 % of distance + 0.15 m/s`, chosen to
    // stay inside the acceptance bar rather than measured from anything.
    final snapshot = _navSnapshot;
    if (isEngineLeading && snapshot?.horizontalSigmaM != null) {
      return UncertaintyModel.fromMargin(snapshot!.horizontalSigmaM!);
    }
    if (_drActive) return _outage.estimate(_clock());
    if (location.isLive) {
      return UncertaintyModel.live(
        gnssAccuracyMeters: _accuracy,
        degradeFactor: _simCanyon ? 3 : 1,
      );
    }
    return null;
  }

  NavigationStateModel get navigationState => NavigationStateModel(
        latitude: _lat,
        longitude: _lon,
        heading: _heading,
        speed: _speed,
        confidence: uncertainty?.confidence ?? 0,
        fusionMode: fusionMode,
      );

  /// Latest navigation-core estimate, or null before it has one.
  ///
  /// Diagnostics only for now — the map marker still comes from the
  /// pipeline above (see [_engine]).
  NavigationSnapshot? get navSnapshot => _navSnapshot;

  NavMode get engineMode => _engine.mode;

  /// Mode transitions with their reasons, newest last.
  List<ModeTransition> get engineTransitions => _engine.transitions;

  /// True only once the core's phone-to-vehicle transform has converged.
  bool get isMountCalibrated =>
      _navSnapshot?.isMountCalibrated ?? false;

  /// Mount-alignment confidence, or null while it is unknown.
  double? get mountConfidence => _navSnapshot?.alignmentConfidence;

  /// Evidence the mount alignment has gathered, for diagnostics (§79).
  int get alignmentSamples => _engine.alignmentSamples;
  int get alignmentEvents => _engine.alignmentEvents;
  bool get hasLevelling => _engine.hasLevelling;

  /// Mean microseconds the navigation core takes per sensor frame, or
  /// null before it has run. Measured, not estimated (§44).
  double? get engineMeanMicros => _engineFeedCount == 0
      ? null
      : _engineMicrosTotal / _engineFeedCount;

  int? get enginePeakMicros =>
      _engineFeedCount == 0 ? null : _engineMicrosPeak;

  int get engineFixCount => _appliedEngineFixCount;

  /// Sensor health, from the core's fault detector once it has an opinion.
  ///
  /// "Present" is a weaker claim than "working": a magnetometer reading
  /// 250 uT is present and useless. The detector knows the difference.
  SensorHealthModel get sensorHealth {
    final faults = _navSnapshot?.sensorFaults;
    bool healthy(SensorType type, bool fallback) {
      final diagnosis = faults?[type];
      if (diagnosis == null || diagnosis.samples == 0) return fallback;
      return diagnosis.usable;
    }

    return SensorHealthModel(
      accelerometer: healthy(SensorType.accelerometer, _sampleCount > 0),
      gyroscope: healthy(SensorType.gyroscope, _sampleCount > 0),
      magnetometer: healthy(SensorType.magnetometer, _hasMagnetometer),
      gnss: hasLiveGnss,
      barometer: healthy(SensorType.barometer, !_pressureHpa.isNaN),
    );
  }
}
