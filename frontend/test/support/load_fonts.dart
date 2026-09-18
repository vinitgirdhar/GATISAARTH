import 'package:flutter/services.dart';

/// Widget tests render text in the square "Ahem" font by default, which makes
/// every string ~2x wider than on a phone and produces false overflow
/// failures. Loading the app's real font makes layout match the device.
Future<void> loadAppFonts() async {
  final loader = FontLoader('.SF Pro Text')
    ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
  await loader.load();
}
