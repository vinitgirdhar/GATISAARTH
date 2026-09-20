import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// Owns the light/dark choice and remembers it across launches.
///
/// The stored value is a plain bool rather than a [ThemeMode] name: the app
/// offers an explicit two-way switch, not a "follow system" third state.
class ThemeController extends ChangeNotifier {
  ThemeController({bool isDark = false}) : _isDark = isDark;

  static const String _prefsKey = 'theme_is_dark';

  bool _isDark;
  bool get isDark => _isDark;
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  /// Awaited before the brightness changes. The widget that animates the flip
  /// (`ThemeTransitionHost`) uses it to freeze a picture of the old look first.
  Future<void> Function()? beforeFlip;

  /// Reads the saved choice. Falls back to the platform brightness the very
  /// first time the app runs, so a phone already in dark mode opens dark.
  static Future<ThemeController> load() async {
    bool initial =
        PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    try {
      final prefs = await SharedPreferences.getInstance();
      initial = prefs.getBool(_prefsKey) ?? initial;
    } catch (e) {
      debugPrint('[Theme] Could not read saved brightness (non-fatal): $e');
    }
    return ThemeController(isDark: initial);
  }

  Future<void> setDark(bool value) async {
    if (_isDark == value) return;
    final freeze = beforeFlip;
    if (freeze != null) {
      await freeze();
      // A second tap while the picture was being taken asked for the same flip.
      if (_isDark == value) return;
    }
    _isDark = value;
    // Set here as well as by the app root so nothing reads the old palette
    // between the flip and the next build.
    AppColors.isDark = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (e) {
      debugPrint('[Theme] Could not save brightness (non-fatal): $e');
    }
  }

  Future<void> toggle() => setDark(!_isDark);
}

/// Makes the [ThemeController] reachable from any screen. Dependents rebuild
/// whenever the controller notifies.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope?.notifier != null, 'No ThemeScope above this widget');
    return scope!.notifier!;
  }
}
