import 'dart:collection';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';

/// An [IndexedStack] whose pages use a restrained, directional parallax slide
/// when the selected tab changes, in the style of an iOS push transition.
///
/// Every page stays mounted, so scroll positions, the map camera and text stay
/// exactly as they were. Pages that are not showing also have their tickers
/// switched off: a hidden map or spinner is not animating in the background,
/// and a page's own entrance animation waits until it is first shown.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 360),
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
  final Queue<bool> _recentSlowFrames = Queue<bool>();
  int? _previousIndex;
  double _direction = 1;
  Duration _slowFrameBudget = const Duration(milliseconds: 19);
  Duration _smoothFrameBudget = const Duration(milliseconds: 11);
  int _smoothFrameStreak = 0;
  bool _lowPerformance = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_onFrameTimings);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && _previousIndex != null) {
        setState(() => _previousIndex = null);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final refreshRate = View.of(context).display.refreshRate;
    if (!refreshRate.isFinite || refreshRate <= 0) return;
    final frameBudgetMicros = (1000000 / refreshRate).round();
    _slowFrameBudget = Duration(
      microseconds: (frameBudgetMicros * 1.15).round(),
    );
    _smoothFrameBudget = Duration(
      microseconds: (frameBudgetMicros * 0.70).round(),
    );
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    var profileChanged = false;
    for (final timing in timings) {
      final frameWork = timing.buildDuration + timing.rasterDuration;
      final slow = frameWork > _slowFrameBudget;
      _recentSlowFrames.addLast(slow);
      if (_recentSlowFrames.length > 8) _recentSlowFrames.removeFirst();

      if (_lowPerformance) {
        _smoothFrameStreak =
            frameWork < _smoothFrameBudget ? _smoothFrameStreak + 1 : 0;
        if (_smoothFrameStreak >= 90) {
          _lowPerformance = false;
          _smoothFrameStreak = 0;
          _recentSlowFrames.clear();
          profileChanged = true;
        }
      } else if (_recentSlowFrames.length == 8 &&
          _recentSlowFrames.where((isSlow) => isSlow).length >= 4) {
        _lowPerformance = true;
        _smoothFrameStreak = 0;
        profileChanged = true;
      }
    }
    if (profileChanged && mounted) setState(() {});
  }

  static const Animation<Offset> _still =
      AlwaysStoppedAnimation<Offset>(Offset.zero);

  @override
  void didUpdateWidget(covariant FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    _previousIndex = old.index;
    _direction = widget.index > old.index ? 1 : -1;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _previousIndex = null;
      _controller.value = 1;
    } else {
      _controller.duration =
          _lowPerformance ? const Duration(milliseconds: 250) : widget.duration;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_onFrameTimings);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hiddenIndices = <int>[
      for (var i = 0; i < widget.children.length; i++)
        if (i != widget.index && i != _previousIndex) i,
    ];
    final entryTravel = _lowPerformance ? 0.055 : 0.10;
    final exitTravel = _lowPerformance ? 0.0 : 0.035;
    final incoming = Tween<Offset>(
      begin: Offset(_direction * entryTravel, 0),
      end: Offset.zero,
    ).animate(_curve);
    final outgoing = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(-_direction * exitTravel, 0),
    ).animate(_curve);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final i in hiddenIndices)
          Offstage(
            key: ValueKey<int>(i),
            child: TickerMode(
              enabled: false,
              child: SlideTransition(
                position: _still,
                child: widget.children[i],
              ),
            ),
          ),
        if (_previousIndex case final previous?)
          Offstage(
            key: ValueKey<int>(previous),
            offstage: false,
            child: TickerMode(
              enabled: false,
              child: IgnorePointer(
                child: SlideTransition(
                  position: outgoing,
                  child: widget.children[previous],
                ),
              ),
            ),
          ),
        Offstage(
          key: ValueKey<int>(widget.index),
          offstage: false,
          child: TickerMode(
            enabled: true,
            child: SlideTransition(
              position: incoming,
              child: widget.children[widget.index],
            ),
          ),
        ),
      ],
    );
  }
}
