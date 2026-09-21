import '../ai/ai_types.dart';
import '../gnss/gnss_quality.dart';
import '../math/nav_math.dart';
import 'drive_log.dart';

/// Records a drive as JSONL (§36).
///
/// IO-free on purpose: it hands finished lines to a sink, so the navigation
/// core never touches the file system and a recorder can be unit-tested,
/// streamed to a socket, or buffered in memory without changing.
///
/// Bounded by construction. A 50 Hz drive writes about 6 KB/s, so an
/// unattended recorder would fill a phone overnight; [maxRecords] and
/// [maxBytes] stop it, and [droppedRecords] says how much was lost rather
/// than silently truncating (§46).
class DriveRecorder {
  DriveRecorder({
    required this.sink,
    this.maxRecords = 2000000,
    this.maxBytes = 256 * 1024 * 1024,
    this.imuDecimation = 1,
  }) : assert(imuDecimation >= 1);

  /// Receives one finished JSONL line, without its newline.
  final void Function(String line) sink;

  final int maxRecords;
  final int maxBytes;

  /// Write only every Nth IMU frame. 1 records everything, which is what a
  /// replay needs; higher values trade fidelity for size on long drives.
  final int imuDecimation;

  bool _recording = false;
  bool _wroteMeta = false;
  int _records = 0;
  int _bytes = 0;
  int _dropped = 0;
  int _imuSeen = 0;
  int? _firstUs;
  int? _lastUs;
  final Map<String, int> _counts = {};

  bool get isRecording => _recording;
  int get recordCount => _records;
  int get byteCount => _bytes;
  int get droppedRecords => _dropped;

  /// True once a limit has been hit and recording has stopped itself.
  bool get isFull => _records >= maxRecords || _bytes >= maxBytes;

  Duration get duration => (_firstUs == null || _lastUs == null)
      ? Duration.zero
      : Duration(microseconds: _lastUs! - _firstUs!);

  /// How many of each record type were written, for the session summary.
  Map<String, int> get counts => Map.unmodifiable(_counts);

  void start(DriveMeta meta) {
    if (_recording) return;
    _recording = true;
    if (!_wroteMeta) {
      _wroteMeta = true;
      _write(DriveRecord(
        type: DriveRecordType.meta,
        monotonicUs: 0,
        meta: meta.toJson(),
      ));
    }
  }

  void stop() => _recording = false;

  void recordImu({
    required int monotonicUs,
    required Vector3 accel,
    required Vector3 gyro,
    Vector3? mag,
    double? pressureHpa,
    double? temperatureC,
  }) {
    if (!_recording) return;
    _imuSeen++;
    if (_imuSeen % imuDecimation != 0) return;
    _write(DriveRecord.imu(
      monotonicUs: monotonicUs,
      accel: accel,
      gyro: gyro,
      mag: mag,
      pressureHpa: pressureHpa,
      temperatureC: temperatureC,
    ));
  }

  /// Records every fix, accepted or rejected. A replay that only saw the good
  /// ones could never reproduce the rejection decisions.
  void recordGnss(GnssObservation fix) {
    if (!_recording) return;
    _write(DriveRecord.gnss(fix));
  }

  void recordGnssLost(int monotonicUs) {
    if (!_recording) return;
    _write(DriveRecord.gnssLost(monotonicUs));
  }

  void recordTruth({
    required int monotonicUs,
    required double latitude,
    required double longitude,
    double? headingDeg,
    double? speedMps,
  }) {
    if (!_recording) return;
    _write(DriveRecord.truth(
      monotonicUs: monotonicUs,
      latitude: latitude,
      longitude: longitude,
      headingDeg: headingDeg,
      speedMps: speedMps,
    ));
  }

  /// Records the model outputs pushed to the engine (any subset of the three
  /// groups), stamped [monotonicUs] like the IMU frame they describe. Written
  /// *after* that frame's IMU line, which is the order the engine saw them in, so
  /// a replay reproduces the run exactly.
  void recordAi({
    required int monotonicUs,
    AiSpeedObservation? speed,
    DisturbanceEstimate? disturbance,
    FusionConfidence? fusion,
  }) {
    if (!_recording) return;
    if (speed == null && disturbance == null && fusion == null) return;
    _write(DriveRecord.ai(
      monotonicUs: monotonicUs,
      speed: speed,
      disturbance: disturbance,
      fusion: fusion,
    ));
  }

  /// Labels an event: tunnel entry, pothole, GNSS loss, a driver's button
  /// press (§42, §53).
  void recordMarker({required int monotonicUs, required String label}) {
    if (!_recording) return;
    _write(DriveRecord.marker(monotonicUs: monotonicUs, label: label));
  }

  void _write(DriveRecord record) {
    if (isFull) {
      _dropped++;
      _recording = false;
      return;
    }
    final line = record.toJsonLine();
    sink(line);
    _records++;
    _bytes += line.length + 1;
    _counts[record.type.name] = (_counts[record.type.name] ?? 0) + 1;
    if (record.type != DriveRecordType.meta) {
      _firstUs ??= record.monotonicUs;
      _lastUs = record.monotonicUs;
    }
  }
}

/// Collects lines in memory. For tests and short sessions; a real drive writes
/// straight to a file through the platform layer.
class MemoryLogSink {
  final List<String> lines = [];

  void call(String line) => lines.add(line);

  String get text => lines.join('\n');

  int get byteCount => text.length;
}
