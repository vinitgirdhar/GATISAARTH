import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The vehicle on the map: a dot with a white ring, a slowly pulsing halo, and
/// (once a heading is known) a soft beam showing where it points - the
/// convention every phone map uses, so it reads at a glance.
///
/// An [estimated] puck (dead-reckoned position, no satellite fix behind it)
/// gets a dashed ring, matching the dashed track behind it.
class VehiclePuck extends StatefulWidget {
  const VehiclePuck({
    super.key,
    required this.color,
    required this.headingDegrees,
    this.showHeading = true,
    this.estimated = false,
  });

  /// Dot, halo and beam colour: the fusion mode's colour.
  final Color color;

  /// Direction of travel **on screen**, degrees clockwise from the top. The map
  /// may be turned, so this is the vehicle heading plus the map rotation.
  final double headingDegrees;

  final bool showHeading;
  final bool estimated;

  /// Diameter of the widget's square; the marker that hosts it must match.
  static const double extent = 96;

  @override
  State<VehiclePuck> createState() => _VehiclePuckState();
}

class _VehiclePuckState extends State<VehiclePuck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 0.35;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: VehiclePuck.extent,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => CustomPaint(
            painter: _PuckPainter(
              color: widget.color,
              heading: widget.headingDegrees,
              showHeading: widget.showHeading,
              estimated: widget.estimated,
              pulse: Curves.easeOut.transform(_pulse.value),
            ),
          ),
        ),
      ),
    );
  }
}

class _PuckPainter extends CustomPainter {
  _PuckPainter({
    required this.color,
    required this.heading,
    required this.showHeading,
    required this.estimated,
    required this.pulse,
  });

  final Color color;
  final double heading;
  final bool showHeading;
  final bool estimated;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);

    // Pulse: a ring that grows and fades, so the puck reads as live.
    canvas.drawCircle(
      c,
      ui.lerpDouble(11, 34, pulse)!,
      Paint()..color = color.withValues(alpha: 0.26 * (1 - pulse)),
    );

    // Heading beam: a 64 degree sector fading out from the dot.
    if (showHeading) {
      final rect = Rect.fromCircle(center: c, radius: 44);
      const half = 32.0;
      canvas.drawArc(
        rect,
        (heading - 90 - half) * math.pi / 180,
        2 * half * math.pi / 180,
        true,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            44,
            [color.withValues(alpha: 0.55), color.withValues(alpha: 0)],
          ),
      );
    }

    if (estimated) _dashedRing(canvas, c, 16, color.withValues(alpha: 0.85));

    // The dot: soft shadow, white ring, coloured core.
    canvas.drawCircle(
      c.translate(0, 1.5),
      11,
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(c, 10.5, Paint()..color = Colors.white);
    canvas.drawCircle(c, 7.4, Paint()..color = color);
  }

  void _dashedRing(Canvas canvas, Offset c, double radius, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    const dashes = 14;
    const sweep = 2 * math.pi / dashes;
    final rect = Rect.fromCircle(center: c, radius: radius);
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PuckPainter old) =>
      old.color != color ||
      old.heading != heading ||
      old.showHeading != showHeading ||
      old.estimated != estimated ||
      old.pulse != pulse;
}
