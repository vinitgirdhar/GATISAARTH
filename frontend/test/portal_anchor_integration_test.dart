import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/anchors/anchor_pack.dart';
import 'package:gatisaarth/core/platform/anchors/anchor_pack_source.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

class _PackSource implements AnchorPackSource {
  @override
  Future<AnchorPack> load() async => AnchorPack.parse('''
{"schemaVersion":1,"packId":"test-pack","anchors":[
 {"id":"portal-a","label":"Portal A","kind":"tunnelPortal","lat":28.639,"lon":77.0661,"sigmaM":4,"visualDescriptor":"f0f0","radioId":"GS-DEMO-A"}
]}''');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('session loads the local pack and safely rejects a scan outside outage',
      () async {
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
      anchorPacks: _PackSource(),
      autoTick: false,
      haptics: Haptics(hardware, pause: (_) async {}),
    );
    addTearDown(session.dispose);
    await session.start();

    expect(session.anchorPackId, 'test-pack');
    final result = session.applyPortalPayload('GSARTH-ANCHOR:1:portal-a');
    expect(result.accepted, isFalse);
    expect(result.message, contains('outage'));
  });
}
