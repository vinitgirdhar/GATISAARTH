import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Design tokens. Palette follows iOS system-color conventions (systemBlue,
/// systemGreen, systemGray groups etc.) so the app reads as native-iOS rather
/// than the earlier tactical/military HUD look.
class AppColors {
  // Light surfaces (iOS systemGroupedBackground / systemBackground)
  static const Color dark = Color(0xFFF2F2F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF2F2F7);
  static const Color surfaceBorder = Color(0xFFE5E5EA);
  static const Color surfaceHighlight = Color(0xFFEAF3FF);

  // Dark surfaces (iOS systemGroupedBackground / secondarySystemBackground, dark mode)
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkBorder = Color(0xFF38383A);

  // Text (iOS label / secondaryLabel / tertiaryLabel)
  static const Color textPrimary = Color(0xFF1C1C1E);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textMuted = Color(0xFFAEAEB2);
  static const Color textInverse = Color(0xFFFFFFFF);

  // Accent (iOS systemBlue / systemIndigo)
  static const Color cyan = Color(0xFF0A84FF);
  static const Color blue = Color(0xFF007AFF);
  static const Color indigo = Color(0xFF5856D6);

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
  static const Color disabled = Color(0xFFC7C7CC);
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

  static List<BoxShadow> card = [
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

  static List<BoxShadow> raised = [
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

  /// Extra depth for the primary CTA / hero elements only.
  static List<BoxShadow> floating = [
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

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.dark,
      cardColor: AppColors.surface,
      dividerColor: AppColors.surfaceBorder,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: _pageTransitions,
      colorScheme: const ColorScheme.light(
        primary: AppColors.cyan,
        secondary: AppColors.indigo,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.dark,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle:
            const TextStyle(color: AppColors.textInverse, fontFamily: fontFamily),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      textTheme: const TextTheme(
        // Hero numerals (speed, big stats) — bold rounded, no tracking.
        displayLarge: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 40,
          height: 1.05,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 24,
          letterSpacing: -0.3,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
        // Small section eyebrows (Apple Health / Settings style): quiet, not shouty.
        labelSmall: TextStyle(
          color: AppColors.textSecondary,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 0.2,
        ),
        bodyLarge: TextStyle(
            color: AppColors.textPrimary,
            fontFamily: fontFamily,
            fontSize: 16),
        bodyMedium: TextStyle(
            color: AppColors.textSecondary,
            fontFamily: fontFamily,
            fontSize: 14),
        bodySmall: TextStyle(
            color: AppColors.textMuted, fontFamily: fontFamily, fontSize: 12),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      pageTransitionsTheme: _pageTransitions,
      scaffoldBackgroundColor: AppColors.darkBackground,
      cardColor: AppColors.darkSurface,
      dividerColor: AppColors.darkBorder,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.cyan,
        secondary: AppColors.indigo,
        surface: AppColors.darkSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      ),
    );
  }
}
