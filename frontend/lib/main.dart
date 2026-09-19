import 'dart:async';

import 'package:flutter/material.dart';
import 'app_widget.dart';
import 'core/platform/maps/offline_tile_provider.dart';
import 'core/theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(BundledOfflineTileProvider.initCache());
  final theme = await ThemeController.load();
  runApp(GatiSaarthApp(theme: theme));
}
