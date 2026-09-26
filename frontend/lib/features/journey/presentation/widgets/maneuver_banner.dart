import 'package:flutter/material.dart';

import '../../../../core/nav/route/planned_route.dart';
import '../../../../core/nav/route/route_tracker.dart';
import '../../../../core/theme/app_theme.dart';
import '../journey_format.dart';

/// Turn-by-turn banner shown at the top of the map overlay while a journey
/// route is active: the next maneuver, distance to it, and (when relevant) a
/// status line for rerouting, dead-reckoning lock or drifting off the route.
class ManeuverBanner extends StatelessWidget {
  const ManeuverBanner({
    super.key,
    required this.progress,
    this.isRouteLocked = false,
    this.isRerouting = false,
    this.isOffRoute = false,
  });

  final RouteProgress progress;

  /// Dead reckoning is following the saved route because GNSS is lost.
  final bool isRouteLocked;

  /// The journey service is computing a new route from the current position.
  final bool isRerouting;

  /// Live positions have stayed off the route (e.g. a missed turn).
  final bool isOffRoute;

  static IconData iconFor(ManeuverKind kind) => switch (kind) {
        ManeuverKind.depart => Icons.navigation_rounded,
        ManeuverKind.continueOn => Icons.straight_rounded,
        ManeuverKind.slightLeft => Icons.turn_slight_left_rounded,
        ManeuverKind.left => Icons.turn_left_rounded,
        ManeuverKind.sharpLeft => Icons.turn_sharp_left_rounded,
        ManeuverKind.slightRight => Icons.turn_slight_right_rounded,
        ManeuverKind.right => Icons.turn_right_rounded,
        ManeuverKind.sharpRight => Icons.turn_sharp_right_rounded,
        ManeuverKind.uTurn => Icons.u_turn_left_rounded,
        ManeuverKind.arrive => Icons.flag_rounded,
      };

  String? get _status {
    if (isRerouting) return 'Rerouting…';
    if (isRouteLocked) return 'GPS lost · following the saved route';
    if (isOffRoute) return 'Off route';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final next = progress.next;
    if (next == null) return const SizedBox.shrink();
    final distance = progress.distanceToNextM;
    final status = _status;
    final headline =
        distance == null ? next.instruction : formatRouteDistance(distance);

    return Semantics(
      liveRegion: true,
      label: [
        if (distance != null) formatRouteDistance(distance),
        next.instruction,
        if (status != null) status,
      ].join('. '),
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadow.card,
          border: status != null
              ? Border.all(color: AppColors.warning.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary
                    .withValues(alpha: AppColors.isDark ? 0.18 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(iconFor(next.kind), color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (distance != null)
                    Text(
                      next.instruction,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (status != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      status,
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
