import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/platform/location/live_location_service.dart';
import '../../../core/platform/maps/offline_tile_provider.dart';
import '../../navigation_ui/presentation/controllers/live_session_controller.dart';

/// One step of start-up the progress bar reports on.
class BootStage {
  const BootStage({required this.label, required this.budget});

  /// Shown under the bar while this step is the one being waited on.
  final String label;

  /// How long this step may take before the sequence gives up on it and moves
  /// on. Start-up must never be able to hang: a phone with location switched
  /// off never resolves a fix, and the dashboard shows that state anyway.
  final Duration budget;
}

/// Drives the boot progress bar from real start-up work rather than a timer.
///
/// Each stage completes when the thing it describes has actually happened
/// (tile cache directory created, first IMU sample in, TFLite model loaded,
/// location permission/service resolved). Stages that exceed their budget are
/// abandoned — [progress] then still advances, but nothing claims they
/// succeeded; the dashboard reports the real state on arrival.
class BootSequence extends ChangeNotifier {
  BootSequence({required this.session, this.minimumDisplay = _minDisplay});

  static const Duration _minDisplay = Duration(milliseconds: 1400);
  static const Duration _poll = Duration(milliseconds: 80);

  static const List<BootStage> stages = [
    BootStage(
      label: 'PREPARING OFFLINE MAPS',
      budget: Duration(seconds: 4),
    ),
    BootStage(
      label: 'INITIALIZING SENSORS',
      budget: Duration(seconds: 4),
    ),
    BootStage(
      label: 'LOADING ON-DEVICE AI',
      budget: Duration(seconds: 6),
    ),
    BootStage(
      label: 'ACQUIRING SATELLITES',
      budget: Duration(seconds: 5),
    ),
  ];

  final LiveSessionController session;

  /// Floor on how long the sequence stays on screen, so a warm start does not
  /// flash the branding for two frames.
  final Duration minimumDisplay;

  int _index = 0;
  bool _finished = false;
  bool _disposed = false;

  int get stageIndex => _index;
  bool get isFinished => _finished;
  String get label =>
      _finished ? 'READY' : stages[_index].label;

  /// 0..1 — completed stages over total. Never runs ahead of real work.
  double get progress =>
      _finished ? 1 : _index / stages.length;

  Future<void> run() async {
    final startedAt = DateTime.now();

    // Stage 0 is the only step this screen owns; the rest are started by the
    // app root and merely observed here.
    await _await(0, () async {
      await BundledOfflineTileProvider.initCache();
      return true;
    });
    await _observe(1, () => session.isSensorLive);
    await _observe(2, () => session.isModelLoaded);
    await _observe(
      3,
      () => session.location.status != LocationStatus.initializing,
    );

    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < minimumDisplay) {
      await Future<void>.delayed(minimumDisplay - elapsed);
    }
    if (_disposed) return;
    _finished = true;
    notifyListeners();
  }

  Future<void> _await(int index, Future<bool> Function() work) async {
    _enter(index);
    try {
      await work().timeout(stages[index].budget);
    } catch (e) {
      debugPrint('[Boot] ${stages[index].label} did not finish: $e');
    }
  }

  /// Polls [done] until it is true or the stage runs out of budget. The budget
  /// is counted in polls rather than against the wall clock so the sequence
  /// behaves identically under `flutter test`'s fake async clock.
  Future<void> _observe(int index, bool Function() done) async {
    _enter(index);
    final maxPolls = stages[index].budget.inMilliseconds ~/ _poll.inMilliseconds;
    for (var i = 0; i < maxPolls && !done(); i++) {
      await Future<void>.delayed(_poll);
      if (_disposed) return;
    }
    if (!done()) {
      debugPrint('[Boot] ${stages[index].label} timed out, continuing');
    }
  }

  void _enter(int index) {
    if (_disposed) return;
    _index = index;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
