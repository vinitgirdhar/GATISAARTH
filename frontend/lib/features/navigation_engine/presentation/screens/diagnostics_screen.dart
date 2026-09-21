import 'package:flutter/material.dart';

import '../../../../core/nav/model/nav_snapshot.dart';
import '../../../../core/nav/gnss/gnss_quality.dart';
import '../../../../core/nav/motion/motion_classifier.dart';
import '../../../../core/nav/sensors/barometer.dart';
import '../../../../core/nav/sensors/sensor_fault_detector.dart';
import '../../../../core/nav/sensors/sensor_sample.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../navigation_ui/presentation/controllers/live_session_controller.dart';
import '../../../navigation_ui/presentation/controllers/live_session_scope.dart';
import '../../../navigation_ui/presentation/widgets/satellite_breakdown.dart';
import '../../data/repositories/demo_navigation_repository.dart';

/// Live engineering view of the navigation core (§64, §79).
///
/// Everything here is measured. A value the phone cannot produce is shown as
/// `--` and a panel that is still demonstration data says so in as many words —
/// the one panel that still is, is labelled, and it is the only one (§65, §83).
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = LiveSessionScope.of(context);
    final snapshot = session.navSnapshot;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _engine(context, session, snapshot),
          _uncertainty(context, snapshot),
          _sensors(context, snapshot),
          _gnss(context, snapshot),
          _motion(context, snapshot),
          _contribution(context, snapshot),
          _subsystems(context, snapshot),
          _performance(context, session),
          _transitions(context, session),
          _demoSatellites(context),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- sections

  Widget _engine(
    BuildContext context,
    LiveSessionController session,
    NavigationSnapshot? snapshot,
  ) {
    return _Panel(
      title: 'Navigation core',
      children: [
        _Row('Leading the position', session.isEngineLeading ? 'Yes' : 'No'),
        if (!session.isEngineLeading)
          _Row('Blocked by', session.engineHandoverBlocker ?? '--'),
        _Row('Mode', snapshot?.mode.label ?? '--'),
        _Row('Integrity', snapshot?.integrity.label ?? '--'),
        _Row('Position source', snapshot?.positionSource.name ?? '--'),
        _Row(
          'Mount alignment',
          snapshot?.alignmentConfidence == null
              ? '--'
              : '${(snapshot!.alignmentConfidence! * 100).round()} %',
        ),
        _Row('Alignment events', '${session.alignmentEvents}'),
        _Row('Alignment samples', '${session.alignmentSamples}'),
        _Row('Levelled', session.hasLevelling ? 'Yes' : 'No'),
        _Row(
          'Sensor calibration',
          snapshot?.calibrationQuality == null
              ? '-- (not calibrated)'
              : '${(snapshot!.calibrationQuality! * 100).round()} %',
        ),
      ],
    );
  }

  Widget _uncertainty(BuildContext context, NavigationSnapshot? s) {
    String metres(double? v) =>
        v == null ? '--' : '± ${v.toStringAsFixed(1)} m';
    return _Panel(
      title: 'Uncertainty (from the covariance, not a formula)',
      children: [
        _Row('Horizontal position', metres(s?.horizontalSigmaM)),
        _Row('Vertical position', metres(s?.verticalSigmaM)),
        _Row(
          'Speed',
          s?.speedSigmaMps == null
              ? '--'
              : '± ${s!.speedSigmaMps!.toStringAsFixed(2)} m/s',
        ),
        _Row(
          'Heading',
          s?.headingSigmaDeg == null
              ? '--'
              : '± ${s!.headingSigmaDeg!.toStringAsFixed(1)}°',
        ),
        if (s != null && s.outageDuration > Duration.zero) ...[
          _Row('Outage', '${s.outageDuration.inSeconds} s'),
          _Row(
            'Dead-reckoned',
            '${s.outageDistanceM.toStringAsFixed(0)} m',
          ),
        ],
      ],
    );
  }

  Widget _sensors(BuildContext context, NavigationSnapshot? s) {
    final stats = s?.sensorStats ?? const <SensorType, SensorStreamStats>{};
    if (stats.isEmpty) {
      return const _Panel(
        title: 'Sensors',
        children: [_Row('Streams', '-- (no samples yet)')],
      );
    }
    return _Panel(
      title: 'Sensors (measured rates, not nominal)',
      children: [
        for (final entry in stats.entries)
          _Row(
            entry.key.label,
            _sensorLine(entry.value, s?.sensorFaults[entry.key]),
          ),
      ],
    );
  }

  static String _sensorLine(
    SensorStreamStats stats,
    SensorDiagnosis? diagnosis,
  ) {
    if (!stats.available) return '-- (not on this device)';
    final hz = stats.effectiveHz;
    final rate = hz == null ? '--' : '${hz.toStringAsFixed(1)} Hz';
    final drops = stats.dropped > 0 ? ', ${stats.dropped} dropped' : '';
    // A working sensor is a stronger claim than a present one, so the fault
    // state is what gets said when there is one.
    final fault = (diagnosis == null || diagnosis.isHealthy)
        ? ''
        : ', ${diagnosis.fault.label}';
    return '$rate, ${stats.quality.name}$drops$fault';
  }

  Widget _gnss(BuildContext context, NavigationSnapshot? s) {
    final gnss = s?.gnss;
    return _Panel(
      title: 'GNSS',
      children: [
        _Row('Quality', gnss?.quality.name ?? '--'),
        _Row(
          'Score',
          gnss == null ? '--' : '${(gnss.score * 100).round()} %',
        ),
        _Row('Last fix', gnss == null ? '--' : (gnss.usable
            ? 'accepted'
            : 'rejected: ${gnss.reason.name}')),
        _Row('Integrity', gnss?.integrity.label ?? '--'),
        _Row(
          'Measurement sigma',
          gnss == null ? '--' : '${gnss.horizontalSigmaM.toStringAsFixed(1)} m',
        ),
        _Row(
          'Satellites',
          '-- (Android GnssStatus not wired)',
        ),
        for (final note in gnss?.notes ?? const <String>[])
          _Row('Note', note),
      ],
    );
  }

  Widget _motion(BuildContext context, NavigationSnapshot? s) {
    final m = s?.motion;
    return _Panel(
      title: 'Vehicle state',
      children: [
        _Row('State', m?.state.label ?? '--'),
        _Row('Stationary', m == null ? '--' : (m.isStationary ? 'Yes' : 'No')),
        _Row(
          'NHC applied',
          m == null ? '--' : (m.nhcApplicable ? 'Yes' : 'No'),
        ),
        _Row(
          'Vibration RMS',
          m == null ? '--' : m.vibrationRms.toStringAsFixed(2),
        ),
        _Row(
          'Lean',
          m?.leanAngleRad == null
              ? '--'
              : '${m!.leanAngleDeg.toStringAsFixed(0)}°',
        ),
        if (s?.barometer != null) ...[
          _Row('Vertical motion', s!.barometer!.motion.label),
          _Row(
            'Relative height',
            s.barometer!.relativeAltitudeM == null
                ? '--'
                : '${s.barometer!.relativeAltitudeM!.toStringAsFixed(1)} m',
          ),
          _Row('Level changes', '${s.barometer!.levelChanges}'),
        ] else
          const _Row('Barometer', '-- (not on this device)'),
      ],
    );
  }

  Widget _contribution(BuildContext context, NavigationSnapshot? s) {
    final c = s?.contribution;
    if (c == null || c.isEmpty) {
      return const _Panel(
        title: 'Why this position?',
        children: [_Row('Contribution', '-- (nothing measured yet)')],
      );
    }
    return _Panel(
      title: 'Why this position?',
      subtitle: 'Share of the position certainty each source supplied, by the '
          'variance it actually removed. Not a probability that any is right.',
      children: [
        for (final entry in c.asMap.entries)
          _Row(entry.key, '${(entry.value * 100).round()} %'),
      ],
    );
  }

  Widget _subsystems(BuildContext context, NavigationSnapshot? s) {
    return _Panel(
      title: 'Subsystems',
      children: [
        _Row(
          'Neural velocity',
          s?.ai.detail ?? '-- (unavailable)',
        ),
        _Row(
          'Map matching',
          s?.mapMatch.detail ?? '-- (unavailable)',
        ),
        for (final note in s?.notes ?? const <String>[]) _Row('Note', note),
      ],
    );
  }

  Widget _performance(BuildContext context, LiveSessionController session) {
    final mean = session.engineMeanMicros;
    final peak = session.enginePeakMicros;
    return _Panel(
      title: 'Performance (measured)',
      children: [
        _Row(
          'Core per frame',
          mean == null ? '--' : '${mean.toStringAsFixed(0)} µs',
        ),
        _Row('Peak', peak == null ? '--' : '$peak µs'),
        _Row('Fixes fed', '${session.engineFixCount}'),
        _Row(
          'Recording',
          session.isRecording
              ? '${session.recordedLines} samples'
              : 'Not recording',
        ),
      ],
    );
  }

  Widget _transitions(BuildContext context, LiveSessionController session) {
    final transitions = session.engineTransitions;
    final recent = transitions.length <= 8
        ? transitions
        : transitions.sublist(transitions.length - 8);
    return _Panel(
      title: 'Mode transitions',
      children: [
        if (recent.isEmpty) const _Row('History', '--'),
        for (final t in recent.reversed)
          _Row('${t.from.name} → ${t.to.name}', t.reason),
      ],
    );
  }

  Widget _demoSatellites(BuildContext context) {
    final data = const DemoNavigationRepository().current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The panel below is illustrative demo data. Android '
                  'GnssStatus is not wired in, so per-constellation satellite '
                  'counts are not available. Everything above this line is '
                  'measured.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        SatelliteBreakdown(satelliteBreakdown: data.satelliteBreakdown),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.lightSurfaceBorder,
        ),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
