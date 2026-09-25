import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/nav/gnss/gnss_health.dart';
import '../../../../core/platform/gnss/gnss_integrity_monitor.dart';
import '../../../../core/platform/gnss/gnss_telemetry.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/standard_card.dart';

/// GNSS HEALTH card: the driver-facing state from `GnssHealthClassifier`
/// (big label + reasons + metric grid) plus the sky plot and C/N0 trend the
/// receiver telemetry has always driven. `assessment`/`cn0History` are the
/// older single-anomaly-bucket monitor's output, kept only for the C/N0
/// trend chart below.
class GnssIntegrityPanel extends StatelessWidget {
  const GnssIntegrityPanel({
    super.key,
    required this.telemetry,
    required this.assessment,
    required this.cn0History,
    required this.health,
  });

  final GnssTelemetrySnapshot? telemetry;
  final GnssIntegrityAssessment assessment;
  final List<double> cn0History;
  final GnssHealthAssessment health;

  static Color _stateColor(GnssHealthState state) => switch (state) {
        GnssHealthState.waiting => AppColors.textSecondary,
        GnssHealthState.normal => AppColors.success,
        GnssHealthState.degraded => AppColors.warning,
        GnssHealthState.multipathSuspected => AppColors.warning,
        GnssHealthState.interferenceSuspected => AppColors.error,
        GnssHealthState.outage => AppColors.error,
      };

  @override
  Widget build(BuildContext context) {
    final snapshot = telemetry;
    final color = _stateColor(health.state);
    return StandardCard(
      titleText: 'GNSS HEALTH',
      trailing: Text(
        health.state == GnssHealthState.waiting
            ? '--'
            : health.state.label.toUpperCase(),
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
            health.state == GnssHealthState.waiting
                ? 'Waiting'
                : health.state.label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          for (final reason in health.reasons)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                reason,
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          _MetricGrid(metrics: health.metrics),
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

/// Compact metric tiles for the GNSS HEALTH card. `--` (never a guessed
/// number) whenever the platform/API level did not report a field.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final GnssHealthMetrics metrics;

  static const _constellationOrder = [
    (GnssHealthConstellation.gps, 'GPS'),
    (GnssHealthConstellation.glonass, 'GLONASS'),
    (GnssHealthConstellation.galileo, 'Galileo'),
    (GnssHealthConstellation.beidou, 'BeiDou'),
    (GnssHealthConstellation.navic, 'NavIC'),
    (GnssHealthConstellation.qzss, 'QZSS'),
  ];

  @override
  Widget build(BuildContext context) {
    final mixLabel = _constellationOrder
        .map((entry) =>
            '${entry.$2} ${metrics.constellationUsed[entry.$1] ?? 0}/'
            '${metrics.constellationVisible[entry.$1] ?? 0}')
        .join(' · ');
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      children: [
        _tile('${metrics.satellitesUsed}/${metrics.satellitesVisible}',
            'Satellites used/visible'),
        _tile(
          metrics.meanCn0DbHz == null
              ? '--'
              : '${metrics.meanCn0DbHz!.toStringAsFixed(1)} dBHz',
          'Mean C/N₀',
        ),
        _tile('${metrics.navicUsed}/${metrics.navicVisible}',
            'NavIC used/visible'),
        _tile(mixLabel, 'Constellation mix (used/visible)'),
        _tile('${metrics.positionJumpRejects}', 'Position-jump rejects (60s)'),
        _tile('${metrics.accelerationJumpRejects}',
            'Velocity-jump rejects (60s)'),
        _tile('${metrics.headingInconsistencies}', 'Heading inconsistencies'),
        _tile(metrics.accuracyWorsening ? 'Worsening' : 'Stable',
            'Accuracy trend'),
        _tile(
          metrics.clockDiscontinuityCount?.toString() ?? '--',
          'Clock anomalies',
        ),
        _tile(
          metrics.multipathDetectedCount?.toString() ?? '--',
          'Multipath indicators',
        ),
        _tile(
          metrics.meanAutomaticGainControlDb == null
              ? '--'
              : '${metrics.meanAutomaticGainControlDb!.toStringAsFixed(1)} dB',
          'AGC',
        ),
      ],
    );
  }

  static Widget _tile(String value, String label) => SizedBox(
        width: 132,
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
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
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
