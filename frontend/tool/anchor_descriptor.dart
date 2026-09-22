import 'dart:io';

import 'package:gatisaarth/core/nav/anchors/visual_landmark_matcher.dart';

/// Builds the exact on-device visual descriptor from a field-survey photo.
/// The input is read locally and never uploaded or retained by this tool.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/anchor_descriptor.dart <photo>');
    exitCode = 64;
    return;
  }
  final photo = File(args.single);
  if (!await photo.exists()) {
    stderr.writeln('Photo not found: ${photo.path}');
    exitCode = 66;
    return;
  }
  final descriptor = VisualLandmarkMatcher.describe(await photo.readAsBytes());
  if (descriptor == null) {
    stderr.writeln('Photo is too large, unreadable, or lacks visual texture.');
    exitCode = 65;
    return;
  }
  stdout.writeln(descriptor);
}
