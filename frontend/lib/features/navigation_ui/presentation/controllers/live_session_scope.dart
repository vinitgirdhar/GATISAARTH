import 'package:flutter/widgets.dart';

import '../../../../core/platform/hardware/device_hardware_service.dart';
import '../../../../core/platform/guidance/voice_guidance.dart';
import '../../../../core/platform/anchors/anchor_pack_source.dart';
import '../../../../core/platform/activity/activity_mode_source.dart';
import '../../../../core/platform/radio/wifi_rtt_anchor_source.dart';
import '../../../../core/platform/gnss/gnss_telemetry.dart';
import '../../../../core/platform/hardware/sensor_mobile.dart';
import '../../../../core/platform/hardware/vehicle_alignment_engine.dart';
import '../../../../core/platform/location/geolocator_gateway.dart';
import '../../../../core/platform/location/live_location_service.dart';
import '../../../../core/platform/maps/offline_map_service.dart';
import '../../../../core/platform/maps/pack_road_source.dart';
import '../../../../core/platform/network/telemetry_sink.dart';
import '../../../ai_motion/data/datasources/ml_speed_estimator.dart';
import 'live_session_controller.dart';

/// Builds the production session: real sensors, GPS, neural model and the
/// optional backend link. [maps] are the installed offline map packs; dead
/// reckoning follows the roads read from them.
LiveSessionController createLiveSession({OfflineMapService? maps}) =>
    LiveSessionController(
      sensors: MobileSensorDriver(),
      alignment: VehicleAlignmentEngine(),
      hardware: DeviceHardwareService(),
      speedEstimator: MlSpeedEstimator(),
      telemetry: BackendTelemetrySink(),
      location: LiveLocationService(
        gateway: const GeolocatorGateway(),
        staleAfter: const Duration(seconds: 18),
      ),
      gnssTelemetry: PlatformGnssTelemetrySource(),
      voiceGuidance: const PlatformVoiceGuidance(),
      anchorPacks: const InstalledAnchorPackSource(),
      activityModes: PlatformActivityModeSource(),
      radioAnchors: const PlatformWifiRttAnchorSource(),
      roads: maps == null ? null : PackRoadGraphSource(maps),
    );

/// Makes the one [LiveSessionController] available to every screen.
class LiveSessionScope extends InheritedNotifier<LiveSessionController> {
  const LiveSessionScope({
    super.key,
    required LiveSessionController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Subscribes the caller: it rebuilds whenever the session notifies
  /// (at most 10 times a second).
  static LiveSessionController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LiveSessionScope>();
    assert(scope != null, 'No LiveSessionScope above this context');
    return scope!.notifier!;
  }
}
