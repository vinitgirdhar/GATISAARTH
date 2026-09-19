import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../gnss/gnss_quality.dart';
import '../math/nav_math.dart';

/// What a line of a drive log holds (§36).
enum DriveRecordType {
  /// One-off header: device, config, vehicle, wall-clock start.
  meta,

  /// Raw phone-frame IMU frame.
  imu,

  /// A GNSS fix as received, accepted or not.
  gnss,

  /// GNSS became unavailable (switched off, permission lost, tunnel).
  gnssLost,

  /// Ground truth, when a drive has any (simulated runs, or a survey-grade
  /// reference logged alongside).
  truth,

  /// A labelled event: tunnel entry, pothole, the driver pressing a button
  /// (§42 event labels).
  marker,
}

/// One line of a drive log.
///
/// Deliberately flat and close to the wire format: a log is written at sensor
/// rate for hours, so every field costs megabytes.
@immutable
class DriveRecord {
  const DriveRecord({
    required this.type,
    required this.monotonicUs,
    this.accel,
    this.gyro,
    this.mag,
    this.pressureHpa,
    this.temperatureC,
    this.fix,
    this.latitude,
    this.longitude,
    this.headingDeg,
    this.speedMps,
    this.label,
    this.meta,
  });

  factory DriveRecord.imu({
    required int monotonicUs,
    required Vector3 accel,
    required Vector3 gyro,
    Vector3? mag,
    double? pressureHpa,
    double? temperatureC,
  }) =>
      DriveRecord(
        type: DriveRecordType.imu,
        monotonicUs: monotonicUs,
        accel: accel,
        gyro: gyro,
        mag: mag,
        pressureHpa: pressureHpa,
        temperatureC: temperatureC,
      );

  factory DriveRecord.gnss(GnssObservation fix) => DriveRecord(
        type: DriveRecordType.gnss,
        monotonicUs: fix.monotonicUs,
        fix: fix,
      );

  factory DriveRecord.gnssLost(int monotonicUs) => DriveRecord(
        type: DriveRecordType.gnssLost,
        monotonicUs: monotonicUs,
      );

  factory DriveRecord.truth({
    required int monotonicUs,
    required double latitude,
    required double longitude,
    double? headingDeg,
    double? speedMps,
  }) =>
      DriveRecord(
        type: DriveRecordType.truth,
        monotonicUs: monotonicUs,
        latitude: latitude,
        longitude: longitude,
        headingDeg: headingDeg,
        speedMps: speedMps,
      );

  factory DriveRecord.marker({
    required int monotonicUs,
    required String label,
  }) =>
      DriveRecord(
        type: DriveRecordType.marker,
        monotonicUs: monotonicUs,
        label: label,
      );

  final DriveRecordType type;
  final int monotonicUs;

  final Vector3? accel;
  final Vector3? gyro;
  final Vector3? mag;
  final double? pressureHpa;
  final double? temperatureC;

  final GnssObservation? fix;

  final double? latitude;
  final double? longitude;
  final double? headingDeg;
  final double? speedMps;

  final String? label;
  final Map<String, dynamic>? meta;

  /// Encodes to one JSON line.
  ///
  /// Doubles go out at full precision. Dart's encoder writes the shortest
  /// representation that round-trips exactly, so a replay reproduces the live
  /// run bit for bit — which is the whole point of having a log (§37). Rounding
  /// to "sensible" decimals here would quietly make replay a different
  /// experiment from the drive.
  String toJsonLine() => jsonEncode(toJson());

  Map<String, dynamic> toJson() {
    switch (type) {
      case DriveRecordType.meta:
        return {'t': 'm', 'u': monotonicUs, if (meta != null) ...meta!};
      case DriveRecordType.imu:
        return {
          't': 'i',
          'u': monotonicUs,
          'a': [accel!.x, accel!.y, accel!.z],
          'g': [gyro!.x, gyro!.y, gyro!.z],
          if (mag != null) 'm': [mag!.x, mag!.y, mag!.z],
          if (pressureHpa != null) 'p': pressureHpa,
          if (temperatureC != null) 'c': temperatureC,
        };
      case DriveRecordType.gnss:
        final f = fix!;
        return {
          't': 'g',
          'u': monotonicUs,
          'lat': f.latitudeDeg,
          'lon': f.longitudeDeg,
          'acc': f.accuracyM,
          if (f.altitudeM != null) 'alt': f.altitudeM,
          if (f.speedMps != null) 'spd': f.speedMps,
          if (f.speedAccuracyMps != null) 'sac': f.speedAccuracyMps,
          if (f.bearingDeg != null) 'brg': f.bearingDeg,
          if (f.bearingAccuracyDeg != null) 'bac': f.bearingAccuracyDeg,
          if (f.verticalAccuracyM != null) 'vac': f.verticalAccuracyM,
          if (f.satellitesUsed != null) 'sat': f.satellitesUsed,
          if (f.isMocked) 'mock': true,
        };
      case DriveRecordType.gnssLost:
        return {'t': 'x', 'u': monotonicUs};
      case DriveRecordType.truth:
        return {
          't': 'r',
          'u': monotonicUs,
          'lat': latitude,
          'lon': longitude,
          if (headingDeg != null) 'hdg': headingDeg,
          if (speedMps != null) 'spd': speedMps,
        };
      case DriveRecordType.marker:
        return {'t': 'k', 'u': monotonicUs, 'l': label};
    }
  }

  /// Parses one line. Returns null for anything unreadable rather than
  /// throwing: a truncated log (battery died mid-drive) should replay up to
  /// the point it was truncated, not fail wholesale.
  static DriveRecord? fromJsonLine(String line) {
    if (line.trim().isEmpty) return null;
    try {
      final json = jsonDecode(line);
      if (json is! Map<String, dynamic>) return null;
      return fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static DriveRecord? fromJson(Map<String, dynamic> json) {
    final us = (json['u'] as num?)?.toInt();
    if (us == null) return null;

    switch (json['t']) {
      case 'm':
        return DriveRecord(
          type: DriveRecordType.meta,
          monotonicUs: us,
          meta: {
            for (final entry in json.entries)
              if (entry.key != 't' && entry.key != 'u') entry.key: entry.value,
          },
        );
      case 'i':
        final a = _vec(json['a']);
        final g = _vec(json['g']);
        if (a == null || g == null) return null;
        return DriveRecord(
          type: DriveRecordType.imu,
          monotonicUs: us,
          accel: a,
          gyro: g,
          mag: _vec(json['m']),
          pressureHpa: (json['p'] as num?)?.toDouble(),
          temperatureC: (json['c'] as num?)?.toDouble(),
        );
      case 'g':
        final lat = (json['lat'] as num?)?.toDouble();
        final lon = (json['lon'] as num?)?.toDouble();
        final acc = (json['acc'] as num?)?.toDouble();
        if (lat == null || lon == null || acc == null) return null;
        return DriveRecord(
          type: DriveRecordType.gnss,
          monotonicUs: us,
          fix: GnssObservation(
            latitudeDeg: lat,
            longitudeDeg: lon,
            accuracyM: acc,
            monotonicUs: us,
            altitudeM: (json['alt'] as num?)?.toDouble(),
            speedMps: (json['spd'] as num?)?.toDouble(),
            speedAccuracyMps: (json['sac'] as num?)?.toDouble(),
            bearingDeg: (json['brg'] as num?)?.toDouble(),
            bearingAccuracyDeg: (json['bac'] as num?)?.toDouble(),
            verticalAccuracyM: (json['vac'] as num?)?.toDouble(),
            satellitesUsed: (json['sat'] as num?)?.toInt(),
            isMocked: json['mock'] == true,
          ),
        );
      case 'x':
        return DriveRecord(
          type: DriveRecordType.gnssLost,
          monotonicUs: us,
        );
      case 'r':
        final lat = (json['lat'] as num?)?.toDouble();
        final lon = (json['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) return null;
        return DriveRecord(
          type: DriveRecordType.truth,
          monotonicUs: us,
          latitude: lat,
          longitude: lon,
          headingDeg: (json['hdg'] as num?)?.toDouble(),
          speedMps: (json['spd'] as num?)?.toDouble(),
        );
      case 'k':
        final label = json['l'];
        if (label is! String) return null;
        return DriveRecord(
          type: DriveRecordType.marker,
          monotonicUs: us,
          label: label,
        );
      default:
        return null;
    }
  }

  static Vector3? _vec(Object? raw) {
    if (raw is! List || raw.length != 3) return null;
    final values = raw.whereType<num>().map((n) => n.toDouble()).toList();
    if (values.length != 3) return null;
    return Vector3(values[0], values[1], values[2]);
  }
}

/// Header of a drive log (§42 dataset metadata, §43 device profile).
@immutable
class DriveMeta {
  const DriveMeta({
    required this.sessionId,
    required this.startedAtMs,
    this.deviceModel,
    this.osVersion,
    this.appVersion,
    this.vehicle,
    this.mountDescription,
    this.roadType,
    this.weather,
    this.configVersion,
    this.notes,
  });

  final String sessionId;
  final int startedAtMs;

  /// Null when unknown. Never a plausible-looking placeholder.
  final String? deviceModel;
  final String? osVersion;
  final String? appVersion;
  final String? vehicle;
  final String? mountDescription;

  /// Manually tagged, so null unless the driver actually said (§42).
  final String? roadType;
  final String? weather;

  final int? configVersion;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'sid': sessionId,
        'start': startedAtMs,
        if (deviceModel != null) 'dev': deviceModel,
        if (osVersion != null) 'os': osVersion,
        if (appVersion != null) 'app': appVersion,
        if (vehicle != null) 'veh': vehicle,
        if (mountDescription != null) 'mount': mountDescription,
        if (roadType != null) 'road': roadType,
        if (weather != null) 'wx': weather,
        if (configVersion != null) 'cfg': configVersion,
        if (notes != null) 'note': notes,
      };

  static DriveMeta? fromJson(Map<String, dynamic> json) {
    final sessionId = json['sid'];
    final start = (json['start'] as num?)?.toInt();
    if (sessionId is! String || start == null) return null;
    return DriveMeta(
      sessionId: sessionId,
      startedAtMs: start,
      deviceModel: json['dev'] as String?,
      osVersion: json['os'] as String?,
      appVersion: json['app'] as String?,
      vehicle: json['veh'] as String?,
      mountDescription: json['mount'] as String?,
      roadType: json['road'] as String?,
      weather: json['wx'] as String?,
      configVersion: (json['cfg'] as num?)?.toInt(),
      notes: json['note'] as String?,
    );
  }
}
