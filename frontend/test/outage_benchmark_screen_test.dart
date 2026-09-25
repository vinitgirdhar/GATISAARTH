import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/benchmark/outage_report.dart';
import 'package:gatisaarth/core/theme/app_theme.dart';
import 'package:gatisaarth/features/benchmark/data/benchmark_backend.dart';
import 'package:gatisaarth/features/benchmark/data/benchmark_report_exporter.dart';
import 'package:gatisaarth/features/benchmark/presentation/outage_benchmark_screen.dart';

import 'support/load_fonts.dart';

const _reference = BenchmarkSource(
  title: 'Reference city drive',
  subtitle: 'Bundled, identical on every phone. Simulated sensors.',
  simulated: true,
  asset: 'assets/benchmarks/reference_city_drive.jsonl',
);

const _recorded = BenchmarkSource(
  title: 'morning-commute.jsonl',
  subtitle: 'Recorded on this phone, 3.1 MB',
  simulated: false,
  path: '/data/drives/morning-commute.jsonl',
);

OutageReport _report() => OutageReport(
      source: 'Reference city drive (simulated)',
      profile: const LogProfile(
        durationS: 320,
        imuHz: 50,
        gnssHz: 1,
        gnssFixes: 316,
        truthFixes: 316,
        medianTruthAccuracyM: 5,
        hasMagnetometer: false,
        hasBarometer: false,
        deviceModel: 'Pixel 9',
      ),
      config: const OutageBenchmarkConfig(),
      durations: [
        DurationResult.of(30, const [
          OutageSample(
              startUs: 0,
              holdErrorM: 190,
              engineErrorM: 12,
              engineSigmaM: 9,
              distanceM: 350),
          OutageSample(
              startUs: 1,
              holdErrorM: 210,
              engineErrorM: 20,
              engineSigmaM: 5,
              distanceM: 380),
        ]),
        DurationResult.of(60, const [
          OutageSample(
              startUs: 0,
              holdErrorM: 500,
              engineErrorM: 25,
              engineSigmaM: 12,
              distanceM: 700),
        ]),
      ],
      windowsTried: 3,
      skipped: const {SkipReason.tooLittleTravel: 1},
      coreLedFromS: 77,
      runtimeMs: 1200,
    );

class _FakeBackend implements BenchmarkBackend {
  _FakeBackend({this.fail = false});

  final bool fail;
  BenchmarkSource? ran;
  BenchmarkSource? shared;
  BenchmarkSource? deleted;
  BenchmarkSource? evidenceSource;
  BenchmarkSource? reportSource;
  ReportFormat? reportFormat;

  @override
  Future<List<BenchmarkSource>> sources() async =>
      [_reference, if (deleted == null) _recorded];

  @override
  Future<void> share(BenchmarkSource source) async => shared = source;

  @override
  Future<bool> delete(BenchmarkSource source) async {
    deleted = source;
    return true;
  }

  @override
  Future<void> shareEvidence(
    BenchmarkSource source,
    OutageReport report,
  ) async {
    evidenceSource = source;
  }

  @override
  Future<void> shareReport(
    BenchmarkSource source,
    OutageReport report,
    ReportFormat format,
  ) async {
    reportSource = source;
    reportFormat = format;
  }

  @override
  Future<OutageReport> run(
    BenchmarkSource source, {
    void Function(double progress)? onProgress,
  }) async {
    ran = source;
    onProgress?.call(0.5);
    if (fail) throw const FormatException('no readable drive records');
    return _report();
  }
}

Widget _screen(BenchmarkBackend backend) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: OutageBenchmarkScreen(backend: backend),
    );

void _size(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('lists the bundled drive and this phone\'s recordings',
      (tester) async {
    _size(tester, 360, 2400);
    await tester.pumpWidget(_screen(_FakeBackend()));
    await tester.pumpAndSettle();
    expect(find.text('Reference city drive'), findsOneWidget);
    expect(find.text('morning-commute.jsonl'), findsOneWidget);
  });

  testWidgets('running a drive shows both methods and the honest caveats',
      (tester) async {
    _size(tester, 360, 2400);
    final backend = _FakeBackend();
    await tester.pumpWidget(_screen(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reference city drive'));
    await tester.pumpAndSettle();

    expect(backend.ran, _reference);
    expect(find.text('AFTER 30 s WITHOUT GNSS'), findsOneWidget);
    expect(find.text('AFTER 60 s WITHOUT GNSS'), findsOneWidget);
    expect(find.text('Hold last velocity'), findsNWidgets(2));
    expect(find.text('Navigation core'), findsNWidgets(2));
    // Median of the two 30 s outages for each method.
    expect(find.text('200 m'), findsOneWidget);
    expect(find.text('16 m'), findsOneWidget);
    expect(find.textContaining('Core closer in 2 of 2'), findsOneWidget);
    expect(find.textContaining('Simulated sensors'), findsWidgets);
    expect(find.textContaining('Pixel 9'), findsOneWidget);
    expect(find.textContaining('vehicle barely moved'), findsOneWidget);
    expect(find.text('Copy report'), findsOneWidget);
  });

  testWidgets('sharing asks first, and only then hands the drive to the phone',
      (tester) async {
    _size(tester, 360, 2400);
    final backend = _FakeBackend();
    await tester.pumpWidget(_screen(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Share drive'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Share it only with someone you trust'),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.shared, isNull);

    await tester.tap(find.byTooltip('Share drive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(backend.shared, _recorded);
    // Sharing never runs the benchmark by accident.
    expect(backend.ran, isNull);
  });

  testWidgets('deleting asks first and removes the drive from the list',
      (tester) async {
    _size(tester, 360, 2400);
    final backend = _FakeBackend();
    await tester.pumpWidget(_screen(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete drive'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this drive?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(backend.deleted, _recorded);
    expect(find.text('morning-commute.jsonl'), findsNothing);
    expect(find.text('Reference city drive'), findsOneWidget);
  });

  testWidgets('the bundled drive has no share or delete', (tester) async {
    _size(tester, 360, 2400);
    await tester.pumpWidget(_screen(_FakeBackend()));
    await tester.pumpAndSettle();
    // One of each: the recording's, not the bundled drive's.
    expect(find.byTooltip('Share drive'), findsOneWidget);
    expect(find.byTooltip('Delete drive'), findsOneWidget);
  });

  testWidgets('a recorded drive is not labelled simulated', (tester) async {
    _size(tester, 360, 2400);
    await tester.pumpWidget(_screen(_FakeBackend()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('morning-commute.jsonl'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not a field measurement'), findsNothing);
    expect(find.text('Share signed evidence'), findsOneWidget);
  });

  testWidgets('shares a signed result rather than only copying prose',
      (tester) async {
    _size(tester, 360, 2400);
    final backend = _FakeBackend();
    await tester.pumpWidget(_screen(backend));
    await tester.pumpAndSettle();
    await tester.tap(find.text('morning-commute.jsonl'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share signed evidence'));
    await tester.pumpAndSettle();

    expect(backend.evidenceSource, _recorded);
  });

  testWidgets('the report section shows a PASS/FAIL chip and exports JSON/CSV/PDF',
      (tester) async {
    _size(tester, 360, 2400);
    final backend = _FakeBackend();
    await tester.pumpWidget(_screen(backend));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reference city drive'));
    await tester.pumpAndSettle();

    expect(find.text('REPORT'), findsOneWidget);
    expect(find.text('PASS'), findsOneWidget);
    expect(find.text('Export report'), findsOneWidget);

    await tester.tap(find.text('Export report'));
    await tester.pumpAndSettle();
    expect(find.text('CSV'), findsOneWidget);

    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();

    expect(backend.reportSource, _reference);
    expect(backend.reportFormat, ReportFormat.csv);
  });

  testWidgets('a log that cannot be read is reported, not shown as a result',
      (tester) async {
    _size(tester, 360, 2400);
    await tester.pumpWidget(_screen(_FakeBackend(fail: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reference city drive'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not run the benchmark'), findsOneWidget);
    expect(find.textContaining('WITHOUT GNSS'), findsNothing);
  });

  for (final size in const [Size(320, 568), Size(411, 915)]) {
    testWidgets(
        'results lay out cleanly on ${size.width.toInt()}x${size.height.toInt()} dp',
        (tester) async {
      _size(tester, size.width, size.height);
      await tester.pumpWidget(_screen(_FakeBackend()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reference city drive'));
      await tester.pumpAndSettle();

      // Scroll the whole page; any overflow is thrown as a test failure.
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 6; i++) {
        await tester.drag(list, const Offset(0, -400));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
