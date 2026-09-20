import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Design tokens. Palette follows iOS system-color conventions (systemBlue,
/// systemGreen, systemGray groups etc.) so the app reads as native-iOS rather
/// than the earlier tactical/military HUD look.
///
/// Surface and label tokens resolve against [isDark]. The flag is set once per
/// frame by the app root (see `app_widget.dart`) before the tree is built, and
/// the root re-keys `MaterialApp` on a theme flip so every widget — including
/// `const` subtrees that never read `Theme.of` — is rebuilt with the new
/// values.
/// ponytail: one app-wide brightness flag instead of threading a palette
/// through ~60 call sites; move to a ThemeExtension if a second theme (or a
/// per-subtree brightness override) is ever needed.
class AppColors {
  static bool isDark = false;

  // ---------------------------------------------------------------- surfaces
  // Light: iOS systemGroupedBackground / systemBackground.
  // Dark:  iOS systemGroupedBackground / secondarySystemBackground.
  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSubtle = Color(0xFFF2F2F7);
  static const Color lightSurfaceBorder = Color(0xFFE5E5EA);
  static const Color lightSurfaceHighlight = Color(0xFFEAF3FF);

  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceSubtle = Color(0xFF2C2C2E);
  static const Color darkBorder = Color(0xFF38383A);
  static const Color darkSurfaceHighlight = Color(0xFF13233A);

  /// Legacy alias for the light scaffold background.
  static const Color dark = lightBackground;

  static Color get background => isDark ? darkBackground : lightBackground;
  static Color get surface => isDark ? darkSurface : lightSurface;
  static Color get surfaceSubtle =>
      isDark ? darkSurfaceSubtle : lightSurfaceSubtle;
  static Color get surfaceBorder => isDark ? darkBorder : lightSurfaceBorder;
  static Color get surfaceHighlight =>
      isDark ? darkSurfaceHighlight : lightSurfaceHighlight;

  // ------------------------------------------------------------------- text
  // iOS label / secondaryLabel / tertiaryLabel in each brightness.
  static const Color lightTextPrimary = Color(0xFF1C1C1E);
  static const Color lightTextSecondary = Color(0xFF8E8E93);
  static const Color lightTextMuted = Color(0xFFAEAEB2);

  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF98989F);
  static const Color darkTextMuted = Color(0xFF6C6C70);

  static Color get textPrimary => isDark ? darkTextPrimary : lightTextPrimary;
  static Color get textSecondary =>
      isDark ? darkTextSecondary : lightTextSecondary;
  static Color get textMuted => isDark ? darkTextMuted : lightTextMuted;

  /// Text drawn on top of an accent fill — white in both brightnesses.
  static const Color textInverse = Color(0xFFFFFFFF);

  // Accent (iOS systemBlue / systemIndigo)
  static const Color cyan = Color(0xFF0A84FF);
  static const Color blue = Color(0xFF007AFF);
  static const Color indigo = Color(0xFF5856D6);

  // UI/UX Board Theme Tokens
  static const Color primary = Color(0xFF3882F6);
  static const Color secondary = Color(0xFF06B6D4);
  static const Color accent = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
  static const Color boardWarning = Color(0xFFFACC15);
  static const Color boardError = Color(0xFFEF4444);

  // Fusion Modes (iOS systemGreen / systemOrange / systemRed / systemPurple)
  static const Color gnssLocked = Color(0xFF34C759);
  static const Color gnssDegraded = Color(0xFFFF9500);
  static const Color deadReckoning = Color(0xFFFF3B30);
  static const Color reacquiring = Color(0xFFAF52DE);

  // Constellations
  static const Color navIC = Color(0xFFFF9500);
  static const Color gps = Color(0xFF0A84FF);
  static const Color galileo = Color(0xFF30D158);
  static const Color glonass = Color(0xFFBF5AF2);

  // Status
  static const Color healthy = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);

  static const Color lightDisabled = Color(0xFFC7C7CC);
  static const Color darkDisabled = Color(0xFF48484A);
  static Color get disabled => isDark ? darkDisabled : lightDisabled;
}

/// 8pt spacing grid, same as iOS Human Interface Guidelines.
class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

/// Corner radii. iOS continuous ("squircle") corners read larger than
/// Android's default Material radii — cards/sheets sit at 20, controls at 14,
/// pills are fully round.
class AppRadius {
  static const double card = 20.0;
  static const double control = 14.0;
  static const double pill = 999.0;
  static const BorderRadius cardRadius =
      BorderRadius.all(Radius.circular(card));
  static const BorderRadius controlRadius =
      BorderRadius.all(Radius.circular(control));
  static const BorderRadius pillRadius =
      BorderRadius.all(Radius.circular(pill));
}

/// Soft elevation used instead of hard 1px borders — iOS cards separate from
/// their background with shadow, not a stroke. Each level stacks a tight
/// "contact" shadow (defines the edge), a mid shadow (body) and a wide, soft
/// "ambient" shadow (lift) — a single flat shadow reads flat; three layered
/// ones read like a real elevated surface.
///
/// Shadows are static and painted once per repaint; every card sits in its own
/// RepaintBoundary (see FadeSlideIn) so they are not re-rasterised while the
/// live numbers change.
class AppShadow {
  static const Color _ink = Color(0xFF1C1C1E);

  /// In dark mode cards separate from the black background by their own
  /// surface colour (the iOS convention) — a black shadow on black is
  /// invisible, so the stack is dropped entirely.
  static List<BoxShadow> get card => AppColors.isDark
      ? const <BoxShadow>[]
      : [
          BoxShadow(
            color: _ink.withValues(alpha: 0.08),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: _ink.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _ink.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ];

  static List<BoxShadow> get raised => AppColors.isDark
      ? const <BoxShadow>[]
      : [
          BoxShadow(
            color: _ink.withValues(alpha: 0.10),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: _ink.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: _ink.withValues(alpha: 0.18),
            blurRadius: 44,
            offset: const Offset(0, 22),
          ),
        ];

  /// Extra depth for the primary CTA / hero elements only. The glow is the
  /// accent colour, so it reads in both brightnesses.
  static List<BoxShadow> get floating => [
        BoxShadow(
          color: const Color(0xFF0A84FF).withValues(alpha: 0.14),
          blurRadius: 6,
          offset: const Offset(0, 3),
        ),
        BoxShadow(
          color: const Color(0xFF0A84FF).withValues(alpha: 0.28),
          blurRadius: 30,
          offset: const Offset(0, 16),
        ),
      ];
}

class AppTheme {
  static const String fontFamily = '.SF Pro Text';

  /// iOS-style push transition (slide + edge-swipe-back) on every platform.
  static const PageTransitionsTheme _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  );

  /// Same type ramp in both brightnesses — only the label colours differ.
  static TextTheme _textTheme({
    required Color primary,
    required Color secondary,
    required Color muted,
  }) {
    return TextTheme(
      // Hero numerals (speed, big stats) — bold rounded, no tracking.
      displayLarge: TextStyle(
        color: primary,
        fontFamily: fontFamily,
        fontWeight: FontWeight.w700,
        fontSize: 40,
        height: 1.05,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        color: primary,
        fontFamily: fontFamily,
        fontWeight: FontWeight.w700,
        fontSize: 24,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        color: primary,
        fontFamily: fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 17,
      ),
      // Small section eyebrows (Apple Health / Settings style): quiet, not shouty.
      labelSmall: TextStyle(
        color: secondary,
        fontFamily: fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        letterSpacing: 0.2,
      ),
      bodyLarge: TextStyle(color: primary, fontFamily: fontFamily, fontSize: 16),
      bodyMedium:
          TextStyle(color: secondary, fontFamily: fontFamily, fontSize: 14),
      bodySmall: TextStyle(color: muted, fontFamily: fontFamily, fontSize: 12),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.lightBackground,
      cardColor: AppColors.lightSurface,
      dividerColor: AppColors.lightSurfaceBorder,
      // Material 3 dividers ignore `dividerColor` and use the scheme's outline
      // colour, which is near-white in dark mode: bright rules across a dark card.
      dividerTheme: const DividerThemeData(
        color: AppColors.lightSurfaceBorder,
        thickness: 1,
        space: 1,
      ),
      splashFactory: InkSparkle.splashFactory,
      // A long-press on a tooltip vibrates by default; nothing here should.
      tooltipTheme: const TooltipThemeData(enableFeedback: false),
      pageTransitionsTheme: _pageTransitions,
      colorScheme: const ColorScheme.light(
        primary: AppColors.cyan,
        secondary: AppColors.indigo,
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightTextPrimary,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBackground,
        foregroundColor: AppColors.lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.lightTextPrimary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.lightTextPrimary,
        contentTextStyle: const TextStyle(
            color: AppColors.textInverse, fontFamily: fontFamily),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      textTheme: _textTheme(
        primary: AppColors.lightTextPrimary,
        secondary: AppColors.lightTextSecondary,
        muted: AppColors.lightTextMuted,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.darkBackground,
      cardColor: AppColors.darkSurface,
      dividerColor: AppColors.darkBorder,
      dividerTheme: const DividerThemeData(
        color: AppColors.darkBorder,
        thickness: 1,
        space: 1,
      ),
      splashFactory: InkSparkle.splashFactory,
      // A long-press on a tooltip vibrates by default; nothing here should.
      tooltipTheme: const TooltipThemeData(enableFeedback: false),
      pageTransitionsTheme: _pageTransitions,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.cyan,
        secondary: AppColors.indigo,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkTextPrimary,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.darkTextPrimary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkSurfaceSubtle,
        contentTextStyle: const TextStyle(
            color: AppColors.darkTextPrimary, fontFamily: fontFamily),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      textTheme: _textTheme(
        primary: AppColors.darkTextPrimary,
        secondary: AppColors.darkTextSecondary,
        muted: AppColors.darkTextMuted,
      ),
    );
  }
}
