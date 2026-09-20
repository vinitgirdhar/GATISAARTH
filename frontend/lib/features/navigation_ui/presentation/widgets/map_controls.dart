import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import 'map_follow.dart';

/// Round-cornered floating button used for every control on the map.
class MapControlButton extends StatelessWidget {
  const MapControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.active = false,
    this.size = 44,
  });

  final Widget icon;
  final VoidCallback onTap;
  final String semanticLabel;

  /// Tinted with the accent (following, or a mode that is on).
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: _controlDecoration(active: active),
          alignment: Alignment.center,
          child: icon,
        ),
      ),
    );
  }
}

BoxDecoration _controlDecoration({bool active = false}) {
  final dark = AppColors.isDark;
  return BoxDecoration(
    color: dark ? AppColors.darkSurface : Colors.white,
    borderRadius: BorderRadius.circular(AppRadius.control),
    border: Border.all(
      color: active
          ? AppColors.primary.withValues(alpha: 0.55)
          : (dark
              ? Colors.white.withValues(alpha: 0.10)
              : AppColors.lightSurfaceBorder),
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.35 : 0.16),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

/// Recentre / follow control. Cycles free -> north-up -> heading-up -> north-up
/// (the convention of phone maps); the icon says which one is active.
class FollowButton extends StatelessWidget {
  const FollowButton({super.key, required this.mode, required this.onTap});

  final FollowMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final following = mode != FollowMode.free;
    final (icon, label) = switch (mode) {
      FollowMode.free => (Icons.gps_not_fixed_rounded, 'Recenter on my position'),
      FollowMode.north => (
          Icons.gps_fixed_rounded,
          'Following, north up. Tap to turn the map with my heading',
        ),
      FollowMode.heading => (
          Icons.navigation_rounded,
          'Following, heading up. Tap for north up',
        ),
    };
    return MapControlButton(
      semanticLabel: label,
      active: following,
      onTap: onTap,
      icon: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.fast),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          icon,
          key: ValueKey(mode),
          size: 24,
          color: following ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// A compass needle that points to north wherever the map is turned. Only
/// shown while the map is not north-up; tapping it turns the map back.
class CompassButton extends StatelessWidget {
  const CompassButton({
    super.key,
    required this.rotationDegrees,
    required this.onTap,
  });

  /// The map's rotation, degrees clockwise (north is this far clockwise of up).
  final double rotationDegrees;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MapControlButton(
      semanticLabel: 'Compass. Tap to point the map north',
      onTap: onTap,
      icon: Transform.rotate(
        angle: rotationDegrees * math.pi / 180,
        child: CustomPaint(
          size: const Size(22, 22),
          painter: _NeedlePainter(),
        ),
      ),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final h = size.height / 2;
    final w = size.width * 0.22;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - h)
        ..lineTo(c.dx + w, c.dy)
        ..lineTo(c.dx - w, c.dy)
        ..close(),
      Paint()..color = AppColors.error,
    );
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy + h)
        ..lineTo(c.dx + w, c.dy)
        ..lineTo(c.dx - w, c.dy)
        ..close(),
      Paint()..color = AppColors.disabled,
    );
  }

  @override
  bool shouldRepaint(covariant _NeedlePainter old) => true;
}

/// Zoom in / zoom out as one joined pill.
class MapZoomButtons extends StatelessWidget {
  const MapZoomButtons({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    this.canZoomIn = true,
    this.canZoomOut = true,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final bool canZoomIn;
  final bool canZoomOut;

  @override
  Widget build(BuildContext context) {
    Widget half(IconData icon, String label, VoidCallback onTap, bool enabled) =>
        Semantics(
          button: true,
          enabled: enabled,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 44,
              height: 42,
              child: Icon(
                icon,
                size: 22,
                color: enabled ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ),
        );

    return Container(
      decoration: _controlDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          half(Icons.add_rounded, 'Zoom in', onZoomIn, canZoomIn),
          Container(
            width: 26,
            height: 1,
            color: AppColors.isDark
                ? Colors.white.withValues(alpha: 0.12)
                : AppColors.lightSurfaceBorder,
          ),
          half(Icons.remove_rounded, 'Zoom out', onZoomOut, canZoomOut),
        ],
      ),
    );
  }
}
