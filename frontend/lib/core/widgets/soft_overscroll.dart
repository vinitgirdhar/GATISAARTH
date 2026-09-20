import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Share of Android's stretch overscroll the app keeps. 1.0 is the platform
/// effect. It was halved (0.5) at first and then cut another 30 % (0.5 * 0.7)
/// because that was still more than felt right.
const double kStretchStrength = 0.35;

/// Same Android 12 stretch on every list, at [kStretchStrength] of its depth.
///
/// Only Android gets it (other platforms keep their own overscroll, exactly
/// like [MaterialScrollBehavior]).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (getPlatform(context) == TargetPlatform.android &&
        Theme.of(context).useMaterial3) {
      return SoftStretchOverscrollIndicator(
        axisDirection: details.direction,
        clipBehavior: details.decorationClipBehavior ?? Clip.hardEdge,
        child: child,
      );
    }
    return super.buildOverscrollIndicator(context, child, details);
  }
}

/// [StretchingOverscrollIndicator] with an adjustable depth.
///
/// Flutter's own indicator hard-codes the stretch size, so this is a port of
/// its physics (itself ported from Android's `EdgeEffect`, BSD-licensed) with
/// one change: the strength handed to [StretchEffect] is multiplied by
/// [strength]. The drag response, the spring and the hand-over between drag and
/// fling are untouched, so it feels like the platform effect, only shallower.
class SoftStretchOverscrollIndicator extends StatefulWidget {
  const SoftStretchOverscrollIndicator({
    super.key,
    required this.axisDirection,
    required this.child,
    this.clipBehavior = Clip.hardEdge,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.strength = kStretchStrength,
  }) : assert(strength >= 0 && strength <= 1);

  final AxisDirection axisDirection;
  final Widget? child;
  final Clip clipBehavior;
  final ScrollNotificationPredicate notificationPredicate;

  /// 0..1 multiplier on the platform stretch.
  final double strength;

  Axis get axis => axisDirectionToAxis(axisDirection);

  @override
  State<SoftStretchOverscrollIndicator> createState() =>
      _SoftStretchOverscrollIndicatorState();
}

class _SoftStretchOverscrollIndicatorState
    extends State<SoftStretchOverscrollIndicator>
    with TickerProviderStateMixin {
  late final _StretchPhysics _physics = _StretchPhysics(vsync: this);
  ScrollNotification? _lastNotification;
  OverscrollNotification? _lastOverscroll;
  double _totalOverscroll = 0;
  bool _accepted = true;

  bool _onScroll(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification) ||
        notification.metrics.axis != widget.axis) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _accepted = true;
      _totalOverscroll = 0;
    } else if (notification is OverscrollNotification) {
      _lastOverscroll = notification;
      if (_lastNotification is! OverscrollNotification) {
        final confirmation = OverscrollIndicatorNotification(
          leading: notification.overscroll < 0,
        );
        confirmation.dispatch(context);
        // The platform indicator reads this same flag: an ancestor may veto the
        // stretch with `disallowIndicator()`. It is only marked test-visible.
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        _accepted = confirmation.accepted;
      }
      if (_accepted) {
        _totalOverscroll += notification.overscroll;
        if (notification.velocity != 0) {
          _physics.absorbImpact(notification.velocity);
        } else if (notification.dragDetails != null &&
            notification.overscroll != 0) {
          // Relative to the viewport, the furthest one pointer can pull.
          final pulled =
              _totalOverscroll / notification.metrics.viewportDimension;
          _physics.pull(clampDouble(pulled, -1, 1));
        }
      }
    } else if (notification is ScrollEndNotification) {
      var velocity = switch (widget.axis) {
        Axis.vertical =>
          notification.dragDetails?.velocity.pixelsPerSecond.dy ?? 0.0,
        Axis.horizontal =>
          notification.dragDetails?.velocity.pixelsPerSecond.dx ?? 0.0,
      };
      // Reverse axes report the drag velocity in the opposite direction.
      if (notification.metrics.axisDirection == AxisDirection.left ||
          notification.metrics.axisDirection == AxisDirection.up) {
        velocity = -velocity;
      }
      _totalOverscroll = 0;
      if (_accepted) _physics.scrollEnd(velocity);
    } else if (notification is ScrollUpdateNotification) {
      _totalOverscroll = 0;
      _physics.scrollEnd(0);
    }
    _lastNotification = notification;
    return false;
  }

  @override
  void dispose() {
    _physics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: AnimatedBuilder(
        animation: _physics,
        builder: (context, _) {
          final stretch = _physics.value * widget.strength;
          final screen = widget.axis == Axis.vertical
              ? MediaQuery.heightOf(context)
              : MediaQuery.widthOf(context);
          final viewport =
              _lastOverscroll?.metrics.viewportDimension ?? screen;

          var strength = -stretch;
          if (widget.axisDirection == AxisDirection.up ||
              widget.axisDirection == AxisDirection.left) {
            strength = -strength;
          }
          return ClipRect(
            // Only a viewport smaller than the screen can bleed past its edge.
            clipBehavior: stretch != 0 && viewport != screen
                ? widget.clipBehavior
                : Clip.none,
            child: StretchEffect(
              stretchStrength: strength,
              axis: widget.axis,
              child: widget.child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}

/// The pull/absorb/release physics, constants from Android's `EdgeEffect`.
class _StretchPhysics extends ChangeNotifier {
  _StretchPhysics({required this.vsync});

  final TickerProvider vsync;
  AnimationController? _controller;
  double _value = 0;
  double _interrupted = 0;

  static const double _exponentialScalar = math.e / 0.33;
  static const double _stretchIntensity = 0.016;
  static const double _flingVelocityFriction = 1 / 6000;
  static const double _absorbVelocityFriction = 1 / 3000;
  static const double _maxFlingVelocity = 0.5;
  static const double _maxAbsorbVelocity = 1.25;
  static const double _naturalFrequency = 24.657;
  static const double _dampingRatio = 0.98;
  static const double _timeCorrection = 0.8;

  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: _naturalFrequency *
        _naturalFrequency *
        _timeCorrection *
        _timeCorrection,
    ratio: _dampingRatio,
  );

  /// -1..1, before the app's strength factor.
  double get value => _value;
  set value(double v) {
    _value = clampDouble(v, -1, 1);
    notifyListeners();
  }

  SpringSimulation _simulation(double velocity) =>
      SpringSimulation(_spring, _value, 0, velocity * _timeCorrection);

  void absorbImpact(double velocity) {
    if (velocity == 0) return;
    _animate(_simulation(clampDouble(
      velocity * _absorbVelocityFriction,
      -_maxAbsorbVelocity,
      _maxAbsorbVelocity,
    )));
  }

  void scrollEnd(double velocity) {
    if (velocity == 0 && _value == 0) return;
    if (_controller != null) return;
    _animate(_simulation(clampDouble(
      -(velocity * _flingVelocityFriction),
      -_maxFlingVelocity,
      _maxFlingVelocity,
    )));
  }

  void pull(double normalized) {
    if (_controller != null) {
      _interrupted = _controller!.value;
      _controller!.dispose();
      _controller = null;
    }
    final distance = normalized.abs();
    final linear = _stretchIntensity * distance;
    final exponential =
        _stretchIntensity * (1 - math.exp(-distance * _exponentialScalar));
    value = normalized.sign * (linear + exponential) + _interrupted;
  }

  void _animate(Simulation simulation) {
    final controller = AnimationController.unbounded(vsync: vsync);
    controller
      ..addListener(() => value = controller.value)
      ..animateWith(simulation).whenComplete(() {
        if (_controller != controller) return;
        value = 0;
        _interrupted = 0;
        controller.dispose();
        _controller = null;
      });
    _controller?.dispose();
    _controller = controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }
}
