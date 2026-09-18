import 'dart:async';

import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/constants/dr_constants.dart';
import 'features/navigation_ui/presentation/controllers/live_session_controller.dart';
import 'features/navigation_ui/presentation/controllers/live_session_scope.dart';

class GatiSaarthApp extends StatefulWidget {
  const GatiSaarthApp({Key? key, this.session}) : super(key: key);

  /// Injected in tests; production builds the real session.
  final LiveSessionController? session;

  @override
  State<GatiSaarthApp> createState() => _GatiSaarthAppState();
}

class _GatiSaarthAppState extends State<GatiSaarthApp> with WidgetsBindingObserver {
  late final LiveSessionController _session =
      widget.session ?? createLiveSession();

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
      child: MaterialApp(
        title: AppConstants.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        initialRoute: AppRoutes.dashboard,
        routes: AppRoutes.routes,
      ),
    );
  }
}
