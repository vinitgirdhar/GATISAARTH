import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/gnss/gnss_telemetry.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

class FakeGnssTelemetrySource implements GnssTelemetrySource {
  final controller = StreamController<GnssTelemetrySnapshot>.broadcast();
  int starts = 0;
  int stops = 0;

  @override
  Stream<GnssTelemetrySnapshot> get snapshots => controller.stream;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async => stops++;

  Future<void> close() => controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeGnssTelemetrySource gnss;
  late LiveSessionController session;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    gnss = FakeGnssTelemetrySource();
    final hardware = FakeHardware();
    session = LiveSessionController(
      sensors: FakeSensors(),
      alignment: VehicleAlignmentEngine(),
      hardware: hardware,
      speedEstimator: FakeSpeed(),
      telemetry: FakeTelemetry(),
      location: LiveLocationService(
        gateway: FakeLocationGateway(),
        errorRetryDelay: Duration.zero,
      ),
      gnssTelemetry: gnss,
      autoTick: false,
      haptics: Haptics(hardware, pause: (_) async {}),
    );
  });

  tearDown(() async {
    session.dispose();
    await gnss.close();
  });

  test('session exposes only snapshots received from Android', () async {
    await session.start();
    expect(gnss.starts, 1);
    expect(session.gnssTelemetry, isNull);

    const snapshot = GnssTelemetrySnapshot(
      permissionGranted: true,
      statusSupported: true,
      rawMeasurementsSupported: true,
      satellites: [
        GnssSatellite(
          svid: 3,
          constellation: GnssConstellation.navic,
          cn0DbHz: 41,
          usedInFix: true,
        ),
      ],
    );
    gnss.controller.add(snapshot);
    await Future<void>.delayed(Duration.zero);

    expect(session.gnssTelemetry, same(snapshot));
    expect(session.gnssTelemetry!.countFor(GnssConstellation.navic), 1);
  });

  test('GNSS status listener follows app pause and resume', () async {
    await session.start();
    await session.pause();
    expect(gnss.stops, 1);

    await session.resume();
    expect(gnss.starts, 2);
  });
}
