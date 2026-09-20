import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/router/app_router.dart';
import 'core/constants/dr_constants.dart';
import 'core/platform/maps/map_download_service.dart';
import 'core/platform/maps/offline_map_service.dart';
import 'core/platform/maps/pack_installer.dart';
import 'core/widgets/soft_overscroll.dart';
import 'core/widgets/theme_transition.dart';
import 'features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'features/navigation_ui/presentation/controllers/live_session_scope.dart';

class GatiSaarthApp extends StatefulWidget {
  const GatiSaarthApp({
    Key? key,
    this.session,
    this.theme,
    this.initialRoute,
    this.animateTheme = true,
    this.offlineMaps,
    this.mapDownloads,
    this.promptForMaps = false,
  }) : super(key: key);

  /// Injected in tests; production builds the real session.
  final LiveSessionController? session;

  /// Injected in tests; production loads the saved brightness in `main`.
  final ThemeController? theme;

  /// Injected by widget tests that want to land straight on a screen instead
  /// of sitting through the boot sequence.
  final String? initialRoute;

  /// Wipe the new brightness in over a frozen picture of the old one. Tests
  /// that only care about the end state turn it off.
  final bool animateTheme;

  /// Injected in tests; production scans for the offline map archives.
  final OfflineMapService? offlineMaps;

  /// Injected in tests; production downloads from the Protomaps build.
  final MapDownloadService? mapDownloads;

  /// Ask "download maps for where you are?" on the first position. `main` turns
  /// it on; it is off by default so tests do not meet the sheet.
  final bool promptForMaps;

  @override
  State<GatiSaarthApp> createState() => _GatiSaarthAppState();
}

class _GatiSaarthAppState extends State<GatiSaarthApp>
    with WidgetsBindingObserver {
  late final LiveSessionController _session =
      widget.session ?? createLiveSession(maps: _maps);
  late final ThemeController _theme = widget.theme ?? ThemeController();
  late final OfflineMapService _maps =
      widget.offlineMaps ?? OfflineMapService();
  late final MapDownloadService _downloads = widget.mapDownloads ??
      MapDownloadService(
        installer: PackInstaller(),
        maps: _maps,
        offerOnFirstFix: widget.promptForMaps,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_session.start());
    // Opening the archives reads a few KB of header each; the map shows online
    // or cached tiles until they are ready.
    unawaited(_maps.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.dispose();
    _theme.dispose();
    _downloads.dispose();
    _maps.dispose();
    super.dispose();
  }

  /// Save battery: sensors, GPS and timers stop while the app is in the
  /// background and come back (with a permission/service re-check, e.g. after
  /// the user visited system settings) when it returns.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_session.pause());
      case AppLifecycleState.resumed:
        unawaited(_session.resume());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LiveSessionScope(
      controller: _session,
      child: OfflineMapsScope(
        service: _maps,
        child: MapDownloadsScope(
          service: _downloads,
          child: ThemeScope(
            controller: _theme,
            child: ThemeTransitionHost(
              controller: _theme,
              enabled: widget.animateTheme,
              child: AnimatedBuilder(
                animation: _theme,
                builder: (context, _) {
                  // Resolve the static palette before the tree below is built.
                  // `ThemeTransitionHost` then marks every element for rebuild
                  // on a flip, so `const` subtrees that read the palette follow
                  // too (remounting the app instead would reset the route
                  // stack).
                  AppColors.isDark = _theme.isDark;
                  return MaterialApp(
                    title: AppConstants.appTitle,
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.lightTheme,
                    darkTheme: AppTheme.darkTheme,
                    themeMode: _theme.themeMode,
                    // The host animates the flip; MaterialApp's own colour lerp
                    // would fight it (static-palette widgets cannot lerp).
                    themeAnimationDuration: Duration.zero,
                    scrollBehavior: const AppScrollBehavior(),
                    initialRoute: widget.initialRoute ?? AppRoutes.boot,
                    routes: AppRoutes.routes,
                    // System bars follow the app brightness on every route. The
                    // boot screen is always dark and overrides this from deeper
                    // in the tree.
                    builder: (context, child) =>
                        AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle(
                        statusBarColor: Colors.transparent,
                        statusBarIconBrightness:
                            _theme.isDark ? Brightness.light : Brightness.dark,
                        statusBarBrightness:
                            _theme.isDark ? Brightness.dark : Brightness.light,
                        systemNavigationBarColor: AppColors.background,
                        systemNavigationBarIconBrightness:
                            _theme.isDark ? Brightness.light : Brightness.dark,
                      ),
                      child: child ?? const SizedBox.shrink(),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
