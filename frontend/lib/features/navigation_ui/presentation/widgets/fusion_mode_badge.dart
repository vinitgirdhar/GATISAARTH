import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../../../navigation_engine/domain/entities/navigation_state.dart';

/// Current positioning mode as a pill. Colour and label cross-fade when the
/// mode changes, and the change is announced to screen readers.
class FusionModeBadge extends StatelessWidget {
  final FusionMode fusionMode;

  const FusionModeBadge({Key? key, required this.fusionMode}) : super(key: key);

  Color get _color {
    switch (fusionMode) {
      case FusionMode.gnssLocked:
        return AppColors.gnssLocked;
      case FusionMode.gnssDegraded:
        return AppColors.gnssDegraded;
      case FusionMode.deadReckoning:
        return AppColors.deadReckoning;
      case FusionMode.reacquiring:
        return AppColors.reacquiring;
    }
  }

  String get _text {
    switch (fusionMode) {
      case FusionMode.gnssLocked:
        return 'GNSS locked';
      case FusionMode.gnssDegraded:
        return 'GNSS degraded · IMU assisted';
      case FusionMode.deadReckoning:
        return 'Dead reckoning · inertial';
      case FusionMode.reacquiring:
        return 'Reacquiring GNSS signal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final duration = AppMotion.of(context, AppMotion.medium);
    return Semantics(
      liveRegion: true,
      label: 'Positioning mode: $_text',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: AppRadius.pillRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: duration,
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: AnimatedSwitcher(
                duration: AppMotion.of(context, AppMotion.fast),
                child: Text(
                  _text,
                  key: ValueKey<FusionMode>(fusionMode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
