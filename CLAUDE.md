# GatiSaarth — Dead Reckoning Navigation System

Monorepo (git repo; remote `origin` is the private GitHub repo `GATISAARTHI`). This file's folder is the repo root.

## What's here

- `frontend/` — Flutter app (Dart). The thing you run in Android Studio / emulator.
- `cpp-core/` — C++17 edge engine (ES-EKF, SPSC pipeline, CSV and UDP external-IMU input, replay and 200 Hz bench tools). The Flutter app does **not** link it; it is for edge boards and fast replays. Build: `cmake -S cpp-core -B <dir> && cmake --build <dir> --config Release && ctest --test-dir <dir> -C Release`.
- `ml/` — our IO-VNBD data pipeline (`ml/src/dataset/`) and the speed-model training script `ml/src/training/train_speed_v4.py` (TensorFlow, run with `ml/.venv-export/Scripts/python.exe`; it writes `ml/models/speed_estimator_v4/`). **The shipped speed model is v4**: `frontend/assets/models/speed_estimator.tflite` (float32, 209 KB, built-in ops only), a dilated causal TCN trained from scratch; held-out MAE 3.33 m/s, 61 % of errors inside 1-sigma. It is **gated**: it only enters the filter after agreeing with GNSS Doppler speed (RMS <= 1 m/s) on the same drive, which it does not reach on the held-out IO-VNBD trips, so navigation there is identical with it on or off. `ml/src/export/ai_replay_log.py` builds the replay logs for `test/nav/real_ai_ablation_test.dart`.

**Originality (2026-09-24).** The first commit of this repo was built on another SIH team's public repo (`saksham4455/SIH_DEAD_RECKONING`, not this team). Their `backend/`, `simulation/`, `scripts/`, copied `cpp-core` and `ml` scaffolding, their notebook-derived speed model and their aux ONNX models, the bundled raster tiles and ~40 frontend files were removed from the app or rewritten; a script lists what is still on disk to delete (`docs/sih2026/remove_third_party_code.sh`, git-ignored). Never reintroduce code from that repo, and never present a backend, a C++ UKF or the aux vibration/motion-quality models as this team's work.

### No backend
The app has no server. Telemetry is a local-only no-op sink (`core/platform/network/telemetry_sink.dart`); drives leave the phone only through the share sheet.

## Where the rest of the notes live (loaded on demand)

- `frontend/lib/core/nav/CLAUDE.md` — navigation core: module rules, the outage benchmark, measured limits, drift/cost/ablation numbers, road-locked DR internals and real-road traps.
- `frontend/test/CLAUDE.md` — widget-test rules learned the hard way.
- Skills in `.claude/skills/`: `offline-maps` (map stack, packs, sizes, map gotchas), `field-test-drive` (record / pull / score a drive), `iovnbd-dataset` (IO-VNBD data and scoring).

## Navigation core (`frontend/lib/core/nav/`) — contracts that apply everywhere

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

**Never quote simulated results (drift benchmark, reference drive, ablation) as
field accuracy; record real drives and score them.** The outage benchmark is the
only accuracy yardstick that works on real phones.

**Road-locked dead reckoning (2026-09-21).** The Tunnel test, the Urban canyon and
real GNSS outages hold the marker to the road network read on the phone from the
installed offline map packs (maxZoom >= 13), so it follows the drawn streets.
Live GNSS is **never** snapped: a real fix releases the lock. With no pack or no
road within 40 m the old heading integration runs. Not checked on a physical
phone; lane level is **not** claimed (the map data has no lanes).

## Frontend architecture (as of 2026-09-18)

- **One live pipeline.** `frontend/lib/features/navigation_ui/presentation/controllers/live_session_controller.dart` owns sensors, GNSS, dead reckoning, uncertainty and telemetry. It is provided app-wide by `live_session_scope.dart` and started/paused/resumed from `lib/app_widget.dart` (pauses sensors + GPS when the app is backgrounded). `dashboard_screen.dart` and `active_nav_screen.dart` are thin views — never add sensor subscriptions or timers to a screen. Listeners are notified at most 10 Hz.
- **Start-up.** `features/boot/presentation/boot_screen.dart` is only a 1.4 s branded animation that fades into the dashboard (there is no `BootSequence`; an earlier version of this note described one that does not exist in the code). What the app is actually waiting for after that is shown by the **sync capsule**: `controllers/sync_status.dart` derives `SyncStatus` from real state only (sensors delivering, motion model initialised, GNSS status, reacquiring) and `widgets/sync_capsule.dart` slides it in from the top ("Syncing · Finding satellites", 3-segment progress, "Synced" for ~1.6 s, then gone). It waits 300 ms before appearing (no flash), says "Still searching · try open sky" after 40 s, never takes taps, and is hidden for problems only the user can fix (location off / permission), which have their own banner. The Home confidence ring spins instead of sitting empty while syncing. **Tests must not `pumpAndSettle` on the dashboard** while sensors or a fix are pending: loading spinners never settle - pump real frames in bounded steps.
- **Haptics: one policy, three events.** `core/platform/hardware/haptics.dart` is the only code that may vibrate the phone. It fires for `outageStarted` (GNSS signal lost while the driver was using the app, or the tunnel test; double pulse, 45 s cool-down, silent while recording because a vibrating phone shakes its own IMU trace and the alert lands exactly where DR is measured, silent for the 20 s after resuming from the background and for a location switch the user turned off), `recordingStarted` (one 60 ms tick) and `recordingStopped` (two ticks). Deliberately **not** haptic: bump/pothole detection (visual ticker only), button taps (`PressableScale` no longer calls `HapticFeedback`; tooltips have `enableFeedback: false`), GNSS recovery, the Urban canyon / Reset demo buttons. Profile > "Haptic alerts" switch turns everything off and is remembered (`haptics_enabled`). Verified on a device with `adb shell dumpsys vibrator_manager` (lists every vibration per package with its reason); `performHapticFeedback(constant=4)` entries from `com.gatisaarth.app` mean something is calling `HapticFeedback.selectionClick()` again.
- **Home tab test hooks are inert on a phone.** The invisible (opacity 0.001) "Tunnel test" / "Two-wheeler" / "Start fullscreen navigation" buttons at the end of the Home list are hit-testable and exposed to screen readers only under `flutter test` (`FLUTTER_TEST` env var).
- **Light/dark:** `core/theme/theme_controller.dart` owns the choice; `ThemeTransitionHost` flips it by marking **every element dirty** (no remount, so the route stack survives). **Never cache a palette getter** in a `static final`, a field initialiser or a top-level `final`: marking elements dirty re-runs `build`, not initialisers (that is how the map chips got white text on a white pill in light mode, and how the Privacy tile stayed near-black on near-black in dark). `MaterialApp.themeAnimationDuration` is zero so its own colour lerp does not fight the wipe. Material 3 ignores `ThemeData.dividerColor`; `dividerTheme` is set explicitly.
- **Overscroll:** `core/widgets/soft_overscroll.dart` (`AppScrollBehavior`) reproduces Android's stretch effect at `kStretchStrength = 0.35` of stock (asked for: half, then 30 % less again). `MaterialApp.scrollBehavior` applies it everywhere.
- **GNSS state machine:** `core/platform/location/live_location_service.dart` (`LocationStatus`: initializing / serviceOff / permissionDenied / permissionBlocked / searching / live / stale). "Live" only ever means a real fix arrived within 6 s — a cached last-known position never counts.
- **Confidence is modelled, not hard-coded:** `features/navigation_engine/domain/uncertainty_model.dart` (live = GNSS accuracy; outage = accuracy at loss + 5 % of distance + 0.15 m/s). `null` uncertainty means "no fix yet" — the UI shows `--`, never a made-up number.
- **Dead-reckoning outage = any non-live state after a real fix** (stale, location off, permission revoked, re-searching after a resume). The outage is noticed ~6 s late, so the tracker is backdated by the time since the last fix and, for gaps ≤ 15 s, that travel is extrapolated at the last GNSS speed; longer gaps only widen the margin.
- **Speed-model input contract** (`_feedModel`): 10 Hz (not the 50 Hz sensor rate), raw accelerometer *including gravity* (levelled vehicle-frame accel + 9.81 on z), pitch/roll 0 — that is what `assets/models/model_metadata.json`'s scaler was fit on. Feeding gravity-free 50 Hz data puts inputs ~75σ off-distribution. AI confidence/latency show `--` until the TFLite model has really run (`hasModelInference`); the heuristic fallback is never presented as AI.
- **Known limits, don't paper over them:** no yaw alignment (phone→vehicle forward axis is unknown) and heading assumes a flat phone (`atan2(-mx, my)`), so off a road DR direction is only trustworthy with the phone flat and top-forward (on a road the direction comes from the road, see Road-locked dead reckoning); the variance-only stationary gate can mistake a smooth cruise for a stop (ZUPT is therefore delayed 3 s at speed); the shipped model's own benchmark (`ml/evaluation/metrics/08_gnss_outage_benchmark_results.json`) shows AI-speed DR *worse* than classical DR on its synthetic set, so never claim drift reduction from it.
- **No demo data left in the UI:** the satellite breakdown, NavIC share and diagnostics read the phone's real `GnssStatus` telemetry and show `--` until it arrives; the Sensors tab and the Home rings are derived from measured stream rates, fault diagnoses and the map matcher.

## Security

- The raster map fallback (`offline_tile_provider.dart`, Stadia OSM Bright) has **no compiled-in key** any more (the old default key belonged to the other team). Online raster tiles need `--dart-define=STADIA_API_KEY=<the team's own key>`.

## Testing

`cd frontend && flutter test` — headless, no device/emulator needed. Widget tests must call `loadAppFonts()` (`test/support/load_fonts.dart`) — otherwise Flutter's test font (every glyph a full-width square) creates false overflow failures. More widget-test rules: `frontend/test/CLAUDE.md`.

## Known gotchas
- **The Android emulator has no real GPS.** Its location is pinned to Google HQ (37.4220, -122.0840) until you set one (emulator ⋮ → Location, or `adb emu geo fix <lon> <lat>`). "Not finding my location" on an emulator is almost always this.
- Android Studio's run-target dropdown defaulting to "Windows (desktop)" gives "No Windows desktop project configured" — pick the emulator/phone instead; this app is mobile-only.
- The tool shells don't have Flutter on PATH; use `C:\src\flutter\bin\flutter.bat` and `JAVA_HOME=C:\Program Files\Android\Android Studio\jbr`. The bundled `sdkmanager` (cmdline-tools 16111833) crashes — install SDK/NDK packages by downloading them directly.
- `minSdk`/`compileSdk`/`ndkVersion` come from the Flutter SDK's own gradle config (`flutter.minSdkVersion` etc.) — don't hardcode versions in `android/app/build.gradle`.
- Assets are large (the 37 MB Delhi map archive, the TFLite model) — first build/index in Android Studio can be slow. The archive is git-ignored: a checkout without `frontend/assets/maps/packs/delhi-ncr.pmtiles` still builds and runs, the map then uses cached tiles (and online Stadia tiles only in a build made with `--dart-define=STADIA_API_KEY=...`) until a region is downloaded (Profile > Offline Maps). Get it with `tools/offline_maps/README.md`.

## Building & Updating APKs (Monorepo & Landing Page Workflow)

Whenever a new APK is built or updated, it must appear in `apks/` and be synchronized to the public landing page.

### 1. One-Command Build & Sync
Run from repo root:
- **Windows PowerShell**: `.\scripts\build_and_sync_apk.ps1`
- **Linux / macOS / Bash**: `./scripts/build_and_sync_apk.sh`

This runs `flutter build apk --release` and automatically synchronizes all APK outputs and landing page assets.

### 2. Synchronizing an Existing APK File
If you already have an APK file built in `apks/` or elsewhere:
```bash
# From repo root (with explicit path or auto-detect):
node tools/sync_apk.js apks/GatiSaarth-v5.2+51-release.apk

# Or from landing_page directory:
cd landing_page && npm run sync-apk
```

### What the Sync Tool (`tools/sync_apk.js`) Automates:
1. **Canonical naming in `apks/`**: Copies to `apks/GatiSaarth-v<version>+<build>-release.apk` and updates `apks/app-release.apk` + `app-release.apk.sha1`.
2. **Landing Page Download Asset**: Copies to `landing_page/public/downloads/gatisaarth-<version>.apk` and removes stale APK binaries.
3. **Checksums**: Re-hashes the file and updates `landing_page/public/downloads/SHA256SUMS.txt`.
4. **Website UI**: Updates `landing_page/index.html` download buttons (`href`), version pill badge (`v<version>`), file size (`<size> MB`), and the verification code element (`#apk-hash`).
5. **Vercel & Playwright**: Updates download header in `landing_page/vercel.json` and download filename/byte size expectations in `landing_page/tests/launch.spec.js`.
6. **Production Bundle**: Re-runs `npm run build` inside `landing_page` so `dist/` is instantly production-ready.
