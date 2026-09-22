import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/constants/dr_constants.dart';

void main() {
  test('Phase B preview is labeled 4.1', () {
    expect(AppConstants.appVersion, '4.1.0');
    expect(AppConstants.appBuild, '41');
  });

  test('the version shown in the app is the one in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*([\w.]+)\+(\d+)\s*$', multiLine: true)
            .firstMatch(pubspec)!;
    expect(AppConstants.appVersion, match.group(1));
    expect(AppConstants.appBuild, match.group(2));
  });
}
