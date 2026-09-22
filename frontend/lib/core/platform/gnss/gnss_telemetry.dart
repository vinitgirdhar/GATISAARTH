import 'package:flutter/foundation.dart';

/// Satellite systems reported by Android's `GnssStatus` API.
enum GnssConstellation {
  unknown,
  gps,
  sbas,
  glonass,
  qzss,
  beidou,
  galileo,
  navic;

  static GnssConstellation fromAndroidType(int type) => switch (type) {
        1 => GnssConstellation.gps,
        2 => GnssConstellation.sbas,
        3 => GnssConstellation.glonass,
        4 => GnssConstellation.qzss,
        5 => GnssConstellation.beidou,
        6 => GnssConstellation.galileo,
        7 => GnssConstellation.navic,
        _ => GnssConstellation.unknown,
      };
}

@immutable
class GnssSatellite {
  const GnssSatellite({
    required this.svid,
    required this.constellation,
    required this.cn0DbHz,
    required this.usedInFix,
    this.elevationDegrees,
    this.azimuthDegrees,
    this.carrierFrequencyHz,
  });

  final int svid;
  final GnssConstellation constellation;
  final double cn0DbHz;
  final bool usedInFix;
  final double? elevationDegrees;
  final double? azimuthDegrees;
  final double? carrierFrequencyHz;

  /// Human-readable RF band where Android exposes carrier frequency.
  String? get carrierBand {
    final mhz = carrierFrequencyHz == null ? null : carrierFrequencyHz! / 1e6;
    if (mhz == null || !mhz.isFinite) return null;
    if ((mhz - 1176.45).abs() < 15) return 'L5';
    if ((mhz - 1575.42).abs() < 15) return 'L1';
    if ((mhz - 2492.028).abs() < 25) return 'S';
    return '${mhz.toStringAsFixed(1)} MHz';
  }
}

/// One truthful view of the Android GNSS receiver.
///
/// An empty list means Android reported no satellites; it is never populated
/// with demo values. Capability flags let the UI distinguish that from a
/// missing permission or a device without the relevant API.
@immutable
class GnssTelemetrySnapshot {
  const GnssTelemetrySnapshot({
    required this.permissionGranted,
    required this.statusSupported,
    required this.rawMeasurementsSupported,
    required this.satellites,
    this.recordedAt,
  });

  factory GnssTelemetrySnapshot.fromPlatformMap(Map<Object?, Object?> map) {
    final rawSatellites = map['satellites'];
    final satellites = <GnssSatellite>[];
    if (rawSatellites is List) {
      for (final raw in rawSatellites) {
        if (raw is! Map) continue;
        final satellite = _parseSatellite(raw);
        if (satellite != null) satellites.add(satellite);
      }
    }

    final timestampMs = _finiteInt(map['timestampMs']);
    return GnssTelemetrySnapshot(
      permissionGranted: map['permissionGranted'] == true,
      statusSupported: map['statusSupported'] == true,
      rawMeasurementsSupported: map['rawMeasurementsSupported'] == true,
      satellites: List.unmodifiable(satellites),
      recordedAt: timestampMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
  }

  final bool permissionGranted;
  final bool statusSupported;
  final bool rawMeasurementsSupported;
  final List<GnssSatellite> satellites;
  final DateTime? recordedAt;

  bool get hasRealStatus => permissionGranted && statusSupported;
  int get visibleCount => satellites.length;
  int get usedInFixCount => satellites.where((s) => s.usedInFix).length;

  int countFor(GnssConstellation constellation) =>
      satellites.where((s) => s.constellation == constellation).length;

  int usedCountFor(GnssConstellation constellation) => satellites
      .where((s) => s.constellation == constellation && s.usedInFix)
      .length;

  double? meanCn0For(GnssConstellation constellation) {
    final matching = satellites
        .where((s) => s.constellation == constellation)
        .map((s) => s.cn0DbHz)
        .toList(growable: false);
    if (matching.isEmpty) return null;
    return matching.reduce((a, b) => a + b) / matching.length;
  }

  static GnssSatellite? _parseSatellite(Map<Object?, Object?> map) {
    final svid = _finiteInt(map['svid']);
    final constellationCode = _finiteInt(map['constellation']);
    final cn0 = _finiteDouble(map['cn0DbHz']);
    if (svid == null || constellationCode == null || cn0 == null) return null;
    final constellation = GnssConstellation.fromAndroidType(constellationCode);
    if (constellation == GnssConstellation.unknown) return null;
    return GnssSatellite(
      svid: svid,
      constellation: constellation,
      cn0DbHz: cn0,
      usedInFix: map['usedInFix'] == true,
      elevationDegrees: _finiteDouble(map['elevationDegrees']),
      azimuthDegrees: _finiteDouble(map['azimuthDegrees']),
      carrierFrequencyHz: _finiteDouble(map['carrierFrequencyHz']),
    );
  }

  static double? _finiteDouble(Object? value) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }

  static int? _finiteInt(Object? value) {
    if (value is! num) return null;
    final result = value.toDouble();
    if (!result.isFinite || result != result.truncateToDouble()) return null;
    return result.toInt();
  }
}
