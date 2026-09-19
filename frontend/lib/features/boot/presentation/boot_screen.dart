import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/router/app_router.dart';
import '../../navigation_ui/presentation/controllers/live_session_scope.dart';
import 'boot_sequence.dart';

/// Brand colours for the boot screen only. It is always dark, whatever the
/// app theme is, so it does not use the light/dark palette.
class _Boot {
  static const Color ink = Color(0xFF050A14);
  static const Color inkTop = Color(0xFF0C1B30);
  static const Color accent = Color(0xFF4FC3F7);
  static const Color accentDeep = Color(0xFF1E70E0);
  static const Color faint = Color(0x4DFFFFFF);
}

/// Full-screen start-up sequence: displays the designed booting image artwork with
/// a dynamic progress bar wired to the real boot work (see [BootSequence]).
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  BootSequence? _boot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_boot != null) return;
    final sequence = BootSequence(session: LiveSessionScope.of(context));
    _boot = sequence;
    sequence.run().then((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
    });
  }

  @override
  void dispose() {
    _boot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boot = _boot!;
    final size = MediaQuery.sizeOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _Boot.ink,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _Boot.ink,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _BootBackground(),
            Positioned(
              left: 28,
              right: 28,
              top: size.height * 0.865,
              child: AnimatedBuilder(
                animation: boot,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ProgressBar(value: boot.progress),
                    const SizedBox(height: 14),
                    _Spaced(
                      boot.isFinished ? 'READY' : '${boot.label}...',
                      size: 10,
                      tracking: 3,
                      color: _Boot.faint,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The launch artwork background image, with a painted gradient fallback.
class _BootBackground extends StatelessWidget {
  const _BootBackground();

  static const Widget _fallback = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_Boot.inkTop, _Boot.ink, Color(0xFF02060D)],
        stops: [0, 0.55, 1],
      ),
    ),
    child: SizedBox.expand(),
  );

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/boot_background.png',
      fit: BoxFit.fill,
      errorBuilder: (context, error, stack) => _fallback,
    );
  }
}

/// Boot progress. Width follows real completed work, eased so the bar glides
/// between stages instead of jumping.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: 4.5,
          color: const Color(0x1FFFFFFF),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: animated,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: const LinearGradient(
                  colors: [_Boot.accent, _Boot.accentDeep],
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x664FC3F7), blurRadius: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Centred, letter-spaced caps — the only type style this screen uses.
class _Spaced extends StatelessWidget {
  const _Spaced(
    this.text, {
    required this.size,
    required this.tracking,
    required this.color,
  });

  final String text;
  final double size;
  final double tracking;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w400,
        // The trailing space of the last glyph is part of the tracking, so the
        // line optically sits a little left; that matches the artwork.
        letterSpacing: tracking,
        height: 1.2,
      ),
    );
  }
}
