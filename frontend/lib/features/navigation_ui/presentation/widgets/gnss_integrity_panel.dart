import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/platform/gnss/gnss_integrity_monitor.dart';
import '../../../../core/platform/gnss/gnss_telemetry.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/standard_card.dart';

class GnssIntegrityPanel extends StatelessWidget {
  const GnssIntegrityPanel({
    super.key,
    required this.telemetry,
    required this.assessment,
    required this.cn0History,
  });

  final GnssTelemetrySnapshot? telemetry;
  final GnssIntegrityAssessment assessment;
  final List<double> cn0History;

  @override
  Widget build(BuildContext context) {
    final snapshot = telemetry;
    final color = switch (assessment.state) {
      GnssSignalState.healthy => AppColors.success,
      GnssSignalState.degraded => AppColors.warning,
      GnssSignalState.anomaly => AppColors.error,
      GnssSignalState.unavailable => AppColors.textSecondary,
    };
    return StandardCard(
      titleText: 'GNSS INTEGRITY LAB',
      trailing: Text(
        assessment.state.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            assessment.reason,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (snapshot == null || !snapshot.hasRealStatus)
            Text(
              'Waiting for receiver-backed satellite geometry.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: _SkyPlotPainter(snapshot.satellites),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _metric('${snapshot.visibleCount} satellites',
                          '${snapshot.usedInFixCount} used in fix'),
                      _metric(
                          '${snapshot.rawMeasurementCount} raw observations',
                          '${snapshot.adrMeasurementCount} ADR valid'),
                      _metric(
                        assessment.meanCn0DbHz == null
                            ? 'C/N₀ unavailable'
                            : '${assessment.meanCn0DbHz!.toStringAsFixed(1)} dBHz mean',
                        'Measured by Android receiver',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('C/N₀ TREND',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                )),
            const SizedBox(height: 4),
            SizedBox(
              height: 56,
              width: double.infinity,
              child: CustomPaint(painter: _Cn0TrendPainter(cn0History, color)),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _metric(String value, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                )),
            Text(label,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                )),
          ],
        ),
      );
}

class _SkyPlotPainter extends CustomPainter {
  const _SkyPlotPainter(this.satellites);

  final List<GnssSatellite> satellites;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final grid = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final scale in const [1.0, 0.66, 0.33]) {
      canvas.drawCircle(center, radius * scale, grid);
    }
    canvas.drawLine(
        center - Offset(radius, 0), center + Offset(radius, 0), grid);
    canvas.drawLine(
        center - Offset(0, radius), center + Offset(0, radius), grid);

    for (final satellite in satellites) {
      final elevation = satellite.elevationDegrees;
      final azimuth = satellite.azimuthDegrees;
      if (elevation == null || azimuth == null) continue;
      final radial = radius * (1 - elevation.clamp(0, 90) / 90);
      final angle = (azimuth - 90) * math.pi / 180;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radial;
      final paint = Paint()
        ..color = _constellationColor(satellite.constellation)
        ..style =
            satellite.usedInFix ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(point, 4.5, paint);
    }
  }

  static Color _constellationColor(GnssConstellation constellation) =>
      switch (constellation) {
        GnssConstellation.navic => AppColors.navIC,
        GnssConstellation.gps => AppColors.gps,
        GnssConstellation.galileo => AppColors.galileo,
        GnssConstellation.glonass => AppColors.glonass,
        _ => AppColors.textSecondary,
      };

  @override
  bool shouldRepaint(_SkyPlotPainter oldDelegate) =>
      oldDelegate.satellites != satellites;
}

class _Cn0TrendPainter extends CustomPainter {
  const _Cn0TrendPainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : i * size.width / (values.length - 1);
      final y = size.height - (values[i].clamp(10, 50) - 10) / 40 * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Cn0TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
