import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/app_widget.dart';
import 'package:gatisaarth/core/platform/hardware/haptics.dart';
import 'package:gatisaarth/core/platform/hardware/vehicle_alignment_engine.dart';
import 'package:gatisaarth/core/platform/location/live_location_service.dart';
import 'package:gatisaarth/core/platform/maps/map_download_service.dart';
import 'package:gatisaarth/core/platform/maps/offline_map_service.dart';
import 'package:gatisaarth/core/platform/maps/pack_installer.dart';
import 'package:gatisaarth/core/platform/maps/region_extractor.dart';
import 'package:gatisaarth/core/platform/maps/offline_catalog.dart';
import 'package:gatisaarth/core/router/app_router.dart';
import 'package:gatisaarth/core/theme/theme_controller.dart';
import 'package:gatisaarth/features/navigation_ui/presentation/controllers/live_session_controller.dart';

import 'fake_location_gateway.dart';
import 'session_fakes.dart';

/// West Delhi, the point most of the app's tests use.
const GnssFix delhiFix = GnssFix(
  latitude: 28.639,
  longitude: 77.0661,
  altitude: 200,
  accuracy: 5,
  speed: 0,
);

/// Pune city centre.
const GnssFix puneFix = GnssFix(
  latitude: 18.5204,
  longitude: 73.8567,
  altitude: 560,
  accuracy: 5,
  speed: 0,
);

/// A whole app on fake sensors and a fake GPS.
class AppHarness {
  AppHarness() {
    controller = LiveSessionController(
      sensors: sensors,
      alignment: VehicleAlignmentEngine(),
      hardware: FakeHardware(),
      speedEstimator: FakeSpeed(),
      telemetry: FakeTelemetry(),
      location: LiveLocationService(
        gateway: gateway,
        clock: () => now,
        errorRetryDelay: Duration.zero,
      ),
      clock: () => now,
      autoTick: false,
      haptics: Haptics(FakeHardware(), clock: () => now, pause: (_) async {}),
    );
  }

  final FakeSensors sensors = FakeSensors();
  final FakeLocationGateway gateway = FakeLocationGateway();
  DateTime now = DateTime(2026, 9, 20, 12);
  late final LiveSessionController controller;

  /// Delivers a GPS fix and lets the session see it. Uses frames, not real
  /// timers: a widget test's clock is fake.
  Future<void> fix(WidgetTester tester, GnssFix f) async {
    gateway.fixController.add(f);
    await tester.pump();
    controller.tick();
    await tester.pump();
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    String route = AppRoutes.dashboard,
    ThemeController? theme,
    OfflineMapService? maps,
    MapDownloadService? downloads,
    bool animateTheme = false,
    Size size = const Size(411, 915),
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GatiSaarthApp(
      session: controller,
      theme: theme,
      initialRoute: route,
      animateTheme: animateTheme,
      offlineMaps: maps,
      mapDownloads: downloads,
    ));
    await tester.pump();
  }
}

/// Runs real frames in bounded steps: a screen with a sync spinner or a
/// running map never "settles".
Future<void> frames(WidgetTester tester, {int count = 10, int ms = 100}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

/// Answers `getTemporaryDirectory` and friends, which the vector map's file
/// cache asks for, with a real temporary folder.
Directory mockPathProvider() {
  final dir = Directory.systemTemp.createTempSync('path_provider_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => dir.path,
  );
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return dir;
}

/// Pretends to download: writes a small file into [folder] instead of touching
/// the network. Can be held open or told to fail.
class FakeInstaller extends PackInstaller {
  FakeInstaller(this.folder) : super(folder: () async => folder);

  final Directory folder;
  final List<String> started = [];
  Object? failWith;
  Future<void>? hold;

  @override
  Future<File> install(
    OfflinePack pack, {
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    started.add(pack.id);
    onProgress?.call(0.4);
    await hold;
    cancel?.throwIfCancelled();
    if (failWith != null) throw failWith!;
    onProgress?.call(1);
    folder.createSync(recursive: true);
    return File('${folder.path}/${pack.fileName}')..writeAsBytesSync([1, 2, 3]);
  }

  @override
  Future<void> cleanUp() async {}

  /// Synchronous file calls: the widget tests' fake clock does not drive real
  /// file I/O.
  @override
  Future<bool> remove(File file) async {
    if (!file.existsSync()) return false;
    file.deleteSync();
    return true;
  }
}
