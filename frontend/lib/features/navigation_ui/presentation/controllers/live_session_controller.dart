import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/dr_constants.dart';
import '../../../../core/nav/anchors/anchor_pack.dart';
import '../../../../core/nav/anchors/portal_anchor.dart';
import '../../../../core/nav/gnss/gnss_quality.dart';
import '../../../../core/nav/guidance/mission_guidance.dart';
import '../../../../core/nav/math/nav_math.dart' show Vector3;
import '../../../../core/nav/model/nav_snapshot.dart';
import '../../../../core/nav/motion/motion_classifier.dart' show VehicleClass;
import '../../../../core/nav/navigation_engine.dart';
import '../../../../core/nav/nav_config.dart';
import '../../../../core/nav/replay/drive_log.dart';
import '../../../../core/platform/gnss/gnss_telemetry.dart';
import '../../../../core/platform/gnss/gnss_integrity_monitor.dart';
import '../../../../core/platform/anchors/anchor_pack_source.dart';
import '../../../../core/nav/replay/drive_recorder.dart';
import '../../../../core/nav/sensors/sensor_sample.dart';
import '../../../../core/platform/storage/drive_log_store.dart';
import '../../../../core/platform/hardware/device_hardware.dart';
import '../../../../core/platform/guidance/voice_guidance.dart';
import '../../../../core/platform/hardware/haptics.dart';
import '../../../../core/platform/hardware/sensor_api.dart';
import '../../../../core/platform/hardware/vehicle_alignment_engine.dart';
import '../../../../core/platform/location/live_location_service.dart';
import '../../../../core/platform/network/backend_telemetry_client.dart'
    show BackendSyncState;
import '../../../../core/platform/maps/pack_road_source.dart'
    show RoadGraphSource;
import '../../../../core/platform/network/telemetry_sink.dart';
import '../../../ai_motion/domain/speed_estimator.dart';
import '../../../ai_motion/domain/ai_engine_feed.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';
import '../../../navigation_engine/domain/uncertainty_model.dart';
import 'road_constraint.dart';
import 'sync_status.dart';
import 'track_trail.dart';

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

/// What the two demo buttons drive at when the phone itself is standing still:
/// 45 km/h through a tunnel, 30 km/h between tall buildings.
const double _tunnelCruiseSpeed = 12.5;
const double _canyonCruiseSpeed = 8.33;

/// Below this speed the direction between two fixes is noise, not a course.
const double _courseMinSpeed = 2.0;

/// Urban canyon: satellite fixes are reported this much less certain than the
/// receiver says, and a fix is only allowed to nudge the position along the
/// road when it shows the vehicle really moving.
const double _canyonMinAccuracy = 25.0;
const double _canyonMovingSpeed = 1.0;

/// Without a Doppler speed, a fix only proves movement by being this far (or
/// three times its own accuracy, if that is more) from the previous one: a
/// standing receiver's position jitters by metres and would otherwise read as
/// a crawl.
const double _canyonMinMoveM = 15.0;

/// Fixes in a row that must disagree with the road before the vehicle is
/// taken to be on another street. One outlier is what a canyon is made of.
const int _canyonRelockAfter = 3;

// The speed model was trained on 10 Hz raw accelerometer data (gravity
// included) — see assets/models/model_metadata.json — so it is fed at that
// rate, not at the 50 Hz sensor rate.
const double _mlFeedSeconds = 0.1;
const int _mlWarmFrames = 10; // model ticks (= 1 s) before its output is used

// While GNSS is live, sensor-only changes repaint at 4 Hz; the map marker
// and dead reckoning still repaint at the full 10 Hz tick.
const Duration _imuNotifyEvery = Duration(milliseconds: 250);

// An outage is noticed `staleAfter` seconds late. Up to this long the missed
// travel is extrapolated onto the map; beyond it (e.g. after the app sat in
// the background) it only widens the uncertainty margin.
const Duration _maxCatchUp = Duration(seconds: 15);
const String _cacheLatKey = 'last_known_lat';
const String _vehicleKey = 'vehicle_profile';
const String _hapticsKey = 'haptics_enabled';
const String _voiceGuidanceKey = 'voice_guidance_enabled';

class AnchorApplicationResult {
  const AnchorApplicationResult(this.accepted, this.message);

  final bool accepted;
  final String message;
}

/// After returning from the background the signal settles for a while; that is
/// not an outage worth buzzing about.
const Duration _afterResumeQuiet = Duration(seconds: 20);
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
    Haptics? haptics,
    RoadGraphSource? roads,
    GnssTelemetrySource? gnssTelemetry,
    VoiceGuidance? voiceGuidance,
    AnchorPackSource? anchorPacks,
  })  : _sensors = sensors,
        _alignment = alignment,
        _hardware = hardware,
        _ml = speedEstimator,
        _telemetry = telemetry,
        _clock = clock ?? DateTime.now,
        _autoTick = autoTick,
        _logStore = logStore ?? DriveLogStore(),
        _haptics = haptics ?? Haptics(hardware, clock: clock),
        _gnssTelemetrySource = gnssTelemetry ?? const NoopGnssTelemetrySource(),
        _voiceGuidance = voiceGuidance ?? const NoopVoiceGuidance(),
        _anchorPacks = anchorPacks ?? const EmptyAnchorPackSource(),
        _road = RoadConstraint(source: roads, clock: clock) {
    _road.onRoadsChanged = _onRoadsChanged;
    _aiFeed = AiEngineFeed(speed: speedEstimator);
  }

  final HardwareSensorInterface _sensors;
  final Haptics _haptics;
  DateTime? _resumedAt;
  final VehicleAlignmentEngine _alignment;
  final DeviceHardware _hardware;
  final SpeedEstimator _ml;
  late final AiEngineFeed _aiFeed;
  final TelemetrySink _telemetry;
  final DateTime Function() _clock;
  final bool _autoTick;
  final GnssTelemetrySource _gnssTelemetrySource;
  final VoiceGuidance _voiceGuidance;
  final AnchorPackSource _anchorPacks;
  AnchorPack? _anchorPack;
  PortalAnchorPolicy? _portalAnchorPolicy;
  final GnssIntegrityMonitor _gnssIntegrity = GnssIntegrityMonitor();
  final MissionGuidancePolicy _missionPolicy = MissionGuidancePolicy();
  MissionGuidanceDecision? _missionGuidance;
  bool _voiceGuidanceEnabled = true;

  /// Owned by this controller (disposed with it).
  final LiveLocationService location;

  /// The path travelled so far, for the map: solid where a fix backed the
  /// position, dashed where it was dead-reckoned.
  final TrackTrail trail = TrackTrail();

  StreamSubscription<List<double>>? _imuSub;
  StreamSubscription<double>? _tempSub;
  StreamSubscription<GnssTelemetrySnapshot>? _gnssTelemetrySub;
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

  /// Whether the drawn position has been put on a real one yet (a live fix, or
  /// an outage that began from one), as opposed to a remembered start.
  bool _drawnOnReal = false;
  int _appliedFixCount = 0;
  DateTime? _lastEaseAt;
  DateTime? _lastCacheAt;
  double? _lastFixLat;
  double? _lastFixLon;
  DateTime? _lastFixAt;
  GnssTelemetrySnapshot? _gnssTelemetry;

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

  /// Keeps dead reckoning on the roads of the installed map (see class doc).
  final RoadConstraint _road;

  /// The direction of travel the satellites reported at the last fix, or null
  /// when the vehicle was too slow for it to mean anything. Better than the
  /// compass to decide which way along a road the vehicle was going when signal
  /// was lost: a phone in a cradle, pocket or hand makes the compass point
  /// anywhere.
  double? _courseDeg;
  DateTime? _lastRoadAdvanceAt;
  int _canyonMisses = 0;

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
  final NavigationEngine _engine = NavigationEngine(config: NavConfig.live);
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
    await _loadVehicleProfile();
    await _loadHaptics();
    await _loadVoiceGuidance();
    await _loadAnchorPack();
    await location.start();
    _gnssTelemetrySub ??= _gnssTelemetrySource.snapshots.listen(
      (snapshot) {
        _gnssTelemetry = snapshot;
        _gnssIntegrity.add(snapshot);
        final us = _engineNowUs;
        if (us != null) {
          _recorder?.recordGnssReceiver(monotonicUs: us, snapshot: snapshot);
        }
        _dirty = true;
      },
      onError: (_) {
        // Position remains available through geolocator when raw receiver
        // diagnostics are unsupported. Never substitute demo telemetry.
      },
    );
    await _gnssTelemetrySource.start();
  }

  Future<void> _loadAnchorPack() async {
    try {
      final pack = await _anchorPacks.load();
      if (_disposed) return;
      _anchorPack = pack;
      _portalAnchorPolicy = PortalAnchorPolicy(
        registry: PortalAnchorRegistry(pack.anchors),
      );
    } catch (error) {
      debugPrint('[AnchorPack] unavailable: $error');
    }
  }

  AnchorApplicationResult applyPortalPayload(String payload) {
    final policy = _portalAnchorPolicy;
    if (policy == null || _anchorPack == null) {
      return const AnchorApplicationResult(
          false, 'No local anchor pack installed');
    }
    final decision = policy.evaluate(
      payload: payload,
      context: PortalAnchorContext(
        inOutage: inOutage,
        estimatedLatitudeDeg: _navSnapshot?.latitude ?? _lat,
        estimatedLongitudeDeg: _navSnapshot?.longitude ?? _lon,
        horizontalSigmaM:
            _navSnapshot?.horizontalSigmaM ?? uncertainty?.marginMeters ?? 25,
      ),
    );
    if (!decision.accepted) {
      return AnchorApplicationResult(
          false, _portalRejectionMessage(decision.reason));
    }
    final us = _engineNowUs;
    if (us == null) {
      return const AnchorApplicationResult(
          false, 'Navigation sensors are not ready');
    }
    final update =
        _engine.onPortalAnchor(decision.measurement!, monotonicUs: us);
    if (update == null || !update.accepted) {
      return const AnchorApplicationResult(
          false, 'Anchor rejected by the navigation filter');
    }
    _navSnapshot = _engine.snapshot;
    _touch();
    return AnchorApplicationResult(
      true,
      '${decision.measurement!.anchor.label} accepted · EKF corrected',
    );
  }

  static String _portalRejectionMessage(PortalAnchorRejection? reason) {
    switch (reason) {
      case PortalAnchorRejection.notInOutage:
        return 'Portal anchors are available only during a GNSS outage';
      case PortalAnchorRejection.unknownAnchor:
        return 'Marker is not in the installed local anchor pack';
      case PortalAnchorRejection.implausibleResidual:
        return 'Marker conflicts with the current uncertainty corridor';
      case PortalAnchorRejection.invalidEstimate:
        return 'Navigation estimate is not ready';
      case PortalAnchorRejection.malformedPayload:
      case null:
        return 'Unknown or unsafe marker';
    }
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
    // Backgrounded apps can be killed without warning: put what has been
    // recorded so far on disk now.
    if (isRecording) unawaited(_logStore.flush());
    if (_positionSeeded && location.hasBeenLive) {
      unawaited(_writeCache(_targetLat, _targetLon));
    }
    await _gnssTelemetrySource.stop();
    await location.pause();
  }

  Future<void> resume() async {
    if (!_started || _disposed) return;
    if (!_running) {
      _running = true;
      _resumedAt = _clock();
      _sensors.start();
      _hardware.start();
      if (_autoTick) _startTimers();
      await location.resume();
      await _gnssTelemetrySource.start();
    }
    await location.recheck();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _road.dispose();
    _stopTimers();
    _imuSub?.cancel();
    _tempSub?.cancel();
    _gnssTelemetrySub?.cancel();
    unawaited(_gnssTelemetrySource.stop());
    unawaited(_voiceGuidance.stop());
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

  /// The user's "Haptic alerts" switch. Remembered across restarts.
  bool get hapticsEnabled => _haptics.enabled;

  void setHapticsEnabled(bool on) {
    _haptics.enabled = on;
    unawaited(_saveHaptics(on));
    _touch();
  }

  Future<void> _loadHaptics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_hapticsKey);
      if (saved != null && !_disposed) _haptics.enabled = saved;
    } catch (_) {}
  }

  Future<void> _saveHaptics(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hapticsKey, on);
    } catch (_) {}
  }

  bool get voiceGuidanceEnabled => _voiceGuidanceEnabled;

  void setVoiceGuidanceEnabled(bool on) {
    _voiceGuidanceEnabled = on;
    if (!on) unawaited(_voiceGuidance.stop());
    unawaited(_saveVoiceGuidance(on));
    _touch();
  }

  Future<void> _loadVoiceGuidance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_voiceGuidanceKey);
      if (saved != null && !_disposed) _voiceGuidanceEnabled = saved;
    } catch (_) {}
  }

  Future<void> _saveVoiceGuidance(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_voiceGuidanceKey, on);
    } catch (_) {}
  }

  void setVehicleProfile(VehicleProfile profile) {
    _applyVehicleProfile(profile);
    unawaited(_saveVehicleProfile(profile));
  }

  /// The chosen vehicle is remembered: an app that restarts mid-ride must not
  /// quietly go back to being a car, and a drive log records which it was.
  Future<void> _loadVehicleProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved =
          VehicleProfile.values.asNameMap()[prefs.getString(_vehicleKey)];
      if (saved != null && !_disposed) _applyVehicleProfile(saved);
    } catch (_) {}
  }

  Future<void> _saveVehicleProfile(VehicleProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_vehicleKey, profile.name);
    } catch (_) {}
  }

  void _applyVehicleProfile(VehicleProfile profile) {
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
    // The outage starts here, so this is where the marker goes onto the road.
    _syncOutage(_clock());
    _stillSeconds = 0;
    // When starting tunnel test, if vehicle was stationary or slow, initialize
    // a realistic tunnel cruise speed (45 km/h = 12.5 m/s) so simulation demonstrates
    // dead reckoning actively moving across the map in real time.
    if (_speed < 5.0) {
      _speed = _tunnelCruiseSpeed;
    }
    _touch();
  }

  void startUrbanCanyon() {
    _simTunnel = false;
    _simCanyon = true;
    _outage.reset();
    _canyonMisses = 0;
    _lockRoad();
    if (_speed < 5.0) {
      _speed = _canyonCruiseSpeed; // 30 km/h urban speed
    }
    _touch();
  }

  void resetSimulation() {
    final wasSimulating = _simTunnel || _simCanyon;
    if (_simTunnel) _reacquiringUntil = _clock().add(_reacquireWindow);
    _simTunnel = false;
    _simCanyon = false;
    _outage.reset();
    _speed = location.lastLiveFix?.speed ?? 0;
    // A real outage carries on where it is: only a simulation is put back on
    // the live fix.
    final fix = location.lastLiveFix;
    if (wasSimulating && fix != null) {
      _road.release();
      _canyonMisses = 0;
      _accuracy = fix.accuracy;
      _targetLat = fix.latitude;
      _targetLon = fix.longitude;
    }
    _touch();
  }

  /// Puts the marker on the road it is on, facing the way the vehicle is
  /// going, so dead reckoning follows the street instead of a bare heading.
  /// Leaves the marker where it was when there is no road close by; with
  /// [keepIfFails] a lock already held survives a failed attempt too.
  bool _lockRoad({double? lat, double? lon, bool keepIfFails = false}) {
    final onRoad = _road.lock(
      lat ?? _targetLat,
      lon ?? _targetLon,
      // Held on a road, the road's own direction is the best there is.
      headingDeg: _road.isLocked ? _heading : (_courseDeg ?? _heading),
      keepIfFails: keepIfFails,
    );
    if (onRoad == null) return false;
    _adoptRoadPosition();
    return true;
  }

  /// Copies the road follower's position and direction to the marker.
  void _adoptRoadPosition() {
    final onRoad = _road.position;
    if (onRoad == null) return;
    _targetLat = onRoad.lat;
    _targetLon = onRoad.lon;
    _heading = onRoad.headingDeg;
  }

  /// New roads arrived (the map was opened, or the vehicle moved on). A
  /// session already dead reckoning off the roads gets onto them now.
  void _onRoadsChanged() {
    if (_disposed) return;
    // The core's map matcher works on the same roads the marker follows: the
    // ones drawn on screen, read from the installed offline map.
    final roads = _road.graph;
    if (roads != null) _engine.setRoadGraph(roads);
    if ((_drActive || _simCanyon) && !_road.isLocked && _lockRoad()) {
      _dirty = true;
    }
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
    // Roads are read ahead of need: an outage has to find them already loaded.
    if (_positionSeeded) _road.watch(_targetLat, _targetLon);
    _easePosition(now);
    _recordTrail();
    if (_dirty) _touch();
  }

  /// Adds the drawn position to the track. Until there is a position that
  /// means something - a live fix, or an outage that began from one - nothing
  /// is recorded: before that the marker sits on a built-in default.
  void _recordTrail() {
    if (uncertainty == null) return;
    trail.add(
      _lat,
      _lon,
      _drActive ? TrailKind.deadReckoning : TrailKind.gnss,
    );
  }

  /// Forgets the track drawn so far.
  void clearTrail() {
    trail.clear();
    _touch();
  }

  void _easePosition(DateTime now) {
    final last = _lastEaseAt;
    _lastEaseAt = now;
    if (_drActive || _simCanyon) {
      _drawnOnReal = true;
      _lat = _targetLat;
      _lon = _targetLon;
      return;
    }
    // The marker waits on the last known place until the first real position,
    // then jumps to it. Gliding across from a stale start would also draw a
    // track the vehicle never drove.
    if (!_drawnOnReal && uncertainty != null) {
      _drawnOnReal = true;
      if (_lat != _targetLat || _lon != _targetLon) _dirty = true;
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
    _alignment.applyNonHolonomicConstraints(vehicleAccel);
    final netAccel = (sqrt(ax * ax + ay * ay + az * az) - 9.81).abs();

    _sampleCount++;
    _lastSampleAt = now;
    _accX = _accX * 0.7 + ax * 0.3;
    _accY = _accY * 0.7 + ay * 0.3;
    _accZ = _accZ * 0.7 + az * 0.3;
    _gyroZ = _gyroZ * 0.7 + gz * 0.3;
    // On a road the road gives the heading; the compass would only fight it.
    if (v.length >= 10) {
      _updateHeading(v[7], v[8], v[9], steer: !_road.isLocked);
    }
    // Only while moving: at a red light the gyro's bias would otherwise be
    // read as a turn.
    if (_speed > _stationarySpeed) {
      _road.addYaw(_yawStepDegrees(gx, gy, gz, dt));
    }
    if (v.length >= 11) _pressureHpa = v[10];

    _vibrationRms = _vibrationRms * 0.85 + netAccel * 0.15;
    _vibrationLevel = _vibrationLevelFor(_vibrationRms);

    _advanceMotion(_feedModel([ax, ay, az], gx, gy, gz, dt), dt, now);
    _detectAnomaly(netAccel, now);
    _feedEngineImu(v, t);

    final last = _lastImuNotifyAt;
    if (_drActive || last == null || now.difference(last) >= _imuNotifyEvery) {
      _lastImuNotifyAt = now;
      _dirty = true;
    }
  }

  /// Feeds the speed model at its training rate and returns a fresh estimate
  /// on those ticks (null between them). The model also runs while GNSS is
  /// live so the AI panel shows real output, but its speed is only *returned*
  /// (and so only used by dead reckoning) once GNSS cannot supply speed; the
  /// warm-up counter restarts at every outage.
  double? _feedModel(
      List<double> nhc, double gx, double gy, double gz, double dt) {
    _mlClock += dt;
    if (_mlClock < _mlFeedSeconds - 0.005) return null;
    _mlClock = 0;
    final speed = _runModel(nhc, gx, gy, gz);
    if (!_drActive && location.isLive) {
      _mlFrames = 0;
      return null;
    }
    _mlFrames++;
    return speed;
  }

  double _runModel(List<double> raw, double gx, double gy, double gz) {
    // The trained model expects raw FLU (forward, left, up), including
    // gravity. Never pass NHC-clamped acceleration: it removes road signal.
    final mount = _engine.alignment;
    if (mount != null) {
      final acceleration = mount.toVehicle(Vector3(raw[0], raw[1], raw[2]));
      final angularRate = mount.toVehicle(Vector3(gx, gy, gz));
      return _ml.addImuFrame(
        ax: acceleration.x,
        ay: -acceleration.y,
        az: -acceleration.z,
        gx: angularRate.x,
        gy: -angularRate.y,
        gz: -angularRate.z,
        // The accelerations are already levelled, so the model sees a flat frame.
        pitch: 0,
        roll: 0,
      );
    }

    // Mount has not fully converged yet (e.g. at start, on desk, or on emulator).
    // Level using estimated or instantaneous gravity vector so gravity is aligned
    // with +Z (up), preventing massive out-of-distribution feature errors.
    final rawAcc = Vector3(raw[0], raw[1], raw[2]);
    final rawG = Vector3(gx, gy, gz);
    final up = _engine.upInPhone ??
        (rawAcc.length > 1.0 ? rawAcc.normalized() : Vector3(0, 0, 1));

    // Decompose acceleration into vertical (along up) and horizontal plane
    final az = rawAcc.dot(up);
    final aHoriz = rawAcc - (up * az);
    final ax = aHoriz.length > 0.05 ? aHoriz.length : 0.0;
    const ay = 0.0;

    // Project angular rate: rotation about vertical is gz
    final gzLevel = rawG.dot(up);
    final gHoriz = rawG - (up * gzLevel);

    return _ml.addImuFrame(
      ax: ax,
      ay: ay,
      az: az,
      gx: gHoriz.x,
      gy: gHoriz.y,
      gz: gzLevel,
      pitch: 0,
      roll: 0,
    );
  }

  /// How far the vehicle turned during this sample, in compass degrees
  /// (clockwise positive): the gyroscope's rotation about the vertical, found
  /// by projecting it on the gravity direction so it holds however the phone
  /// is mounted. Tells the road follower which way a junction was taken.
  double _yawStepDegrees(double gx, double gy, double gz, double dt) {
    final gravity = sqrt(_accX * _accX + _accY * _accY + _accZ * _accZ);
    if (gravity < 1) return 0; // free fall: no "up" to measure against
    final rateUp = (gx * _accX + gy * _accY + gz * _accZ) / gravity;
    return -rateUp * dt * 180 / pi;
  }

  void _updateHeading(double mx, double my, double mz, {required bool steer}) {
    if (mx == 0 && my == 0 && mz == 0) return;
    _hasMagnetometer = true;
    _magX = mx;
    _magY = my;
    _magZ = mz;
    if (!steer) return;
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

    if (_drActive || _simCanyon) {
      // Fallback while the core is not leading: hold the speed along
      // the road/heading, and let the model's stillness gate stop it during real DR.
      if (mlReady && _drActive && !_simTunnel) _applyModelStillness(mlSpeed);
      if (_speed > _stationarySpeed) _integrate(_speed * dt);
    }
    // GNSS live: speed comes from the fix (see _applyFix). With no fix ever,
    // there is no basis for a speed, so it stays at zero rather than showing
    // an unvalidated model's guess.
  }

  void _applyModelStillness(double mlSpeed) {
    if (mlSpeed >= _stationarySpeed) {
      _stillSeconds = 0;
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

  /// Whether a starting outage is one to buzz about: a signal lost while the
  /// driver was using the app (or the tunnel test), not a location switch they
  /// turned off and not the settling after coming back from the background.
  bool _outageIsWorthAlerting(DateTime now) {
    final resumed = _resumedAt;
    if (resumed != null && now.difference(resumed) < _afterResumeQuiet) {
      return false;
    }
    return _simTunnel || location.status == LocationStatus.stale;
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
    _updateMissionGuidance();
    if (starting && _outageIsWorthAlerting(now)) {
      unawaited(
          _haptics.fire(HapticEvent.outageStarted, recording: isRecording));
    }
    if (!starting) return;

    // Onto the road first: the travel missed while the outage went unnoticed
    // is then walked along the street, not along a bare heading.
    // A parked vehicle is not put on the nearest street: only one that was
    // moving when the signal went (or the tunnel test) has a road to follow.
    if (_simTunnel || _speed > _stationarySpeed) _lockRoad();
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

  void _updateMissionGuidance() {
    final candidates = _navSnapshot?.mapMatchResult?.candidates ?? const [];
    final best = candidates.isEmpty ? null : candidates.first;
    final decision = _missionPolicy.update(MissionGuidanceContext(
      inOutage: _drActive,
      marginMeters: uncertainty?.marginMeters,
      roadHypotheses: candidates.length,
      leadingRoadProbability: best?.posterior,
      trustedRoad: _drActive ? null : best?.roadName,
      trustedHeadingDeg: _drActive ? null : _heading,
    ));
    if (decision == null) return;
    _missionGuidance = decision;
    if (_voiceGuidanceEnabled) unawaited(_voiceGuidance.speak(decision.speech));
    if (decision.requestHaptic &&
        decision.event != MissionGuidanceEvent.outageStarted) {
      unawaited(
          _haptics.fire(HapticEvent.missionWarning, recording: isRecording));
    }
    _dirty = true;
  }

  /// Moves the fused position [distanceMeters] forward: along the road when
  /// the marker is on one, otherwise straight ahead on the heading.
  void _integrate(double distanceMeters) {
    _outage.addDistance(distanceMeters);
    if (_road.advance(distanceMeters, simulated: _simTunnel || _simCanyon) ==
        null) {
      _integrateUnconstrained(distanceMeters);
      return;
    }
    _adoptRoadPosition();
  }

  void _integrateUnconstrained(double distanceMeters) {
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
    // Visual only, on purpose: see [Haptics] for why a bump never buzzes.
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
  bool get isEngineLeading => _navSnapshot?.canLeadPosition ?? false;

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
    if (!isEngineLeading) {
      _lastRoadAdvanceAt = null;
      return;
    }
    final snapshot = _navSnapshot!;
    final speed = snapshot.speedMps;
    if (speed != null && speed.isFinite) {
      _speed = speed < _stationarySpeed ? 0 : speed;
    }
    if (_road.isLocked && (_drActive || _simCanyon)) {
      _advanceAlongRoad();
    } else {
      _lastRoadAdvanceAt = null;
      _targetLat = snapshot.latitude!;
      _targetLon = snapshot.longitude!;
      final heading = snapshot.headingDeg;
      if (heading != null && heading.isFinite) _heading = heading;
    }
    final altitude = snapshot.altitude;
    if (altitude != null && altitude.isFinite) _altitude = altitude;
    _positionSeeded = true;
    _dirty = true;
  }

  /// Dead reckoning on a road while the core leads: its speed is trusted, its
  /// free-space position is not. Off satellites, a vehicle on a street can only
  /// have gone along it, so the core says how far and the road says where.
  void _advanceAlongRoad() {
    final now = _clock();
    final last = _lastRoadAdvanceAt;
    _lastRoadAdvanceAt = now;
    if (last == null || _speed <= _stationarySpeed) return;
    final dt = (now.difference(last).inMilliseconds / 1000).clamp(0.0, 0.5);
    _integrate(_speed * dt);
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
    final sessionId =
        'drive-${startedAt.toIso8601String().replaceAll(RegExp(r'[^0-9A-Za-z]'), '')}';
    final path = await _logStore.open(sessionId);
    if (path == null) return null;
    unawaited(_haptics.fire(HapticEvent.recordingStarted));
    final device = await _hardware.deviceInfo();

    final recorder = DriveRecorder(sink: _logStore.write);
    recorder.start(DriveMeta(
      sessionId: sessionId,
      startedAtMs: startedAt.millisecondsSinceEpoch,
      deviceModel: device?.model,
      osVersion: device?.os,
      appVersion: AppConstants.appVersion,
      vehicle: _vehicleProfile.name,
      mountDescription: mountDescription ??
          (_alignment.isCalibrated
              ? 'calibrated mount · pitch ${pitchDegrees.toStringAsFixed(1)}° '
                  'roll ${rollDegrees.toStringAsFixed(1)}°'
              : 'unverified mount'),
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
    unawaited(_haptics.fire(HapticEvent.recordingStopped));
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
      final ai = _aiFeed.poll(us);
      if (ai.speed != null) _engine.onAiSpeed(ai.speed!);
      if (ai.disturbance != null) _engine.onDisturbance(ai.disturbance!);
      if (ai.fusion != null) _engine.onFusionConfidence(ai.fusion!);
      _recorder?.recordAi(
        monotonicUs: us,
        speed: ai.speed,
        disturbance: ai.disturbance,
        fusion: ai.fusion,
      );
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
    _accuracy =
        _simCanyon ? max(fix.accuracy, _canyonMinAccuracy) : fix.accuracy;
    _stillSeconds = 0;
    _positionSeeded = true;
    _maybeCache(fix);

    final now = _clock();
    double resolvedSpeed = fix.speed;
    var movedM = 0.0;

    // Real-time speed & heading calibration:
    // When Android device doesn't populate fix.speed or reports 0 during walking/low speeds,
    // accurately derive ground speed and course heading from consecutive GPS positions.
    if (_lastFixLat != null && _lastFixLon != null && _lastFixAt != null) {
      final dt = now.difference(_lastFixAt!).inMilliseconds / 1000.0;
      if (dt >= 0.5 && dt <= 10.0) {
        final dLatM = (fix.latitude - _lastFixLat!) * _metresPerDegree;
        final dLonM = (fix.longitude - _lastFixLon!) *
            _metresPerDegree *
            cos(fix.latitude * pi / 180);
        final dist = sqrt(dLatM * dLatM + dLonM * dLonM);
        movedM = dist;
        final derivedSpeed = dist / dt;

        if (resolvedSpeed < 0.35 &&
            derivedSpeed >= 0.35 &&
            derivedSpeed < 70.0) {
          resolvedSpeed = derivedSpeed;
        }

        if (dist > 1.0) {
          final courseDeg = (atan2(dLonM, dLatM) * 180 / pi + 360) % 360;
          _heading = courseDeg;
          if (resolvedSpeed >= _courseMinSpeed) _courseDeg = courseDeg;
        }
      }
    }
    if (resolvedSpeed < _courseMinSpeed) _courseDeg = null;

    _lastFixLat = fix.latitude;
    _lastFixLon = fix.longitude;
    _lastFixAt = now;

    // A real fix ends whatever outage the marker was following a road through.
    if (!_simCanyon) _road.release();

    // While the core leads, a raw fix is a *measurement*, not the answer:
    // the filter has already gated it and folded in what survived. Writing
    // it straight to the marker here is exactly the teleport-on-one-bad-fix
    // behaviour the gate exists to prevent.
    if (isEngineLeading) return;

    _altitude = fix.altitude;
    if (_simCanyon) {
      final moving = fix.speed >= _canyonMovingSpeed ||
          movedM > max(_canyonMinMoveM, 3 * fix.accuracy);
      _applyCanyonFix(fix, resolvedSpeed, moving: moving);
      return;
    }
    _targetLat = fix.latitude;
    _targetLon = fix.longitude;
    _speed = resolvedSpeed < 0.35 ? 0 : resolvedSpeed;
  }

  /// Urban canyon: satellites heard through buildings are not trusted with the
  /// position - the road is. A fix only nudges where along the road the vehicle
  /// is, and only when it shows the vehicle really [moving]: a phone standing
  /// still (the emulator's, or any receiver's jitter) says nothing about
  /// progress, so the simulated cruise carries on. One fix off the road is
  /// ignored; only a run of them means another street. Without a road the fix
  /// itself is the position, as it would be with live GNSS - never a made-up
  /// wander around it.
  void _applyCanyonFix(GnssFix fix, double resolvedSpeed,
      {required bool moving}) {
    if (!moving) return;
    _speed = resolvedSpeed;
    if (!_road.isLocked) {
      if (_lockRoad(lat: fix.latitude, lon: fix.longitude)) return;
      _targetLat = fix.latitude;
      _targetLon = fix.longitude;
      return;
    }
    if (_road.correct(fix.latitude, fix.longitude, sigmaM: _accuracy)) {
      _canyonMisses = 0;
      _adoptRoadPosition();
      return;
    }
    if (++_canyonMisses < _canyonRelockAfter) return;
    _canyonMisses = 0;
    _lockRoad(lat: fix.latitude, lon: fix.longitude, keepIfFails: true);
  }

  void _seedFromLastKnown() {
    final seed = location.lastKnownFix;
    if (seed == null || location.hasBeenLive) return;
    _targetLat = _lat = seed.latitude;
    _targetLon = _lon = seed.longitude;
    _positionSeeded = true;
    _dirty = true;
    _touch();
    unawaited(_writeCache(seed.latitude, seed.longitude));
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
        _touch();
      }
    } catch (_) {}
  }

  void _maybeCache(GnssFix fix) {
    final now = _clock();
    final last = _lastCacheAt;
    if (last != null &&
        now.difference(last) < _cacheEvery &&
        _appliedFixCount > 1) return;
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
  MissionGuidanceDecision? get missionGuidance => _missionGuidance;

  /// Whether the marker is being held on a road of the installed map: true
  /// through an outage when there are roads around, false where there are none.
  bool get isOnRoad => _road.isLocked;
  bool get isSimulatingTunnel => _simTunnel;
  bool get isSimulatingCanyon => _simCanyon;
  VehicleProfile get vehicleProfile => _vehicleProfile;
  String? get anchorPackId => _anchorPack?.packId;

  double get speed => _speed;
  double get heading => _heading;
  double get latitude => _lat;
  double get longitude => _lon;
  double get altitude => _altitude;
  double get accuracy => _accuracy;

  LocationStatus get gnssStatus => location.status;

  /// Latest hardware-reported constellation status, or null until Android has
  /// produced one. Null is intentionally not replaced with demo values.
  GnssTelemetrySnapshot? get gnssTelemetry => _gnssTelemetry;
  GnssIntegrityAssessment get gnssIntegrity => _gnssIntegrity.assessment;
  List<double> get gnssCn0History => _gnssIntegrity.cn0History;

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

  /// The phone's model and OS, or null when the platform cannot say.
  Future<DeviceInfo?> deviceInfo() => _hardware.deviceInfo();

  /// Whether the app is still getting itself ready (sensors, motion model,
  /// satellites) and on what, for the sync capsule and loading states.
  SyncStatus get syncStatus => syncStatusOf(
        sensorsLive: isSensorLive,
        modelReady: isSpeedEstimatorReady,
        location: gnssStatus,
        reacquiring: fusionMode == FusionMode.reacquiring,
      );
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

  /// Up to three HMM road hypotheses while GNSS is unavailable. These are
  /// display corridors, not turn instructions.
  List<RoadCorridorModel> get roadCorridors {
    if (!inOutage) return const [];
    final candidates = _navSnapshot?.mapMatchResult?.candidates;
    if (candidates == null || candidates.isEmpty) return const [];
    return [
      for (final candidate in candidates.take(3))
        RoadCorridorModel(
          polyline: candidate.corridorPolyline,
          probability: candidate.posterior,
          roadName: candidate.roadName,
        ),
    ];
  }

  /// Latest navigation-core estimate, or null before it has one.
  ///
  /// Diagnostics only for now — the map marker still comes from the
  /// pipeline above (see [_engine]).
  NavigationSnapshot? get navSnapshot => _navSnapshot;

  NavMode get engineMode => _engine.mode;

  /// Mode transitions with their reasons, newest last.
  List<ModeTransition> get engineTransitions => _engine.transitions;

  /// True only once the core's phone-to-vehicle transform has converged.
  bool get isMountCalibrated => _navSnapshot?.isMountCalibrated ?? false;

  /// Mount-alignment confidence, or null while it is unknown.
  double? get mountConfidence => _navSnapshot?.alignmentConfidence;

  /// Evidence the mount alignment has gathered, for diagnostics (§79).
  int get alignmentSamples => _engine.alignmentSamples;
  int get alignmentEvents => _engine.alignmentEvents;
  bool get hasLevelling => _engine.hasLevelling;

  /// Mean microseconds the navigation core takes per sensor frame, or
  /// null before it has run. Measured, not estimated (§44).
  double? get engineMeanMicros =>
      _engineFeedCount == 0 ? null : _engineMicrosTotal / _engineFeedCount;

  int? get enginePeakMicros => _engineFeedCount == 0 ? null : _engineMicrosPeak;

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
