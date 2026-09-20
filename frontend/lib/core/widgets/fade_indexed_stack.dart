import 'package:flutter/material.dart';

/// An [IndexedStack] whose pages fade (and drift down a few pixels) into view
/// instead of swapping instantly.
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
    this.duration = const Duration(milliseconds: 260),
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
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late final Animation<Offset> _drift =
      Tween<Offset>(begin: const Offset(0, -0.012), end: Offset.zero)
          .animate(_curve);

  static const Animation<double> _opaque = AlwaysStoppedAnimation<double>(1);
  static const Animation<Offset> _still =
      AlwaysStoppedAnimation<Offset>(Offset.zero);

  @override
  void didUpdateWidget(covariant FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != widget.index,
            child: TickerMode(
              enabled: i == widget.index,
              // The same widget types in the same places for every page, so
              // switching the active one never rebuilds a page's state.
              child: FadeTransition(
                opacity: i == widget.index ? _curve : _opaque,
                child: SlideTransition(
                  position: i == widget.index ? _drift : _still,
                  child: widget.children[i],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
