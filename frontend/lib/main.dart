import 'package:flutter/material.dart';
import 'app_widget.dart';
import 'core/theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The tile cache is warmed by the boot screen, which reports its progress;
  // only the saved brightness has to be known before the first frame so the
  // app never flashes the wrong theme.
  final theme = await ThemeController.load();
  runApp(GatiSaarthApp(theme: theme));
}
