import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/hardware/sensor_mobile.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/maps/offline_tile_provider.dart';
import 'package:gatisaarth/features/navigation_engine/domain/entities/navigation_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mount tilt', () {
    test('says nothing until it has seen enough samples', () {
      final tilt = VehicleAlignmentEngine();
      for (var i = 0; i < 5; i++) {
        tilt.addAccelerometer(0, 0, 9.81);
      }
      expect(tilt.isCalibrated, isFalse);
    });

    test('a phone lying flat has no pitch or roll', () {
      final tilt = VehicleAlignmentEngine();
      for (var i = 0; i < 300; i++) {
        tilt.addAccelerometer(0, 0, 9.81);
      }
      expect(tilt.isCalibrated, isTrue);
      expect(tilt.pitch, closeTo(0, 1e-6));
      expect(tilt.roll, closeTo(0, 1e-6));
    });

    test('a phone stood on its side in the mount reads 90° of roll', () {
      final tilt = VehicleAlignmentEngine();
      for (var i = 0; i < 600; i++) {
        tilt.addAccelerometer(0, 9.81, 0);
      }
      expect(tilt.roll, closeTo(math.pi / 2, 0.02));
    });

    test('a single jolt barely moves the estimate', () {
      final tilt = VehicleAlignmentEngine();
      for (var i = 0; i < 300; i++) {
        tilt.addAccelerometer(0, 0, 9.81);
      }
      tilt.addAccelerometer(6, 0, 9.81);
      expect(tilt.pitch.abs(), lessThan(0.02));
    });
  });

  group('raster tiles', () {
    test('no key is compiled in, so a tile never goes to the network', () {
      expect(BundledOfflineTileProvider.hasNetworkSource, isFalse);
    });

    test('an uncached tile is resolved by the provider itself, not an asset',
        () {
      final image = BundledOfflineTileProvider().getImage(
        const TileCoordinates(1, 2, 3),
        TileLayer(urlTemplate: 'https://tiles.invalid/{z}/{x}/{y}.png'),
      );
      expect(image.runtimeType.toString(), '_RasterTile');
    });
  });

  test('pressure altitude follows the standard atmosphere', () {
    expect(MobileSensorDriver.altitudeFor(1013.25), closeTo(0, 1e-9));
    expect(MobileSensorDriver.altitudeFor(899.0), closeTo(998, 3));
    expect(MobileSensorDriver.altitudeFor(double.nan), isNaN);
  });

  test('every fusion mode has a readable label and a stable code', () {
    for (final mode in FusionMode.values) {
      expect(mode.label, isNotEmpty);
      expect(mode.nameString, matches(RegExp(r'^[A-Z_]+$')));
    }
  });
}
