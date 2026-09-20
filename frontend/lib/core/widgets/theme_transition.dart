import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/theme_controller.dart';

/// Makes a light/dark flip a transition instead of a cut.
///
/// The app's surface colours are static getters resolved at build time, so a
/// flip can't be animated by interpolating a `ThemeData`. Instead, just before
/// the brightness changes this host freezes a picture of the screen
/// ([ThemeController.beforeFlip]), lets the app rebuild in the new brightness
/// underneath it, and then wipes the picture away from the top of the screen to
/// the bottom with a soft edge, so the new look arrives as a smooth reveal.
///
/// It also does what `MaterialApp` cannot: after a flip every element is marked
/// for rebuild. A `const` widget that reads a static colour (the Privacy tile
/// in Profile was one) is otherwise skipped by the framework and keeps the
/// previous brightness's colours - dark text on a dark card.
class ThemeTransitionHost extends StatefulWidget {
  /// Marks the frozen-picture overlay, so a test can tell a flip is mid-wipe.
  @visibleForTesting
  static const Key wipeOverlayKey = ValueKey<String>('theme-wipe-overlay');

  const ThemeTransitionHost({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
    this.duration = const Duration(milliseconds: 620),
  });

  final ThemeController controller;
  final Widget child;

  /// False in tests that don't want a frozen picture; the flip still rebuilds
  /// everything, it just is not animated.
  final bool enabled;
  final Duration duration;

  @override
  State<ThemeTransitionHost> createState() => _ThemeTransitionHostState();
}

class _ThemeTransitionHostState extends State<ThemeTransitionHost>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  late final AnimationController _wipe =
      AnimationController(vsync: this, duration: widget.duration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _release();
        });
  ui.Image? _frozen;

  @override
  void initState() {
    super.initState();
    _wire(widget.controller);
  }

  @override
  void didUpdateWidget(covariant ThemeTransitionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.enabled != widget.enabled) {
      _unwire(oldWidget.controller);
      _wire(widget.controller);
    }
  }

  void _wire(ThemeController controller) {
    controller.addListener(_flipped);
    if (widget.enabled) controller.beforeFlip = _freeze;
  }

  void _unwire(ThemeController controller) {
    controller.removeListener(_flipped);
    if (controller.beforeFlip == _freeze) controller.beforeFlip = null;
  }

  @override
  void dispose() {
    _unwire(widget.controller);
    _wipe.dispose();
    _frozen?.dispose();
    super.dispose();
  }

  bool get _reducedMotion => WidgetsBinding
      .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  /// Called by the controller before it changes brightness: puts a picture of
  /// the current screen on top, so the rebuild underneath is never seen.
  Future<void> _freeze() async {
    if (!mounted || _reducedMotion) return;
    if (_wipe.isAnimating || _frozen != null) _release(immediately: true);

    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    // Debug builds assert the boundary is clean; a release build cannot ask.
    if (kDebugMode && boundary.debugNeedsPaint) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final ui.Image image;
    try {
      image = boundary.toImageSync(
        pixelRatio: View.of(context).devicePixelRatio,
      );
    } catch (_) {
      return; // no picture: the flip just happens without the wipe
    }
    setState(() => _frozen = image);
    // Wait until the picture is really on screen before the app changes.
    await WidgetsBinding.instance.endOfFrame;
  }

  void _flipped() {
    _rebuildEverything();
    if (_frozen == null || !mounted) return;
    // The first frame in the new brightness is painted under the picture;
    // only then start uncovering it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _frozen != null) _wipe.forward(from: 0);
    });
  }

  void _rebuildEverything() {
    void mark(Element element) {
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    (_boundaryKey.currentContext as Element?)?.visitChildren(mark);
  }

  void _release({bool immediately = false}) {
    final old = _frozen;
    if (old == null) return;
    _wipe.stop();
    _wipe.value = 0;
    if (immediately) {
      _frozen = null;
      // Painted this frame; drop it after.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      return;
    }
    setState(() => _frozen = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final frozen = _frozen;
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(key: _boundaryKey, child: widget.child),
        if (frozen != null)
          Positioned.fill(
            child: IgnorePointer(
              key: ThemeTransitionHost.wipeOverlayKey,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _wipe,
                  builder: (context, _) => CustomPaint(
                    painter: _WipePainter(
                      image: frozen,
                      progress: Curves.easeInOutCubic.transform(_wipe.value),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Paints the old screen with everything above a moving line erased. The line
/// has a soft edge, so the two looks blend across it rather than meeting at a
/// hard seam.
class _WipePainter extends CustomPainter {
  _WipePainter({required this.image, required this.progress});

  final ui.Image image;

  /// 0 = old screen fully visible, 1 = fully uncovered.
  final double progress;

  /// Height of the soft edge, as a fraction of the screen.
  static const double _feather = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final feather = size.height * _feather;
    final front = progress * (size.height + feather);

    canvas.saveLayer(bounds, Paint());
    paintImage(
      canvas: canvas,
      rect: bounds,
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.low,
    );
    // dstOut: where the gradient is opaque the old picture is removed.
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = ui.Gradient.linear(
          Offset(0, front - feather),
          Offset(0, front),
          const [Color(0xFF000000), Color(0x00000000)],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WipePainter old) =>
      old.progress != progress || old.image != image;
}
