import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/anchors/radio_anchor.dart';
import 'package:gatisaarth/core/platform/radio/wifi_rtt_anchor_source.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'portal_anchor_integration_test.dart' show TestAnchorPackSource;
import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

class _RadioSource implements WifiRttAnchorSource {
  @override
  Future<RadioAnchorObservation?> range(String radioId) async =>
      RadioAnchorObservation(
        radioId: radioId,
        rangeM: 4,
        rangeSigmaM: 2,
        age: const Duration(milliseconds: 100),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('radio measurement cannot bypass the outage safety gate', () async {
    SharedPreferences.setMockInitialValues({});
    final hardware = FakeHardware();
    final session = LiveSessionController(
      sensors: FakeSensors(),
      alignment: VehicleAlignmentEngine(),
      hardware: hardware,
      speedEstimator: FakeSpeed(),
      telemetry: FakeTelemetry(),
      location: LiveLocationService(
        gateway: FakeLocationGateway(),
        errorRetryDelay: Duration.zero,
      ),
      anchorPacks: TestAnchorPackSource(),
      radioAnchors: _RadioSource(),
      autoTick: false,
      haptics: Haptics(hardware, pause: (_) async {}),
    );
    addTearDown(session.dispose);
    await session.start();
    final result = await session.rangeRadioAnchor();
    expect(result.accepted, isFalse);
    expect(result.message, contains('outage'));
  });
}
