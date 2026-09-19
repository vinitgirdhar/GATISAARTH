import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/router/app_router.dart';
import 'core/constants/dr_constants.dart';
import 'features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'features/navigation_ui/presentation/controllers/live_session_scope.dart';

class GatiSaarthApp extends StatefulWidget {
  const GatiSaarthApp({
    Key? key,
    this.session,
    this.theme,
    this.initialRoute,
  }) : super(key: key);

  /// Injected in tests; production builds the real session.
  final LiveSessionController? session;

  /// Injected in tests; production loads the saved brightness in `main`.
  final ThemeController? theme;

  /// Injected by widget tests that want to land straight on a screen instead
  /// of sitting through the boot sequence.
  final String? initialRoute;

  @override
  State<GatiSaarthApp> createState() => _GatiSaarthAppState();
}

class _GatiSaarthAppState extends State<GatiSaarthApp> with WidgetsBindingObserver {
  late final LiveSessionController _session =
      widget.session ?? createLiveSession();
  late final ThemeController _theme = widget.theme ?? ThemeController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_session.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.dispose();
    _theme.dispose();
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
      child: ThemeScope(
        controller: _theme,
        child: AnimatedBuilder(
          animation: _theme,
          builder: (context, _) {
            // Resolve the static palette before the tree below is built; the
            // ValueKey then remounts that tree on a flip so widgets holding
            // colours in `const` subtrees pick the new values up too.
            AppColors.isDark = _theme.isDark;
            return MaterialApp(
              key: ValueKey<bool>(_theme.isDark),
              title: AppConstants.appTitle,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: _theme.themeMode,
              initialRoute: widget.initialRoute ?? AppRoutes.boot,
              routes: AppRoutes.routes,
              // System bars follow the app brightness on every route. The
              // boot screen is always dark and overrides this from deeper in
              // the tree.
              builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
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
    );
  }
}
