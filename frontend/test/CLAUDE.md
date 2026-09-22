# Test notes

Loaded when working under `frontend/test/`. Run with `cd frontend && flutter test` (headless, no device needed; real-screen widget tests run at 320/360/411 dp). Widget tests must call `loadAppFonts()` (`test/support/load_fonts.dart`) — otherwise Flutter's test font (every glyph a full-width square) creates false overflow failures.

Widget-test rules learned the hard way (helpers in `test/support/`: `app_harness.dart`, `fake_map_packs.dart`):
- **Never `pumpAndSettle` or `await` a real `Future.delayed`/`settle()` inside `testWidgets`.** Maps, spinners and the sync capsule never settle, and real timers do not run on the fake clock. Use `frames(tester, count:, ms:)`. Real file I/O also does not advance under the fake clock: use sync file calls in fakes, or `tester.runAsync`.
- A screen that mounts the vector map (`vector_map_tiles`) starts a 3 s cache-maintenance `Future.delayed` and needs `mockPathProvider()`; end the test with `pumpWidget(const SizedBox.shrink())` then `pump(5 s)` or the framework reports a pending timer.
- `scrollUntilVisible` only builds a row; a row under the tab bar still needs `ensureVisible` before a tap.
- Assert on `AppColors` after a `ThemeController.toggle()` to catch cached-colour bugs; reset `AppColors.isDark = false` in `tearDown`.
- A test that batches sensor adds and drains them afterwards lets its fake clock run seconds ahead of the samples. Drain per frame.
- Known failures that predate the map work: 7 tests in `test/screens_widget_test.dart` assert stale copy (e.g. "Nominal GNSS lock").
