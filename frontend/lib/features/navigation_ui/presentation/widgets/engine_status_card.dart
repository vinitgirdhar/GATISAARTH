import 'package:flutter/material.dart';

import '../../../../core/nav/model/nav_snapshot.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';

/// Shows whether the navigation core is driving the position, and lets the
/// driver record the drive.
///
/// Two jobs, one card, because they belong together: the only way to find out
/// whether the core is actually better is to record a drive and replay it, and
/// the only way to know whether the recording is worth anything is to see
/// whether the core was leading while it ran.
///
/// Every value is either measured or shown as `--`. Nothing here is a
/// placeholder (§65, §83).
class EngineStatusCard extends StatelessWidget {
  const EngineStatusCard({
    super.key,
    required this.snapshot,
    required this.isLeading,
    required this.blocker,
    required this.isRecording,
    required this.recordedDuration,
    required this.recordedLines,
    this.recordingError,
    this.onStartRecording,
    this.onStopRecording,
    this.onMarkEvent,
    this.onMarkBump,
    this.compact = false,
    this.onToggleDetails,
  });

  final NavigationSnapshot? snapshot;

  /// True when the core, not the heuristic pipeline, owns the position.
  final bool isLeading;

  /// Why it is not leading yet. Null once it is.
  final String? blocker;

  final bool isRecording;
  final Duration recordedDuration;
  final int recordedLines;
  final Object? recordingError;

  final VoidCallback? onStartRecording;
  final VoidCallback? onStopRecording;
  final VoidCallback? onMarkEvent;

  /// Labels a bump or pothole in the recording: supervised labels for a
  /// future vibration classifier.
  final VoidCallback? onMarkBump;
  final bool compact;
  final VoidCallback? onToggleDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = AppColors.isDark;
    return Container(
      margin: EdgeInsets.only(bottom: compact ? AppSpacing.sm : AppSpacing.md),
      padding: EdgeInsets.all(compact ? 12 : 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.lightSurfaceBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Navigation core',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusPill(isLeading: isLeading),
              if (onToggleDetails != null)
                IconButton(
                  tooltip: compact ? 'Show core details' : 'Hide core details',
                  onPressed: onToggleDetails,
                  icon: Icon(
                    compact
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 6),
            Text(
              isLeading
                  ? 'Position, speed and heading come from the filter'
                  : blocker ?? 'Starting',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _metrics(theme),
          ],
          SizedBox(height: compact ? 8 : AppSpacing.sm),
          _recordingRow(context, theme),
          if (recordingError != null) ...[
            const SizedBox(height: 6),
            Text(
              'Recording failed: $recordingError',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metrics(ThemeData theme) {
    final s = snapshot;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: 6,
      children: [
        _Metric(
          label: 'Mode',
          value: s?.mode.label ?? '--',
          theme: theme,
        ),
        _Metric(
          label: 'Integrity',
          value: s?.integrity.label ?? '--',
          theme: theme,
        ),
        _Metric(
          label: 'Position',
          value: s?.horizontalSigmaM == null
              ? '--'
              : '± ${s!.horizontalSigmaM!.toStringAsFixed(1)} m',
          theme: theme,
        ),
        _Metric(
          label: 'Heading',
          value: s?.headingSigmaDeg == null
              ? '--'
              : '± ${s!.headingSigmaDeg!.toStringAsFixed(0)}°',
          theme: theme,
        ),
        _Metric(
          label: 'Mount',
          value: s?.alignmentConfidence == null
              ? '--'
              : '${(s!.alignmentConfidence! * 100).round()} %',
          theme: theme,
        ),
      ],
    );
  }

  Widget _recordingRow(BuildContext context, ThemeData theme) {
    if (!isRecording) {
      return _ActionButton(
        label: 'Record drive',
        icon: Icons.fiber_manual_record,
        color: AppColors.error,
        onTap: onStartRecording,
      );
    }
    final minutes = recordedDuration.inMinutes;
    final seconds = recordedDuration.inSeconds % 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recording  '
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}'
          '  ·  $recordedLines samples',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'Stop',
                icon: Icons.stop,
                color: AppColors.textSecondary,
                onTap: onStopRecording,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ActionButton(
                label: 'Bump',
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
                onTap: onMarkBump,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ActionButton(
                label: 'Mark',
                icon: Icons.flag_outlined,
                color: AppColors.cyan,
                onTap: onMarkEvent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isLeading});

  final bool isLeading;

  @override
  Widget build(BuildContext context) {
    final color = isLeading ? AppColors.healthy : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isLeading ? 'Leading' : 'Calibrating',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final callback = onTap;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: callback ?? () {},
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: callback == null ? 0.06 : 0.15),
            borderRadius: AppRadius.controlRadius,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
