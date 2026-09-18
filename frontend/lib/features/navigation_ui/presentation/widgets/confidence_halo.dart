import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Soft glow ring behind the vehicle puck. Radius and opacity are driven by
/// [confidence] (0.0-1.0): tight and bright when GNSS-locked, large and
/// diffuse when confidence drops into dead-reckoning territory.
class ConfidenceHalo extends StatelessWidget {
  final double confidence;

  const ConfidenceHalo({super.key, this.confidence = 0});

  @override
  Widget build(BuildContext context) {
    final c = confidence.clamp(0.0, 1.0);
    // High confidence -> tight, bright ring. Low confidence -> large, soft ring.
    final diameter = 60.0 + (1 - c) * 60.0; // 60..120
    final coreOpacity = 0.10 + c * 0.30; // 0.10..0.40
    final color = Color.lerp(AppColors.deadReckoning, AppColors.gnssLocked, c)!;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: coreOpacity),
            color.withValues(alpha: coreOpacity * 0.3),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
