import 'package:flutter/foundation.dart';

import '../nav_config.dart';

/// The floor the vehicle is on, relative to where GNSS was lost.
@immutable
class ParkingLevel {
  const ParkingLevel({required this.level, required this.heightM});

  /// 0 = the entry level, -1 = one floor below it, +1 one above.
  final int level;

  /// Barometric height relative to the entry (m).
  final double heightM;

  /// "Entry level", "B2" below the entry, "L1" above it.
  String get label => level == 0
      ? 'Entry level'
      : level < 0
          ? 'B${-level}'
          : 'L$level';
}

/// Counts car-park floors from barometric height once GNSS is lost.
///
/// The entry (where GNSS went) is level 0; the level only changes once the
/// height sits beyond half a floor plus a hysteresis margin from the current
/// level, so a ramp wobble or a slammed door never flips it. Height *change* is
/// what a phone barometer measures well (see `BarometerProcessor`), and a car
/// park is minutes long, so weather drift does not matter here.
class ParkingLevelTracker {
  ParkingLevelTracker({NavConfig config = NavConfig.defaults})
      : _c = config.parkingLevel;

  final ParkingLevelConfig _c;
  double? _entryM;
  int _level = 0;
  ParkingLevel? _current;

  ParkingLevel? get current => _current;
  bool get isTracking => _entryM != null;

  /// GNSS was just lost at barometric height [relativeAltitudeM].
  void markEntry(double relativeAltitudeM) {
    _entryM = relativeAltitudeM;
    _level = 0;
    _current = ParkingLevel(level: 0, heightM: 0);
  }

  ParkingLevel? update(double relativeAltitudeM) {
    final entry = _entryM;
    if (entry == null || !relativeAltitudeM.isFinite) return _current;
    final h = relativeAltitudeM - entry;
    final floors = h / _c.floorHeightM;
    final threshold = 0.5 + _c.hysteresis;
    while (floors - _level > threshold) {
      _level++;
    }
    while (_level - floors > threshold) {
      _level--;
    }
    return _current = ParkingLevel(level: _level, heightM: h);
  }

  /// GNSS is back: the car park is behind us.
  void clear() {
    _entryM = null;
    _level = 0;
    _current = null;
  }
}
