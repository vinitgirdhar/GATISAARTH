import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/geo_format.dart';
import '../../controllers/live_session_scope.dart';
import '../../widgets/fusion_confidence_badge.dart';
import '../../widgets/engine_status_card.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/navigation_map.dart';
import '../../widgets/mission_guidance_card.dart';
import '../../widgets/session_controls.dart';
import '../../widgets/telemetry_card.dart';

const double _sheetRadius = 22;

class MapTab extends StatefulWidget {
  const MapTab({Key? key}) : super(key: key);

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  bool _coreDetailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final estimate = session.uncertainty;
    final margin = estimate?.marginMeters;
    final isDark = AppColors.isDark;

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          // 1. Top Exact Location Card (replaces mock 300 m guidance)
          Container(
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppColors.lightSurfaceBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.my_location_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              session.inOutage
                                  ? 'Estimated road corridor'
                                  : 'Exact Location',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: session.inOutage
                                    ? AppColors.error.withValues(alpha: 0.15)
                                    : AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                session.inOutage
                                    ? 'DEAD RECKONING'
                                    : 'GNSS LOCKED',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: session.inOutage
                                      ? AppColors.error
                                      : AppColors.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatLatitude(session.latitude)}, ${formatLongitude(session.longitude)}${margin != null ? ' · ±${margin.round()} m' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontFamily: 'RobotoMono',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: EngineStatusCard(
                    compact: !_coreDetailsExpanded ||
                        session.isSimulatingTunnel ||
                        session.isSimulatingCanyon,
                    onToggleDetails: () => setState(
                      () => _coreDetailsExpanded = !_coreDetailsExpanded,
                    ),
                    snapshot: session.navSnapshot,
                    isLeading: session.isEngineLeading,
                    blocker: session.engineHandoverBlocker,
                    isRecording: session.isRecording,
                    recordedDuration: session.recordedDuration,
                    recordedLines: session.recordedLines,
                    recordingError: session.recordingError,
                    onStartRecording: () async {
                      final path = await session.startRecording();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(path == null
                              ? 'Could not start recording — storage unavailable'
                              : 'Recording this drive. The screen stays on.'),
                          backgroundColor:
                              path == null ? AppColors.error : AppColors.cyan,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                    onStopRecording: () async {
                      final file = await session.stopRecording();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(file == null
                              ? 'Recording stopped'
                              : 'Saved ${file.name} (${file.sizeMb.toStringAsFixed(1)} MB)'),
                          backgroundColor: AppColors.healthy,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                    onMarkEvent: () {
                      session.markEvent('driver marker');
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Marked this moment in the log'),
                          backgroundColor: AppColors.cyan,
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          if (session.missionGuidance != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: MissionGuidanceCard(
                decision: session.missionGuidance!,
                compact: true,
              ),
            ),

          // 2. Interactive Navigation Map. Fills all the space between the card
          // above and the sheet below, and runs [_sheetRadius] underneath the
          // sheet so its rounded top corners show map, not page background.
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: -_sheetRadius,
                  child: NavigationMap(
                    navigationState: session.navigationState,
                    marginMeters: margin,
                    trail: session.trail.segments,
                    roadCorridors: session.roadCorridors,
                    expand: true,
                    gestures: MapGestures.full,
                    bottomInset: _sheetRadius + 12,
                    onClearTrail: session.clearTrail,
                    actions: [
                      MapControlButton(
                        icon: Icon(
                          Icons.fullscreen_rounded,
                          size: 22,
                          color: AppColors.textPrimary,
                        ),
                        semanticLabel: 'Open live navigation',
                        onTap: () => Navigator.pushNamed(context, '/session'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3. Bottom Telemetry & Simulation Controls
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_sheetRadius)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Telemetry metrics row
                Row(
                  children: [
                    TelemetryCard(
                      label: 'Speed',
                      value: (session.speed * 3.6).toStringAsFixed(0),
                      unit: 'km/h',
                      subtitle: '${session.speed.toStringAsFixed(1)} m/s',
                      accentColor: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    TelemetryCard(
                      label: 'Heading',
                      value: '${session.heading.round()}°',
                      subtitle: 'Compass',
                      accentColor: AppColors.secondary,
                    ),
                    const SizedBox(width: 8),
                    TelemetryCard(
                      label: 'Accuracy',
                      value: margin == null ? '—' : '±${margin.round()}',
                      unit: margin == null ? null : 'm',
                      subtitle:
                          session.inOutage ? 'Dead reckoning' : 'GNSS fix',
                      accentColor:
                          FusionConfidenceBadge.colorFor(estimate?.confidence),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Outage & Simulation Controls
                SessionControls(
                  compact: true,
                  showBackground: false,
                  showDiagnostics: false,
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.only(top: 10),
                  onTunnelTest: session.startTunnelTest,
                  onUrbanCanyon: session.startUrbanCanyon,
                  onResetGps: session.resetSimulation,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
