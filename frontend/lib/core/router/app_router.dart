import 'package:flutter/material.dart';

import '../../features/about/presentation/engine_spec_screen.dart';
import '../../features/anchors/presentation/portal_anchor_screen.dart';
import '../../features/benchmark/presentation/outage_benchmark_screen.dart';
import '../../features/boot/presentation/boot_screen.dart';
import '../../features/fault_lab/presentation/fault_lab_screen.dart';
import '../../features/navigation_engine/presentation/screens/diagnostics_screen.dart';
import '../../features/navigation_ui/presentation/screens/active_nav_screen.dart';
import '../../features/navigation_ui/presentation/screens/dashboard_screen.dart';
import '../../features/navigation_ui/presentation/screens/outage_log_screen.dart';
import '../../features/offline_maps/presentation/offline_maps_screen.dart';

/// Named routes of the app. Every screen reads the live session from
/// `LiveSessionScope`, so a route needs no arguments.
abstract final class AppRoutes {
  static const boot = '/';
  static const dashboard = '/dashboard';
  static const session = '/session';
  static const diagnostics = '/diagnostics';
  static const benchmark = '/benchmark';
  static const faultLab = '/fault-lab';
  static const offlineMaps = '/offline-maps';
  static const engine = '/engine';
  static const portalAnchor = '/portal-anchor';
  static const outageLog = '/outage-log';

  static final Map<String, WidgetBuilder> routes = {
    boot: (_) => const BootScreen(),
    dashboard: (_) => const DashboardScreen(),
    session: (_) => const NavigationScreen(),
    diagnostics: (_) => const DiagnosticsScreen(),
    benchmark: (_) => const OutageBenchmarkScreen(),
    faultLab: (_) => const FaultLabScreen(),
    offlineMaps: (_) => const OfflineMapsScreen(),
    engine: (_) => const EngineSpecScreen(),
    portalAnchor: (_) => const LivePortalAnchorScreen(),
    outageLog: (_) => const OutageLogScreen(),
  };
}
