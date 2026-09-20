import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../controllers/sync_status.dart';

/// A capsule that drops in from the top while the app is getting ready, says
/// what it is waiting for, and leaves with a brief "Synced" once it is done.
///
/// It reflects real state only ([SyncStatus]); it never advances on a timer.
/// Three refinements keep it from being noise:
///  * it waits [showDelay] before appearing, so a step that completes at once
///    never flashes a capsule;
///  * it stays for [doneHold] after finishing, so the user sees that it
///    finished rather than that it vanished;
///  * if satellites take longer than [slowAfter] it says so and what to do,
///    instead of spinning as if that were normal.
///
/// It never takes a tap: it sits over the screen and everything under it stays
/// usable.
class SyncCapsule extends StatefulWidget {
  const SyncCapsule({
    super.key,
    required this.status,
    this.showDelay = const Duration(milliseconds: 300),
    this.doneHold = const Duration(milliseconds: 1600),
    this.slowAfter = const Duration(seconds: 40),
  });

  final SyncStatus status;
  final Duration showDelay;
  final Duration doneHold;
  final Duration slowAfter;

  @override
  State<SyncCapsule> createState() => _SyncCapsuleState();
}

class _SyncCapsuleState extends State<SyncCapsule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
    reverseDuration: AppMotion.fast,
  );

  Timer? _showTimer;
  Timer? _hideTimer;
  Timer? _slowTimer;

  /// What the capsule last said while syncing, kept so the text does not change
  /// while it animates away.
  SyncStatus _shown = SyncStatus.idle;
  bool _finished = false;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _follow(widget.status);
  }

  @override
  void didUpdateWidget(SyncCapsule old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _follow(widget.status);
  }

  void _follow(SyncStatus status) {
    if (status.isSyncing) {
      _hideTimer?.cancel();
      _finished = false;
      _shown = status;
      if (_anim.isDismissed || _anim.status == AnimationStatus.reverse) {
        _showTimer ??= Timer(widget.showDelay, () {
          _showTimer = null;
          if (mounted) _anim.forward();
        });
      }
      if (status.phase == SyncPhase.satellites) {
        _slowTimer ??= Timer(widget.slowAfter, () {
          if (mounted) setState(() => _slow = true);
        });
      } else {
        _slowTimer?.cancel();
        _slowTimer = null;
        _slow = false;
      }
      return;
    }

    _showTimer?.cancel();
    _showTimer = null;
    _slowTimer?.cancel();
    _slowTimer = null;
    _slow = false;
    if (_anim.isDismissed) return; // never appeared: nothing to say "done" to
    _finished = true;
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.doneHold, () {
      if (mounted) _anim.reverse();
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _slowTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _anim.duration = AppMotion.of(context, AppMotion.medium);
    _anim.reverseDuration = AppMotion.of(context, AppMotion.fast);

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        if (_anim.isDismissed) return const SizedBox.shrink();
        // A little overshoot on the way in gives the "pop"; leaving is plain.
        final travel = _anim.status == AnimationStatus.reverse
            ? Curves.easeInCubic.transform(_anim.value)
            : Curves.easeOutBack.transform(_anim.value);
        return IgnorePointer(
          child: FractionalTranslation(
            translation: Offset(0, -(1 - travel) * 1.8),
            child: Opacity(
              opacity: _anim.value.clamp(0.0, 1.0),
              child: _CapsuleBody(
                status: _shown,
                finished: _finished,
                slow: _slow,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CapsuleBody extends StatelessWidget {
  const _CapsuleBody({
    required this.status,
    required this.finished,
    required this.slow,
  });

  final SyncStatus status;
  final bool finished;
  final bool slow;

  @override
  Widget build(BuildContext context) {
    final title = finished ? 'Synced' : 'Syncing';
    final detail = finished
        ? null
        : slow
            ? 'Still searching · try open sky'
            : status.label;
    final accent = finished
        ? AppColors.healthy
        : slow
            ? AppColors.warning
            : AppColors.primary;
    final done = finished ? SyncStatus.total : status.done;

    return Semantics(
      container: true,
      liveRegion: true,
      label: finished
          ? 'Synced'
          : 'Syncing. ${detail ?? ''}. Step ${status.done + 1} of ${SyncStatus.total}',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.max(
              0, MediaQuery.sizeOf(context).width - 2 * AppSpacing.md),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
            boxShadow: AppShadow.raised,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: finished
                      ? Icon(Icons.check_circle_rounded,
                          size: 18, color: accent)
                      : CircularProgressIndicator(
                          strokeWidth: 2.4,
                          strokeCap: StrokeCap.round,
                          valueColor: AlwaysStoppedAnimation(accent),
                        ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (detail != null)
                          TextSpan(
                            text: '  ·  $detail',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                _Steps(done: done, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Three small segments, one per thing that must be ready.
class _Steps extends StatelessWidget {
  const _Steps({required this.done, required this.color});

  final int done;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < SyncStatus.total; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.fast),
            width: 12,
            height: 4,
            decoration: BoxDecoration(
              color: i < done ? color : AppColors.surfaceBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}
