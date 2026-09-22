import 'package:flutter/material.dart';
import '../../features/boot/presentation/boot_screen.dart';
import '../../features/navigation_ui/presentation/screens/dashboard_screen.dart';
import '../../features/navigation_ui/presentation/screens/active_nav_screen.dart';
import '../../features/navigation_engine/presentation/screens/diagnostics_screen.dart';
import '../../features/about/presentation/engine_spec_screen.dart';
import '../../features/benchmark/presentation/outage_benchmark_screen.dart';
import '../../features/offline_maps/presentation/offline_maps_screen.dart';
import '../../features/anchors/presentation/portal_anchor_screen.dart';

class AppRoutes {
  static const String boot = '/';
  static const String dashboard = '/dashboard';
  static const String session = '/session';
  static const String diagnostics = '/diagnostics';
  static const String benchmark = '/benchmark';
  static const String offlineMaps = '/offline-maps';
  static const String engine = '/engine';
  static const String portalAnchor = '/portal-anchor';

  static Map<String, WidgetBuilder> get routes {
    return {
      boot: (context) => const BootScreen(),
      dashboard: (context) => const DashboardScreen(),
      session: (context) => const NavigationScreen(),
      diagnostics: (context) => const DiagnosticsScreen(),
      benchmark: (context) => const OutageBenchmarkScreen(),
      offlineMaps: (context) => const OfflineMapsScreen(),
      engine: (context) => const EngineSpecScreen(),
      portalAnchor: (context) => const LivePortalAnchorScreen(),
    };
  }
}
