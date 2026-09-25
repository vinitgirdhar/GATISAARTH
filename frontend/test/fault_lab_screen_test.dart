import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/fault_injection.dart';
import 'package:gatisaarth/core/nav/benchmark/fault_lab.dart';
import 'package:gatisaarth/core/theme/app_theme.dart';
import 'package:gatisaarth/features/fault_lab/data/fault_lab_backend.dart';
import 'package:gatisaarth/features/fault_lab/presentation/fault_lab_screen.dart';

import 'support/load_fonts.dart';

const _reference = FaultLabSource(
  title: 'Simulated reference drive',
  subtitle: 'Bundled, identical on every phone. Simulated sensors.',
  simulated: true,
  asset: 'assets/benchmarks/reference_city_drive.jsonl',
);

const _recorded = FaultLabSource(
  title: 'morning-commute.jsonl',
  subtitle: 'Recorded on this phone',
  simulated: false,
  path: '/data/drives/morning-commute.jsonl',
);

FaultLabResult _detectedResult() => const FaultLabResult(
      injected: 'GNSS position offset +120 m for 20s at t=30s',
      detected: true,
      detectionLatencyS: 0.5,
      mechanism: 'GNSS measurement rejected (impossibleJump)',
      action: 'GNSS measurement rejected, dead reckoning maintained',
      maxErrorM: 8,
      endErrorM: 3,
      keptLeading: true,
    );

FaultLabResult _notDetectedResult() => const FaultLabResult(
      injected: 'Gyro bias +0.50 deg/s for 20s at t=30s',
      detected: false,
      detectionLatencyS: null,
      mechanism: 'Not detected',
      action: 'Not detected - position was pulled 14 m',
      maxErrorM: 14,
      endErrorM: 11,
      keptLeading: true,
    );

class _FakeBackend implements FaultLabBackend {
  FaultLabSource? ranSource;
  FaultSpec? ranSpec;
  bool fail = false;

  @override
  Future<List<FaultLabSource>> sources() async => [_reference, _recorded];

  @override
  Future<FaultLabResult> run(FaultLabSource source, FaultSpec spec) async {
    ranSource = source;
    ranSpec = spec;
    if (fail) throw const FormatException('no readable drive records');
    return spec.kind == FaultKind.gyroBias
        ? _notDetectedResult()
        : _detectedResult();
  }

  @override
  Future<List<FaultLabResult>> runAll(
    FaultLabSource source, {
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(1.0);
    return [for (final _ in kFaultPresets) _detectedResult()];
  }
}

Widget _screen(FaultLabBackend backend) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: FaultLabScreen(backend: backend),
    );

void _size(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('lists the bundled drive and offers every fault preset',
      (tester) async {
    _size(tester, 360, 2400);
    await tester.pumpWidget(_screen(_FakeBackend()));
    await tester.pumpAndSettle();
    expect(find.text('Simulated reference drive'), findsOneWidget);
    for (final preset in kFaultPresets) {
      expect(find.text(preset.label), findsOneWidget);
    }
  });

  testWidgets('running a detected fault shows the mechanism and action',
      (tester) async {
    _size(tester, 360, 2400);
    final backend = _FakeBackend();
    await tester.pumpWidget(_screen(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(backend.ranSource, _reference);
    expect(backend.ranSpec!.kind, kFaultPresets.first.spec.kind);
    expect(find.textContaining('GNSS measurement rejected'), findsWidgets);
    expect(find.textContaining('dead reckoning maintained'), findsOneWidget);
  });

  testWidgets('an undetected fault is reported honestly, not papered over',
      (tester) async {
    _size(tester, 360, 2400);
    final backend = _FakeBackend();
    await tester.pumpWidget(_screen(backend));
    await tester.pumpAndSettle();

    final gyroPreset =
        kFaultPresets.firstWhere((p) => p.spec.kind == FaultKind.gyroBias);
    await tester.tap(find.text(gyroPreset.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(find.text('No'), findsOneWidget);
    expect(find.textContaining('Not detected'), findsWidgets);
  });

  testWidgets('run all faults shows a table with one row per preset',
      (tester) async {
    _size(tester, 360, 2400);
    final backend = _FakeBackend();
    await tester.pumpWidget(_screen(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run all faults'));
    await tester.pumpAndSettle();

    expect(find.text('ALL FAULTS'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
    // One "Yes" per preset (the fake backend reports every fault detected).
    expect(find.text('Yes'), findsNWidgets(kFaultPresets.length));
  });

  testWidgets('a log that cannot be read is reported, not shown as a result',
      (tester) async {
    _size(tester, 360, 2400);
    final backend = _FakeBackend()..fail = true;
    await tester.pumpWidget(_screen(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not run the lab'), findsOneWidget);
  });
}
