# GatiSaarth — Dead Reckoning Navigation System

Monorepo (git repo; remote `origin` is the private GitHub repo `GATISAARTHI`). This file's folder is the repo root.

## What's here

- `frontend/` — Flutter app (Dart). The thing you run in Android Studio / emulator. Has its own `android/` gradle project (standard Flutter scaffold, Gradle 9.3.1 / AGP 9.1.0 / Kotlin 2.4.0, Java 17).
- `backend/` — dual backend: Python FastAPI (`backend/app`, port 8000) + TypeScript WS/EKF engine (`backend/src`, port 8080). Optional for running the app — see below.
- `cpp-core/` — C++17 SINS/UKF engine. **Not wired into the Flutter app yet** (no `dart:ffi`/`DynamicLibrary` calls in `frontend/lib` as of this writing, despite the README architecture diagram showing it). Only matters if you're building that integration.
- `ml/` — PyTorch training pipeline (the PyTorch model source is a stub here; the ONNX files are the source of truth). **The speed model is real and loads**: `frontend/assets/models/speed_estimator.tflite` (float32, 351 KB, built-in ops only) is generated from `speed_estimator.onnx` by `ml/src/export/onnx_to_tflite.py`, which rebuilds the net in TF ops (onnx2tf mis-converts its BiGRU) and checks parity against onnxruntime (max diff 6.7e-06). It is float32, not INT8, on purpose. **The `vibration_classifier_int8.tflite` and `motion_quality_int8.tflite` files are still ~130-byte Git LFS pointer stubs** and the app does not load them. The model runs on IMU motion whether or not GNSS is live (so the AI panel has data), but its speed only drives dead reckoning once GNSS is gone. Its own benchmark (`model_metadata.json`) shows worse 30 s outage drift than classical DR, so don't claim it improves accuracy.
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
- **Start-up is a real sequence, not a timer.** `frontend/lib/features/boot/presentation/` — `BootScreen` is the initial route (`/boot`) and draws the launch lock-up; `BootSequence` walks four stages (tile cache, first IMU sample, TFLite model loaded, location permission/service resolved) and the progress bar only advances on completed stages. Every stage has a poll budget so a phone with location off can never hang the app; a stage that times out is logged and skipped, never reported as done. Stage budgets are counted in polls, not wall-clock, so they behave the same under `flutter test`'s fake clock. Drop the launch photograph at `frontend/assets/images/boot_background.png`; without it the screen falls back to a painted gradient. The OS splash (`flutter_native_splash`) is only a bridge and uses the same `#050A14` background with no wordmark.
- **Light/dark:** `core/theme/theme_controller.dart` owns the choice (persisted in `SharedPreferences` under `theme_is_dark`, first launch follows the platform). Surface/label tokens on `AppColors` are getters that resolve against the app-wide `AppColors.isDark` flag, set by `app_widget.dart` before each build; the root re-keys `MaterialApp` on a flip so `const` subtrees pick up the new colours too. Accent/status colours are the same in both brightnesses. Card shadows collapse to nothing in dark mode (cards separate by surface colour, iOS-style), and the bundled daylight map raster is inverted/desaturated by `_DarkMapFilter`. The toggle lives in `DashboardHeader`.
- **GNSS state machine:** `core/platform/location/live_location_service.dart` (`LocationStatus`: initializing / serviceOff / permissionDenied / permissionBlocked / searching / live / stale). "Live" only ever means a real fix arrived within 6 s — a cached last-known position never counts.
- **Confidence is modelled, not hard-coded:** `features/navigation_engine/domain/uncertainty_model.dart` (live = GNSS accuracy; outage = accuracy at loss + 5 % of distance + 0.15 m/s). `null` uncertainty means "no fix yet" — the UI shows `--`, never a made-up number.
- **Dead-reckoning outage = any non-live state after a real fix** (stale, location off, permission revoked, re-searching after a resume). The outage is noticed ~6 s late, so the tracker is backdated by the time since the last fix and, for gaps ≤ 15 s, that travel is extrapolated at the last GNSS speed; longer gaps only widen the margin.
- **Speed-model input contract** (`_feedModel`): 10 Hz (not the 50 Hz sensor rate), raw accelerometer *including gravity* (levelled vehicle-frame accel + 9.81 on z), pitch/roll 0 — that is what `assets/models/model_metadata.json`'s scaler was fit on. Feeding gravity-free 50 Hz data puts inputs ~75σ off-distribution. AI confidence/latency show `--` until the TFLite model has really run (`hasModelInference`); the heuristic fallback is never presented as AI.
- **Known limits, don't paper over them:** no yaw alignment (phone→vehicle forward axis is unknown) and heading assumes a flat phone (`atan2(-mx, my)`), so DR direction is only trustworthy with the phone flat and top-forward; the variance-only stationary gate can mistake a smooth cruise for a stop (ZUPT is therefore delayed 3 s at speed); the shipped model's own benchmark (`ml/evaluation/metrics/08_gnss_outage_benchmark_results.json`) shows AI-speed DR *worse* than classical DR on its synthetic set, so never claim drift reduction from it.
- **Deliberately still demo data (labelled as such in the UI):** the satellite breakdown and NavIC weight panels, and the diagnostics screen. Real `GnssStatus` (Android platform channel) is not wired yet. Map-matching (HMM/OSM) does not exist; the old "Map match %" was removed rather than faked.

## Testing

`cd frontend && flutter test` — headless, no device/emulator needed (~90 tests: state machines, dead-reckoning maths, telemetry backoff, tile gate, and real-screen widget tests at 320/360/411 dp). Widget tests must call `loadAppFonts()` (`test/support/load_fonts.dart`) — otherwise Flutter's test font (every glyph a full-width square) creates false overflow failures.

## Known gotchas
- **The Android emulator has no real GPS.** Its location is pinned to Google HQ (37.4220, -122.0840) until you set one (emulator ⋮ → Location, or `adb emu geo fix <lon> <lat>`). "Not finding my location" on an emulator is almost always this.
- Android Studio's run-target dropdown defaulting to "Windows (desktop)" gives "No Windows desktop project configured" — pick the emulator/phone instead; this app is mobile-only.
- The tool shells don't have Flutter on PATH; use `C:\src\flutter\bin\flutter.bat` and `JAVA_HOME=C:\Program Files\Android\Android Studio\jbr`. The bundled `sdkmanager` (cmdline-tools 16111833) crashes — install SDK/NDK packages by downloading them directly.
- Android emulator networking: use `10.0.2.2` not `localhost` to reach a backend running on the host machine (already handled in the candidate list above).
- `minSdk`/`compileSdk`/`ndkVersion` come from the Flutter SDK's own gradle config (`flutter.minSdkVersion` etc.) — don't hardcode versions in `android/app/build.gradle`.
- Assets are large (map tiles + TFLite/ONNX models, ~180 files under `frontend/assets/`) — first build/index in Android Studio can be slow.

## Feedback / workflow notes
- Nothing accumulated yet this session — see `~/.claude/rules/` for the standing global rules (TDD, code review, git workflow) that still apply once real feature work starts here.
