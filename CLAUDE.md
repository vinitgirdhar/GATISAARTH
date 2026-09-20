# GatiSaarth — Dead Reckoning Navigation System

Monorepo (git repo; remote `origin` is the private GitHub repo `GATISAARTHI`). This file's folder is the repo root.

## What's here

- `frontend/` — Flutter app (Dart). The thing you run in Android Studio / emulator. Has its own `android/` gradle project (standard Flutter scaffold, Gradle 9.3.1 / AGP 9.1.0 / Kotlin 2.4.0, Java 17).
- `backend/` — dual backend: Python FastAPI (`backend/app`, port 8000) + TypeScript WS/EKF engine (`backend/src`, port 8080). Optional for running the app — see below.
- `cpp-core/` — C++17 SINS/UKF engine. **Not wired into the Flutter app yet** (no `dart:ffi`/`DynamicLibrary` calls in `frontend/lib` as of this writing, despite the README architecture diagram showing it). Only matters if you're building that integration.
- `ml/` — PyTorch training pipeline (the PyTorch model source is a stub here; the ONNX files are the source of truth). **The speed model is real and loads**: `frontend/assets/models/speed_estimator.tflite` (float32, 351 KB, built-in ops only) is generated from `speed_estimator.onnx` by `ml/src/export/onnx_to_tflite.py`, which rebuilds the net in TF ops (onnx2tf mis-converts its BiGRU) and checks parity against onnxruntime (max diff 6.7e-06). It is float32, not INT8, on purpose. **The `vibration_classifier_int8.tflite` and `motion_quality_int8.tflite` files are still ~130-byte Git LFS pointer stubs** and the app does not load them. The model runs on IMU motion whether or not GNSS is live (so the AI panel has data), but it is **advisory**: in the fallback path (core not leading) it may only *stop* the marker through its rule-based stillness gate, it never sets the speed, and the panel says so. The `-309 %` outage figure in `model_metadata.json` / `ml/evaluation/metrics/08_*.json` is an artifact of a broken baseline (see Outage benchmark below) - neither "the model is bad" nor "the model is good" is established; that needs real recorded drives.
- `maps/`, `simulation/`, `datasets/`, `docs/`, `config/` — support data/tooling, not needed to run the app.

## Running the Flutter app (primary target)

No native FFI dependency currently, so `cpp-core` does NOT need to be built first. Just:

```
cd frontend
flutter pub get
flutter run          # picks whatever device/emulator is active
```

First run auto-generates `android/local.properties`, `.dart_tool/`, `.flutter-plugins*` — these are gitignored and expected to be absent on a fresh checkout, not missing/broken files.

### Backend is optional
`frontend/lib/core/platform/network/backend_telemetry_client.dart` tries a list of candidate URLs (`127.0.0.1:8000`, `10.0.2.2:8000` for Android emulator, a LAN IP) and fails gracefully if none respond. Dead reckoning, map rendering, and sensor fusion all work standalone without the backend running. Only start `backend/` if you're testing the telemetry upload feature.

## Navigation core (`frontend/lib/core/nav/`, added 2026-09-19)

A pure-Dart, Flutter-free navigation engine, and **it now drives the app**.

`LiveSessionController` feeds it every sensor frame and every fix, and once it
is healthy its solution replaces the heuristic pipeline's: position, speed,
heading and a covariance-derived uncertainty. `isEngineLeading` is the switch,
and every condition in it is a reason the core could be *worse* than the
heuristic:

* the mount transform has not converged (it needs ~40 s of accelerating and
  braking on a straight road before it knows which way the phone points);
* integrity is INVALID or the filter failed numerically;
* the minimum sensor set is gone.

Any of those and it hands straight back. **The app can never be worse than it
was before the core existed** — `test/engine_handover_test.dart` pins that.

Two clock traps live here, both found the hard way:

* `sensors_plus` timestamps are device uptime; `DateTime.now()` is epoch. The
  core integrates against one timeline, so a fix is stamped with the newest IMU
  timestamp **plus the wall time elapsed since it**. Stamping it with the IMU
  timestamp alone collapses the spacing of queued fixes to milliseconds and the
  GNSS gate rejects them all as teleports.
* A test that batches sensor adds and drains them afterwards lets its fake
  clock run seconds ahead of the samples. Drain per frame.

Read `docs/architecture/EVOLUTION_PLAN.md` before touching it; it holds the
audit, the gap analysis against the 84-point spec, the EKF state definition,
the measured drift benchmark and the P0-P4 migration plan with per-step status.

- `nav_config.dart` — every tunable in one versioned place. Nothing under
  `core/nav/` may hard-code a threshold; add it here instead.
- `math/nav_math.dart` — NED frame, WGS84 geodesy, quaternion helpers.
  **Always rotate via `NavMath.rotateBodyToNav` / `rotateNavToBody`.**
  `vector_math`'s own `Quaternion.rotated()` applies the *opposite* sense to the
  matrix that same quaternion's `asRotationMatrix()` produces; a guard test in
  `test/nav/math_test.dart` pins that so a package upgrade cannot silently flip
  the heading sign.
- `math/matrix.dart` — minimal NxN dense matrix (Gauss-Jordan inverse returns
  `null` rather than NaN on a singular matrix).
- `sensors/` — `SensorSample` (typed, sequenced, with its own event timestamp)
  and `TimeSync`, a bounded k-way merge that orders several sensor streams,
  drops duplicates, counts real drops and measures effective Hz. Replaces the
  old positional `List<double>` where gyro/mag were latched off the accel
  callback up to 66 ms stale.
- `ins/` + `ekf/navigation_filter.dart` — strapdown mechanization plus a
  15-state error-state EKF (position, velocity, attitude, accel bias, gyro
  bias) with Joseph-form updates, chi-square NIS gating, and covariance
  inflation after a rejection streak. Updates available: GNSS position/velocity,
  ZUPT, ZARU, NHC, forward speed, barometric altitude, heading, magnetometer.
- `gnss/gnss_quality.dart` — quality score, outlier rejection (teleport,
  impossible acceleration, speed-aware heading-rate limit, null island, mocked
  fixes) and an integrity monitor that says "GNSS integrity anomaly detected",
  never "spoofing".
- `motion/motion_classifier.dart` — vehicle-state classification, ZUPT gating
  with enter/exit hysteresis, NHC applicability, two-wheeler lean.
- `calibration/` — gyro bias, accel bias/scale and magnetometer hard/soft iron
  by ellipsoid fit, with noise statistics, persistence and staleness.
- `alignment/mount_alignment.dart` — the phone-to-vehicle transform **including
  yaw**, regressed from the GNSS speed derivative during a calibration drive.
- `navigation_engine.dart` — assembles all of the above and emits
  `NavigationSnapshot` at 10 Hz, with logged mode transitions.
- `map/` — road graph with a uniform-grid index and bounded routing, plus an
  HMM (Newson–Krumm) matcher that keeps multiple hypotheses and **refuses to
  snap** unless one road clears a threshold, beats the runner-up by a margin,
  and sits within the filter's own uncertainty. It feeds only *heading* back
  into the filter; the map never pushes position into the state.
- `sensors/barometer.dart` — relative height, ramps and car-park floors, with
  an absolute altitude that only exists while a GNSS anchor is fresh and a
  sigma that grows ~9 m/hour after it goes stale.
- `sensors/sensor_fault_detector.dart` — frozen, stalled, out-of-range, noisy
  and magnetically-disturbed sensors. Isolates the faulty one; only losing the
  accelerometer or gyroscope stops navigation.
- `replay/` — JSONL drive recorder and a **bit-exact** deterministic replay
  engine. Replaying a log reproduces the live run exactly, which is what makes
  a drift regression attributable to a code change.
- `benchmark/` — **the outage benchmark, and the only accuracy yardstick that
  works on real phones.** `OutageBenchmark.run(records)` replays any drive log
  with GNSS withheld from many start times and scores the core and a
  hold-last-velocity baseline against the *withheld fixes* (truth = the phone's
  own GNSS, so no reference receiver and any phone works). Scores the core only
  while `NavigationSnapshot.canLeadPosition` (the app's own hand-over test)
  holds; reports the truth's noise floor, the phone's IMU/GNSS rates and sensors,
  and every window it skipped and why. On device: Profile > Outage Benchmark
  (background isolate, reference drive or any recording). Headless:
  `flutter test test/nav/reference_drive_asset_test.dart` prints the report.
  Bundled reference drive is **simulated** (regenerate with
  `UPDATE_REFERENCE_DRIVE=1`); on it the core beats hold-velocity by a wide
  margin through bends and stops (30 s: 12 m vs 189 m) but is weak at 120 s
  (281 m median, its own 3-sigma covers the error in 3 of 6) - see
  `docs/architecture/EVOLUTION_PLAN.md` P2. **Never quote simulated results as
  field accuracy; record real drives (Sensors > Navigation core) and score them.**

**Measured limits to keep quoting honestly:** at rest, accelerometer bias and
tilt are not separately observable (a 0.3 m/s² bias is absorbed as 1.744° of
pitch), so ZUPT stops velocity drift but does *not* identify the bias. NHC alone
cannot observe yaw — only NHC together with an independent velocity reference
can (measured: 0.68° vs 34° heading sigma). A constant acceleration has zero
variance, so the stillness gate must test horizontal specific force, not just
variance. Gravity may only be estimated while the vehicle is *not*
accelerating.

**Drift, simulated only:** 1.75 % at 60 s, 5.64 % at 300 s
(`flutter test test/nav/drift_benchmark_test.dart` prints the table). That is a
bound on the estimator under modelled sensor error — **not** a field
measurement, and never to be quoted as measured accuracy.

**Cost:** 20 µs per sensor frame, 74 µs peak — about 0.1 % of a core at 50 Hz,
so the C++ port stays unjustified until profiling says otherwise.

**Measured ablation** (`flutter test test/nav/ablation_test.dart`, 60 s outage,
5 seeded drives): raw inertial 35.1 % drift, + GNSS velocity 15.4 %,
**+ non-holonomic constraint 1.4 %**, and nothing after that moves the number.
NHC is the dominant lever by 11×. ZUPT/ZARU shows no measurable benefit on
these cruising profiles — do not claim it does until a stop-and-go profile says
otherwise.

**No road graph ships** (`maps/processed_graphs/road_edges.json` is
`{"edges": []}`), so map matching reports unavailable on a stock build. Build
one with `python -m maps.tools.graph_builder overpass.json out.json`;
`test/nav/graph_builder_contract_test.dart` pins the Python→Dart format.

Tests live in `frontend/test/nav/` plus `test/nav_core_integration_test.dart`
(303 of the suite's 416).

## Frontend architecture (as of 2026-09-18)

- **One live pipeline.** `frontend/lib/features/navigation_ui/presentation/controllers/live_session_controller.dart` owns sensors, GNSS, dead reckoning, uncertainty and telemetry. It is provided app-wide by `live_session_scope.dart` and started/paused/resumed from `lib/app_widget.dart` (pauses sensors + GPS when the app is backgrounded). `dashboard_screen.dart` and `active_nav_screen.dart` are thin views — never add sensor subscriptions or timers to a screen. Listeners are notified at most 10 Hz.
- **Start-up.** `features/boot/presentation/boot_screen.dart` is only a 1.4 s branded animation that fades into the dashboard (there is no `BootSequence`; an earlier version of this note described one that does not exist in the code). What the app is actually waiting for after that is shown by the **sync capsule**: `controllers/sync_status.dart` derives `SyncStatus` from real state only (sensors delivering, motion model initialised, GNSS status, reacquiring) and `widgets/sync_capsule.dart` slides it in from the top ("Syncing · Finding satellites", 3-segment progress, "Synced" for ~1.6 s, then gone). It waits 300 ms before appearing (no flash), says "Still searching · try open sky" after 40 s, never takes taps, and is hidden for problems only the user can fix (location off / permission), which have their own banner. The Home confidence ring spins instead of sitting empty while syncing. **Tests must not `pumpAndSettle` on the dashboard** while sensors or a fix are pending: loading spinners never settle - pump real frames in bounded steps.
- **Haptics: one policy, three events.** `core/platform/hardware/haptics.dart` is the only code that may vibrate the phone. It fires for `outageStarted` (GNSS signal lost while the driver was using the app, or the tunnel test; double pulse, 45 s cool-down, silent while recording because a vibrating phone shakes its own IMU trace and the alert lands exactly where DR is measured, silent for the 20 s after resuming from the background and for a location switch the user turned off), `recordingStarted` (one 60 ms tick) and `recordingStopped` (two ticks). Deliberately **not** haptic: bump/pothole detection (visual ticker only), button taps (`PressableScale` no longer calls `HapticFeedback`; tooltips have `enableFeedback: false`), GNSS recovery, the Urban canyon / Reset demo buttons. Profile > "Haptic alerts" switch turns everything off and is remembered (`haptics_enabled`). Verified on a device with `adb shell dumpsys vibrator_manager` (lists every vibration per package with its reason); `performHapticFeedback(constant=4)` entries from `com.gatisaarth.app` mean something is calling `HapticFeedback.selectionClick()` again.
- **Home tab test hooks are inert on a phone.** The invisible (opacity 0.001) "Tunnel test" / "Two-wheeler" / "Start fullscreen navigation" buttons at the end of the Home list are hit-testable and exposed to screen readers only under `flutter test` (`FLUTTER_TEST` env var).
- **Light/dark:** `core/theme/theme_controller.dart` owns the choice (persisted in `SharedPreferences` under `theme_is_dark`, first launch follows the platform). Surface/label tokens on `AppColors` are getters that resolve against the app-wide `AppColors.isDark` flag. `core/widgets/theme_transition.dart` (`ThemeTransitionHost`) performs the flip: it freezes the current frame (`toImageSync`), sets the flag, marks **every element dirty** (so `const` subtrees that read the palette follow too, without remounting the app, which would lose the route stack) and wipes the frozen frame away top to bottom (620 ms, feathered edge). `MaterialApp.themeAnimationDuration` is zero so its own colour lerp does not fight it. **Never cache a palette getter** in a `static final`, a field initialiser or a top-level `final`: marking elements dirty re-runs `build`, not initialisers (that is how the map chips got white text on a white pill in light mode, and how the Privacy tile stayed near-black on near-black in dark). Accent/status colours are the same in both brightnesses. Card shadows collapse to nothing in dark mode (cards separate by surface colour, iOS-style). Material 3 ignores `ThemeData.dividerColor`; `dividerTheme` is set explicitly. The switch is Profile > Appearance (`BrightnessToggle` in `dashboard_header.dart` is the icon variant).
- **Overscroll:** `core/widgets/soft_overscroll.dart` (`AppScrollBehavior`) reproduces Android's stretch effect at `kStretchStrength = 0.35` of stock (asked for: half, then 30 % less again). `MaterialApp.scrollBehavior` applies it everywhere.
- **Screen changes:** the dashboard tabs cross-fade (`core/widgets/fade_indexed_stack.dart`, each page keeps its state and its `TickerMode`).
- **GNSS state machine:** `core/platform/location/live_location_service.dart` (`LocationStatus`: initializing / serviceOff / permissionDenied / permissionBlocked / searching / live / stale). "Live" only ever means a real fix arrived within 6 s — a cached last-known position never counts.
- **Confidence is modelled, not hard-coded:** `features/navigation_engine/domain/uncertainty_model.dart` (live = GNSS accuracy; outage = accuracy at loss + 5 % of distance + 0.15 m/s). `null` uncertainty means "no fix yet" — the UI shows `--`, never a made-up number.
- **Dead-reckoning outage = any non-live state after a real fix** (stale, location off, permission revoked, re-searching after a resume). The outage is noticed ~6 s late, so the tracker is backdated by the time since the last fix and, for gaps ≤ 15 s, that travel is extrapolated at the last GNSS speed; longer gaps only widen the margin.
- **Speed-model input contract** (`_feedModel`): 10 Hz (not the 50 Hz sensor rate), raw accelerometer *including gravity* (levelled vehicle-frame accel + 9.81 on z), pitch/roll 0 — that is what `assets/models/model_metadata.json`'s scaler was fit on. Feeding gravity-free 50 Hz data puts inputs ~75σ off-distribution. AI confidence/latency show `--` until the TFLite model has really run (`hasModelInference`); the heuristic fallback is never presented as AI.
- **Known limits, don't paper over them:** no yaw alignment (phone→vehicle forward axis is unknown) and heading assumes a flat phone (`atan2(-mx, my)`), so DR direction is only trustworthy with the phone flat and top-forward; the variance-only stationary gate can mistake a smooth cruise for a stop (ZUPT is therefore delayed 3 s at speed); the shipped model's own benchmark (`ml/evaluation/metrics/08_gnss_outage_benchmark_results.json`) shows AI-speed DR *worse* than classical DR on its synthetic set, so never claim drift reduction from it.
- **Deliberately still demo data (labelled as such in the UI):** the satellite breakdown and NavIC weight panels, and the diagnostics screen. Real `GnssStatus` (Android platform channel) is not wired yet. Map-matching (HMM/OSM) does not exist; the old "Map match %" was removed rather than faked.

## Maps (rebuilt 2026-09-20)

The map is **OpenStreetMap vector data drawn on the phone**, not downloaded pictures: sharp at any zoom, street names, light and dark styles, and it works with no signal. The ~170 bundled raster PNG tiles (`assets/maps/tiles`, Delhi only, zoom 11-16, served by `offline_tile_provider.dart`) are still there as the last-resort layer under the vector maps.

- **Widget:** `features/navigation_ui/presentation/widgets/navigation_map.dart` (`NavigationMap`) is a `flutter_map` with one vector layer per installed archive (`basemap_layers.dart`; `BasemapCoverage` decides which archives a viewport needs and whether the cached/online raster must sit underneath). Used by the Map tab (`MapGestures.full`), fullscreen navigation (`zoomOnly`) and the Offline Maps preview (`none`).
- **Camera** (`map_follow.dart`, `map_controls.dart`, `vehicle_puck.dart`): follow modes free / north-up / heading-up (heading-up rotates the map by `-heading` and looks ahead of the puck), eased glides (`Ease`, `AngleEase`) with a 300 m teleport snap, speed-driven auto-zoom with hysteresis (injectable `clock`), `+`/`-` buttons, recentre. The accuracy ring is drawn in metres. Track: `controllers/track_trail.dart`, solid where a satellite fix backed the position and dashed red where it was dead-reckoned; a "Clear track" chip. The marker starts on the last remembered position and **jumps** (does not glide) to the first real fix, otherwise a restart 100 m from the old spot drew a phantom track (`_drawnOnReal` in `live_session_controller.dart`).
- **Archives** (`core/platform/maps/offline_catalog.dart`): PMTiles v3 vector archives cut from the Protomaps daily build (schema v4). `delhi-ncr` 37 MB z15 (bundled in the APK), `maharashtra-state` 79 MB z12 (whole state), and z15 city packs `mumbai` 26 MB, `pune` 17 MB, `nagpur` 5 MB, `nashik` 4 MB, `sambhajinagar` 3 MB. City packs are `detail` packs: drawn over the statewide overview from zoom 12 (`BasemapCoverage.detailFromZoom`), with no background layer so an empty tile stays transparent.
- **Where a pack lives** (`MainActivity.kt`, channel `com.gatisaarth.app/map_packs`, method `locate`; first hit wins): side-loaded `/sdcard/Android/data/com.gatisaarth.app/files/offline_maps/` (testing) → downloaded `<filesDir>/offline_maps/` → bundled. The bundled archive is stored uncompressed (`noCompress += ["pmtiles"]` in `android/app/build.gradle`) and read **in place** from the APK (`AssetManager.openFd` offset via `OffsetFileAt`), so there is no second copy on the phone. `OfflineMapService` finds and opens them; a broken file is reported (`problemWith`), never fatal.
- **Download and delete on the phone** (`MapDownloadService`, `PackInstaller`, `RegionExtractor`, `PmTilesWriter`, all pure Dart): cuts the region out of the newest Protomaps planet build (`build.protomaps.com/<date>.pmtiles`, ~138 GB) with HTTP range requests, which is what `pmtiles extract` does, so only the region's bytes cross the network. Writes `<id>.pmtiles.part`, verifies, then renames (the map never sees half a file); cancellable and retried. The output passes `pmtiles verify`. Measured from an emulator on a home link: Pune 17 MB in ~1.5 min, statewide 79 MB in ~4 min. Bundled Delhi cannot be deleted.
- **It asks first:** `MapDownloadPrompter` + `MainShellScreen._maybeOfferMaps`. The first position inside a known region whose maps are missing opens a bottom sheet ("Save maps for Pune & Pimpri-Chinchwad?", sizes, tick boxes, "Download 96 MB", "Not now", "Do not ask again"). Nothing downloads without a tap. "Not now" (also swiping it away) snoozes 3 days, "Do not ask again" is per region; never shown offline, while a download runs, or over another route. Profile > Offline Maps (`/offline-maps`) lists every region with Download / Delete, confirms downloads of 30 MB or more and checks connectivity first.
- **Size (measured 2026-09-20):** release APK with Delhi bundled = 77.1 MiB fat (arm64 + armeabi-v7a + x86_64; about 58 MB for one ABI, which is what an app bundle delivers). Every other region is on-demand: all seven maps together are ~171 MB on top of a ~40 MB app. A debug APK is ~172 MB and says nothing about what users get.
- **Gotchas:**
  * `vector_map_tiles` renders in isolates only in **release/profile**. A debug build draws tiles on the UI thread: blank rectangles for seconds after a zoom, dropped frames. Judge map smoothness on a release build.
  * Every style needs a **unique `theme.id` and a `revision`** (`BasemapStyle`): the renderer caches finished tiles on disk under the theme id/version and Protomaps' own themes all say `default`, so light tiles showed in dark mode. Bump `BasemapStyle.revision` when a style changes.
  * `vector_tile_renderer` 5.2.1 cannot parse Protomaps' label expressions (`format`, `is-supported-script`, `in` + `literal` + zoom filters), which meant **no street names**; `BasemapStyle.adapt` rewrites them, and `basemap_style_test.dart` asserts zero parser warnings.
  * `flutter_native_splash` is **not** a dev dependency any more: `pmtiles` pulls `archive` 3.x, which forced it down to 2.4.4, and that version fails the Android build (compiled against android-31). Regenerate the splash with `dart pub global activate flutter_native_splash` if it ever needs redoing.
  * The raster fallback (`offline_tile_provider.dart`, Stadia OSM Bright, cached) is only used outside installed regions. It still carries a **hard-coded default Stadia API key** (overridable by `--dart-define`): treat it as public and rotate it before the repo is shared.
  * A snackbar with an action never leaves by itself (`persist` defaults to true): pass `persist: false` for anything that goes stale.
  * Put the emulator in Pune with `adb emu geo fix 73.8567 18.5204` to see the download prompt; `adb shell cmd connectivity airplane-mode enable` proves the maps work offline.
- **Developer tool:** `tools/offline_maps/build_offline_maps.py` (+ README) cuts the same archives on a PC with the official `pmtiles` CLI, for bundling another region or side-loading a test phone. `.pmtiles` files under `frontend/assets/maps/packs/` are git-ignored.
- **Profile > GatiSaarth Navigation Engine** opens `EngineSpecScreen` (`features/about/`, route `/engine`): what the app is, how the pipeline works, specifications read from `NavConfig` defaults and the model's own metadata (so the numbers cannot drift from the code), maps installed, privacy, known limits, this phone. It states the same limits as this file and claims no field accuracy.

## Testing

`cd frontend && flutter test` — headless, no device/emulator needed (state machines, dead-reckoning maths, telemetry backoff, tile gate, the offline-map stack, and real-screen widget tests at 320/360/411 dp). Widget tests must call `loadAppFonts()` (`test/support/load_fonts.dart`) — otherwise Flutter's test font (every glyph a full-width square) creates false overflow failures.

Widget-test rules learned the hard way (helpers in `test/support/`: `app_harness.dart`, `fake_map_packs.dart`):
- **Never `pumpAndSettle` or `await` a real `Future.delayed`/`settle()` inside `testWidgets`.** Maps, spinners and the sync capsule never settle, and real timers do not run on the fake clock. Use `frames(tester, count:, ms:)`. Real file I/O also does not advance under the fake clock: use sync file calls in fakes, or `tester.runAsync`.
- A screen that mounts the vector map (`vector_map_tiles`) starts a 3 s cache-maintenance `Future.delayed` and needs `mockPathProvider()`; end the test with `pumpWidget(const SizedBox.shrink())` then `pump(5 s)` or the framework reports a pending timer.
- `scrollUntilVisible` only builds a row; a row under the tab bar still needs `ensureVisible` before a tap.
- Assert on `AppColors` after a `ThemeController.toggle()` to catch cached-colour bugs; reset `AppColors.isDark = false` in `tearDown`.
- Known failures that predate the map work: 7 tests in `test/screens_widget_test.dart` assert stale copy (e.g. "Nominal GNSS lock").

## Field test and data hand-over (any phone, car or two-wheeler)

- **Record:** Profile > pick Car/Two-wheeler (**saved across restarts; pick it before recording** - the log header stores it and the benchmark replays with the matching settings: bikes get a looser lateral constraint) > Sensors > "Navigation core" > Record drive. Recording holds the screen awake (`FLAG_KEEP_SCREEN_ON`) and is flushed to disk when the app is backgrounded; the app must stay in the foreground (backgrounding stops sensors and GPS by design). Limits: 2 M records / 256 MB (~8 h); ~9 KB/s (~32 MB/h).
- **Mount alignment** (`AlignmentConfig`): needs >= 20 distinct straight-line speed changes of >= 0.5 m/s^2 (yaw rate < 0.08 rad/s), >= 400 IMU samples, confidence >= 0.6, and restarts if gravity in the phone frame moves > 0.25 rad (phone shifted in its mount). Sensors tab pill: "Calibrating" -> "Leading".
- **Where the data is:** app-private `app_flutter/drives/drive-<time>.jsonl` (header line: device, OS, vehicle, config). Survives `adb install -r` and relaunch; **lost on uninstall or Clear storage**. Pull from a debug build: `adb -s <serial> exec-out run-as com.gatisaarth.app cat app_flutter/drives/<file> > drive.jsonl` (use `MSYS_NO_PATHCONV=1` in Git Bash). In-app: Profile > Outage Benchmark > share icon sends a gzip copy through the Android share sheet (asks first - the file is a full location trace); trash icon deletes.
- **Score a drive headless:** `DRIVE_LOG=<file.jsonl or .jsonl.gz> flutter test test/nav/score_drive_test.dart`. On device: Outage Benchmark > tap the drive (~1-3 min for a 30 min ride; 34 min = 104k records scored in 42 s on a PC).
- **Traps found while building this:** the log header is stamped `u: 0` while sensor lines use the phone's uptime clock (~1e15 us), so timing must come from the first sensor line, never the header. The Home tab keeps invisible, hit-testable test-hook buttons (opacity 0.001, incl. "Two-wheeler" and "Tunnel test") near its bottom edge: a stray tap there changes state. The Sensors tab's constellation and NavIC panels are demo data.

## Known gotchas
- **The Android emulator has no real GPS.** Its location is pinned to Google HQ (37.4220, -122.0840) until you set one (emulator ⋮ → Location, or `adb emu geo fix <lon> <lat>`). "Not finding my location" on an emulator is almost always this.
- Android Studio's run-target dropdown defaulting to "Windows (desktop)" gives "No Windows desktop project configured" — pick the emulator/phone instead; this app is mobile-only.
- The tool shells don't have Flutter on PATH; use `C:\src\flutter\bin\flutter.bat` and `JAVA_HOME=C:\Program Files\Android\Android Studio\jbr`. The bundled `sdkmanager` (cmdline-tools 16111833) crashes — install SDK/NDK packages by downloading them directly.
- Android emulator networking: use `10.0.2.2` not `localhost` to reach a backend running on the host machine (already handled in the candidate list above).
- `minSdk`/`compileSdk`/`ndkVersion` come from the Flutter SDK's own gradle config (`flutter.minSdkVersion` etc.) — don't hardcode versions in `android/app/build.gradle`.
- Assets are large (the 37 MB Delhi map archive, ~170 fallback PNG tiles, TFLite/ONNX models) — first build/index in Android Studio can be slow. The archive is git-ignored: a checkout without `frontend/assets/maps/packs/delhi-ncr.pmtiles` still builds and runs, the map then uses cached/online tiles until a region is downloaded (Profile > Offline Maps). Get it with `tools/offline_maps/README.md`.

## Feedback / workflow notes
- Nothing accumulated yet this session — see `~/.claude/rules/` for the standing global rules (TDD, code review, git workflow) that still apply once real feature work starts here.
