import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../../../navigation_ui/presentation/controllers/live_session_controller.dart';
import '../../application/journey_service.dart';
import '../../domain/journey.dart';
import '../journey_format.dart';
import '../route_planner_screen.dart';

/// Home's journey entry point: a "Where to?" planner card, or — once a
/// journey is under way — a compact live-progress card with Resume/End.
class WhereToCard extends StatelessWidget {
  const WhereToCard({
    super.key,
    required this.session,
    required this.journey,
    required this.onNavigateToTab,
  });

  final LiveSessionController session;

  /// Null when `JourneyScope` has not been wired above this context yet (an
  /// older harness, or a test that only mounts `HomeTab`): the card still
  /// renders, tapping it just does nothing.
  final JourneyService? journey;
  final void Function(int tabIndex) onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    final active = journey?.active;
    if (active != null) {
      return _ActiveJourneyCard(
        session: session,
        journey: journey!,
        active: active,
        onNavigateToTab: onNavigateToTab,
      );
    }
    return _PlanCard(journey: journey, onNavigateToTab: onNavigateToTab);
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.journey, required this.onNavigateToTab});

  final JourneyService? journey;
  final void Function(int tabIndex) onNavigateToTab;

  Future<void> _open(BuildContext context) async {
    final journey = this.journey;
    if (journey == null) return;
    final started = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const RoutePlannerScreen()),
    );
    if (started == true) onNavigateToTab(1);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Where to? Plan a journey',
      excludeSemantics: true,
      child: PressableScale(
        key: const ValueKey('where-to-card'),
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _WhereRow(
                icon: Icons.my_location_rounded,
                label: 'From',
                value: 'Your location',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 34),
                    Expanded(
                      child: Divider(color: AppColors.surfaceBorder, height: 1),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.swap_vert_rounded,
                        size: 18, color: AppColors.textSecondary),
                  ],
                ),
              ),
              const _WhereRow(
                icon: Icons.place_rounded,
                label: 'To',
                value: 'Choose destination',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhereRow extends StatelessWidget {
  const _WhereRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label · ',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ActiveJourneyCard extends StatelessWidget {
  const _ActiveJourneyCard({
    required this.session,
    required this.journey,
    required this.active,
    required this.onNavigateToTab,
  });

  final LiveSessionController session;
  final JourneyService journey;
  final Journey active;
  final void Function(int tabIndex) onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    final progress = session.routeProgress;
    final status = progress == null
        ? 'Calculating…'
        : progress.arrived
            ? 'You have arrived'
            : '${formatRouteDistance(progress.remainingM)} · '
                '${formatRouteDuration(progress.remainingS)}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.navigation_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  active.to.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onNavigateToTab(1),
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Resume navigation'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => journey.end(),
                child: const Text('End'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
