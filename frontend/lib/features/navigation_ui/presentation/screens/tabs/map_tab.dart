import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../../core/nav/guidance/mission_guidance.dart';
import '../../../../../core/nav/route/route_tracker.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/motion.dart';
import '../../controllers/live_session_controller.dart';
import '../../controllers/live_session_scope.dart';
import '../../widgets/map_controls.dart';
import '../../widgets/nav_safety_badge.dart';
import '../../widgets/navigation_map.dart';
import '../../widgets/outage_recovery_card.dart';
import '../../controllers/position_share.dart';
import '../../widgets/parking_level_card.dart';
import '../../widgets/tunnel_ahead_card.dart';
import '../../widgets/mission_guidance_card.dart';
import '../../widgets/simulated_outage_sheet.dart';
import '../../../../navigation_engine/domain/navigation_safety.dart';
import '../../../../journey/application/journey_service.dart';
import '../../../../journey/presentation/journey_format.dart';
import '../../../../journey/presentation/widgets/maneuver_banner.dart';

const double _sheetRadius = 22;

class MapTab extends StatefulWidget {
  const MapTab({Key? key}) : super(key: key);

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  bool _detailsExpanded = false;

  void _showSimulationMenu(
    BuildContext context,
    LiveSessionController session,
  ) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Simulation Lab'),
        message: const Text(
          'Try signal conditions while your drive recording continues. Simulations affect GatiSaarth only; they do not change the phone’s GNSS receiver.',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              session.startTunnelTest();
            },
            child: const Text('Tunnel test'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              session.startUrbanCanyon();
            },
            child: const Text('Urban canyon test'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              showSimulatedOutageSheet(context, session);
            },
            child: const Text('Timed GPS loss test'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _simulationToolsButton(
    BuildContext context,
    LiveSessionController session,
  ) {
    final tunnelOrCanyon =
        session.isSimulatingTunnel || session.isSimulatingCanyon;
    final outage = session.isSimulatingOutage;
    final active = tunnelOrCanyon || outage;
    final accent = AppColors.warning;
    return Tooltip(
      message: 'Simulation Lab',
      child: OutlinedButton.icon(
        key: const ValueKey('map-simulation-tools'),
        onPressed: tunnelOrCanyon
            ? session.resetSimulation
            : outage
                ? () => showSimulatedOutageSheet(context, session)
                : () => _showSimulationMenu(context, session),
        icon: Icon(
          active ? Icons.stop_circle_outlined : Icons.science_outlined,
          size: 16,
        ),
        label: Text(tunnelOrCanyon
            ? 'End test'
            : outage
                ? 'Outage'
                : 'Simulation Lab'),
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          backgroundColor: accent.withValues(alpha: 0.10),
          side: BorderSide(
            color: accent.withValues(alpha: active ? 0.65 : 0.38),
          ),
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _startRecording(
    BuildContext context,
    LiveSessionController session,
  ) async {
    final path = await session.startRecording();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path == null
            ? 'Could not start recording — storage unavailable'
            : 'Recording this drive. The screen stays on.'),
        backgroundColor: path == null ? AppColors.error : AppColors.cyan,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _stopRecording(
    BuildContext context,
    LiveSessionController session,
  ) async {
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
  }

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final estimate = session.uncertainty;
    final margin = estimate?.marginMeters;
    final isDark = AppColors.isDark;
    final trust = session.trust;
    final restoring = !trust.limited &&
        session.missionGuidance?.event == MissionGuidanceEvent.recovered;
    final journey = JourneyScope.maybeOf(context);
    final activeRoute = session.activeRoute;
    final routeProgress = session.routeProgress;

    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        children: [
          // The map leads the page. Status and recording controls stay in
          // floating map overlays or the lower sheet.
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
                    route: activeRoute,
                    routeAlongM: routeProgress?.alongM,
                    expand: true,
                    gestures: MapGestures.full,
                    bottomInset: _sheetRadius + 12,
                    onClearTrail: session.clearTrail,
                    bottomStatus: restoring
                        ? _RecoveryMapStatus(
                            message: session.missionGuidance!.display,
                          )
                        : null,
                    actions: [
                      if (estimate != null)
                        MapControlButton(
                          icon: Icon(
                            Icons.share_location_rounded,
                            size: 22,
                            color: AppColors.textPrimary,
                          ),
                          semanticLabel: 'Share my position',
                          onTap: () => SharePlus.instance.share(ShareParams(
                            subject: 'My position',
                            text: positionShareText(
                              latitude: session.latitude,
                              longitude: session.longitude,
                              marginM: margin,
                              deadReckoning: session.inOutage,
                              sinceGnssLost: session.outageElapsed,
                              at: DateTime.now(),
                            ),
                          )),
                        ),
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
                Positioned(
                  top: 54,
                  left: 12,
                  right: 72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (activeRoute != null && routeProgress != null) ...[
                        ManeuverBanner(
                          progress: routeProgress,
                          isRouteLocked: session.isRouteLocked,
                          isRerouting: journey?.isRerouting ?? false,
                          isOffRoute: session.isOffRoute,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      NavSafetyBadge(assessment: trust),
                      if (!restoring) ...[
                        if (trust.limited) ...[
                          const SizedBox(height: AppSpacing.sm),
                          const MissionGuidancePausedNotice(),
                        ] else if (session.missionGuidance != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          MissionGuidanceCard(
                            decision: session.missionGuidance!,
                            compact: true,
                          ),
                        ] else if (session.recentRecovery != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          GestureDetector(
                            onTap: () =>
                                Navigator.pushNamed(context, '/outage-log'),
                            child: OutageRecoveryCard(
                              recovery: session.recentRecovery!,
                            ),
                          ),
                        ] else if (session.parkingLevel != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          ParkingLevelCard(level: session.parkingLevel!),
                        ] else if (session.tunnelAhead != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          TunnelAheadCard(
                            tunnel: session.tunnelAhead!,
                            speedAidValidated: session.isSpeedAidValidated,
                            readiness: session.isPreparingForGnssLoss
                                ? session.drReadiness
                                : null,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // The map stays primary; the sheet keeps only speed and accuracy at a glance.
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(_sheetRadius),
              ),
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
                SizedBox(
                  width: double.infinity,
                  child: _simulationToolsButton(context, session),
                ),
                if (activeRoute != null && routeProgress != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _RouteSheetRow(progress: routeProgress, journey: journey),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SPEED',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                (session.speed * 3.6).toStringAsFixed(0),
                                style: Theme.of(context)
                                    .textTheme
                                    .displayLarge
                                    ?.copyWith(color: AppColors.primary),
                              ),
                              const SizedBox(width: 5),
                              Text('km/h',
                                  style: Theme.of(context).textTheme.bodyLarge),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 44,
                      color: AppColors.surfaceBorder,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'LOCATION',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            margin == null
                                ? (session.hasLiveGnss
                                    ? 'Connected'
                                    : 'Searching')
                                : formatUncertainty(trust, margin),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: trust.limited
                                      ? NavSafetyBadge.colorFor(trust.level)
                                      : AppColors.textPrimary,
                                ),
                          ),
                          Text(
                            session.inOutage
                                ? 'Estimated position'
                                : 'GPS accuracy',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip:
                          _detailsExpanded ? 'Hide details' : 'Show details',
                      onPressed: () =>
                          setState(() => _detailsExpanded = !_detailsExpanded),
                      icon: AnimatedRotation(
                        turns: _detailsExpanded ? 0.5 : 0,
                        duration: AppMotion.of(
                          context,
                          const Duration(milliseconds: 320),
                        ),
                        curve: Curves.easeInOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                ClipRect(
                  child: AnimatedSize(
                    duration: AppMotion.of(
                      context,
                      const Duration(milliseconds: 380),
                    ),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment.topCenter,
                    child: _detailsExpanded
                        ? Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.md,
                              bottom: AppSpacing.sm,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _SmallReading(
                                    label: 'Heading',
                                    value: '${session.heading.round()}°',
                                  ),
                                ),
                                Expanded(
                                  child: _SmallReading(
                                    label: 'Mode',
                                    value: session.inOutage
                                        ? 'Estimating'
                                        : 'Live GPS',
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: session.isRecording
                        ? () => _stopRecording(context, session)
                        : () => _startRecording(context, session),
                    icon: Icon(session.isRecording
                        ? Icons.stop_rounded
                        : Icons.fiber_manual_record_rounded),
                    label: Text(session.isRecording
                        ? 'Stop recording'
                        : 'Record drive'),
                    style: FilledButton.styleFrom(
                      foregroundColor: AppColors.error,
                      backgroundColor: AppColors.error.withValues(alpha: 0.14),
                      minimumSize: const Size(double.infinity, 46),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: AppColors.error.withValues(alpha: 0.28),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact remaining-distance/ETA row shown in the sheet while a journey
/// route is active, with the way out of it.
class _RouteSheetRow extends StatelessWidget {
  const _RouteSheetRow({required this.progress, required this.journey});

  final RouteProgress progress;
  final JourneyService? journey;

  @override
  Widget build(BuildContext context) {
    final arrived = progress.arrived;
    final eta = formatArrivalIn(progress.remainingS, DateTime.now());
    return Row(
      children: [
        Expanded(
          child: arrived
              ? Text(
                  'You have arrived',
                  style: TextStyle(
                    color: AppColors.healthy,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                )
              : Text(
                  '${formatRouteDistance(progress.remainingM)} · '
                  '${formatRouteDuration(progress.remainingS)} · arrive $eta',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
        ),
        TextButton(
          onPressed: journey == null ? null : journey!.end,
          child: Text(arrived ? 'End' : 'End route'),
        ),
      ],
    );
  }
}

class _RecoveryMapStatus extends StatelessWidget {
  const _RecoveryMapStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: message,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.gps_fixed_rounded,
                size: 14, color: AppColors.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

class _SmallReading extends StatelessWidget {
  const _SmallReading({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      );
}
