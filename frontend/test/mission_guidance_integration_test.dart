import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/platform/guidance/voice_guidance.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_location_gateway.dart';
import 'support/session_fakes.dart';

class _Voice implements VoiceGuidance {
  final spoken = <String>[];

  @override
  Future<void> speak(String message) async => spoken.add(message);

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('live session speaks safe outage guidance once and exposes it to UI',
      () async {
    SharedPreferences.setMockInitialValues({});
    final voice = _Voice();
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
      voiceGuidance: voice,
      autoTick: false,
      haptics: Haptics(hardware, pause: (_) async {}),
    );
    addTearDown(session.dispose);
    await session.start();

    session.startTunnelTest();
    await Future<void>.delayed(Duration.zero);
    session.tick();
    await Future<void>.delayed(Duration.zero);

    expect(voice.spoken, hasLength(1));
    expect(voice.spoken.single, contains('GNSS lost'));
    expect(session.missionGuidance?.display, contains('Outage mission'));
    session.tick();
    await Future<void>.delayed(Duration.zero);
    expect(voice.spoken, hasLength(1), reason: 'no repeated driver distraction');
  });
}
