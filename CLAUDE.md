# GatiSaarth — Dead Reckoning Navigation System

Monorepo (git repo; remote `origin` is the private GitHub repo `GATISAARTHI`). This file's folder is the repo root.

## What's here

- `frontend/` — Flutter app (Dart). The thing you run in Android Studio / emulator. Has its own `android/` gradle project (standard Flutter scaffold, Gradle 9.3.1 / AGP 9.1.0 / Kotlin 2.4.0, Java 17).
- `backend/` — dual backend: Python FastAPI (`backend/app`, port 8000) + TypeScript WS/EKF engine (`backend/src`, port 8080). Optional for running the app — see below.
- `cpp-core/` — C++17 SINS/UKF engine. **Not wired into the Flutter app yet** (no `dart:ffi`/`DynamicLibrary` calls in `frontend/lib` as of this writing, despite the README architecture diagram showing it). Only matters if you're building that integration.
- `ml/` — PyTorch training pipeline. **The `.tflite` files everywhere in the repo are Git LFS pointer files (~130 bytes), not real models** — the neural speed model has never loaded; the app runs the rule-based fallback and the AI panel shows `--` / "Model not loaded". Real `.onnx` exports exist; regenerate INT8 TFLite from them.
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

## Frontend architecture (as of 2026-09-18)

- **One live pipeline.** `frontend/lib/features/navigation_ui/presentation/controllers/live_session_controller.dart` owns sensors, GNSS, dead reckoning, uncertainty and telemetry. It is provided app-wide by `live_session_scope.dart` and started/paused/resumed from `lib/app_widget.dart` (pauses sensors + GPS when the app is backgrounded). `dashboard_screen.dart` and `active_nav_screen.dart` are thin views — never add sensor subscriptions or timers to a screen. Listeners are notified at most 10 Hz.
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
