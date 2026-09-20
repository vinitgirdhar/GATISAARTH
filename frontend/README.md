# GatiSaarth — Flutter Mobile Application

The `frontend/` directory contains the complete source code for the **GatiSaarth Android Application** (Dart package `gatisaarth`, application ID `com.gatisaarth.app`).

For the high-level system overview, problem statement, mathematical derivations, and project-wide benchmarks, refer to the [Root README](../README.md).

---

## Table of Contents

1. [Architecture & Design Principles](#architecture--design-principles)
2. [Directory Structure](#directory-structure)
3. [Core Subsystems & State Management](#core-subsystems--state-management)
4. [Screens & Feature Walkthrough](#screens--feature-walkthrough)
5. [Offline Vector Map Engine](#offline-vector-map-engine)
6. [Edge AI Speed Estimator](#edge-ai-speed-estimator)
7. [Commands & Build Workflows](#commands--build-workflows)
8. [Testing Rules & Gotchas](#testing-rules--gotchas)
9. [Live Presentation & Demo Playbook](#live-presentation--demo-playbook)
10. [Hardware, Permissions & Notes](#hardware-permissions--notes)

---

## Architecture & Design Principles

The frontend is architected around a strict **single-pipeline, reactive state model**:

1. **Single Source of Truth (`LiveSessionController`):**
   - Owns hardware sensor streams, GNSS state machines, inertial dead reckoning, uncertainty estimation, and optional telemetry.
   - Screens and widgets are **thin, passive observers**. No screen may ever subscribe directly to a sensor stream or manage its own navigation timer.
   - UI listeners are notified at a controlled maximum rate of **10 Hz**, preventing unnecessary frame rebuilds and conserving battery.

2. **Fail-Safe Core Handover (`isEngineLeading`):**
   - The pure-Dart navigation core (`lib/core/nav/`) leads the app only when healthy:
     - Phone-to-vehicle mount calibration has converged (requires ~40 s of driving with at least 20 straight-line acceleration/braking events).
     - GNSS integrity check passes without numerical divergence.
     - Minimum sensor suite (accelerometer + gyroscope) is actively delivering data.
   - If any condition fails, the controller immediately hands over to the simpler kinematic fallback pipeline. The app is **never worse** than the fallback (`test/engine_handover_test.dart` pins this contract).

3. **Honest, Modelled Uncertainty:**
   - Confidence is mathematically derived rather than hardcoded. When GNSS is live, uncertainty equals the reported satellite horizontal accuracy. During an outage, uncertainty expands based on elapsed time, distance traveled, and the filter's covariance matrix.
   - If no valid position basis exists, the UI displays `--` instead of fabricated numbers.

4. **Single-Vibrator Haptic Policy:**
   - Only three events may ever trigger device vibration:
     - `outageStarted` (GNSS signal lost while driving; double pulse, 45 s cooldown; silent while recording to protect the IMU trace).
     - `recordingStarted` (single 60 ms tick).
     - `recordingStopped` (double 60 ms tick).
   - Button taps, road anomaly alerts, and GNSS reacquisition are strictly non-haptic to avoid sensor corruption and driver annoyance.

5. **Top-to-Bottom Theme Transition:**
   - Theme switching uses `ThemeTransitionHost` to capture a frozen snapshot of the current frame, toggle `AppColors.isDark`, mark every element dirty (ensuring `const` widgets adapt), and wipe the old frame away top-to-bottom in 620 ms.
   - `AppColors` tokens are dynamic getters over a global brightness flag. Never cache color tokens in `static final` or top-level variables.

---

## Directory Structure

```
frontend/
├── android/                         # Native Android Gradle project (AGP 9.1.0, Kotlin 2.4.0)
│   └── app/src/main/kotlin/        # MainActivity.kt (PMTiles asset locator, thermal telemetry)
├── assets/
│   ├── fonts/                      # Inter font family
│   ├── icons/                      # Wordmark and launcher branding
│   ├── maps/
│   │   ├── packs/                  # PMTiles archives (delhi-ncr.pmtiles, 37 MB, git-ignored)
│   │   └── tiles/                  # Fallback offline raster tiles (Delhi zoom 11-16)
│   └── models/                     # speed_estimator.tflite (351 KB float32 BiGRU)
├── lib/
│   ├── main.dart                   # Application entry point, scope initialization
│   ├── app_widget.dart             # Root MaterialApp, theme transition host, lifecycle hooks
│   ├── core/
│   │   ├── nav/                    # Pure-Dart Navigation Core (Zero Flutter imports)
│   │   │   ├── ekf/                # 15-state Error-State Kalman Filter
│   │   │   ├── ins/                # Strapdown inertial mechanization (WGS-84 NED)
│   │   │   ├── math/               # NavMath (geodesy, quaternions, NED frame) and Matrix
│   │   │   ├── gnss/               # Quality scoring, outlier rejection, integrity monitor
│   │   │   ├── motion/             # Motion classifier, ZUPT/ZARU gating, NHC
│   │   │   ├── alignment/          # Dynamic mount alignment (gravity + auto-yaw regression)
│   │   │   ├── calibration/        # Sensor bias and magnetometer ellipsoid calibration
│   │   │   ├── sensors/            # TimeSync (k-way merge) & sensor fault detection
│   │   │   ├── map/                # Road graph index and HMM map matcher (Newson-Krumm)
│   │   │   ├── replay/             # Bit-exact deterministic drive replayer
│   │   │   ├── benchmark/          # Outage benchmark engine and scoring metrics
│   │   │   ├── nav_config.dart     # Central versioned repository of all engine thresholds
│   │   │   └── navigation_engine.dart # Engine assembly emitting snapshots at 10 Hz
│   │   ├── platform/               # Device hardware, storage, and platform channels
│   │   │   ├── location/           # LiveLocationService (7-state GNSS state machine)
│   │   │   ├── hardware/           # Sensor driver, vehicle alignment, haptic policy
│   │   │   ├── maps/               # PMTiles reader, region extractor, download service
│   │   │   ├── storage/            # DriveLogStore (JSONL recordings in app-private storage)
│   │   │   └── network/            # BackendTelemetryClient with exponential backoff
│   │   ├── theme/                  # AppColors, AppTypography, AppTheme tokens
│   │   ├── widgets/                # SoftOverscroll, FadeIndexedStack, ThemeTransitionHost
│   │   └── router/                 # Named route definitions
│   └── features/                   # Screen controllers and UI presentation
│       ├── navigation_ui/          # LiveSessionController, Home, Map, Sensors, Profile tabs
│       ├── offline_maps/           # Offline Maps screen, download prompt and bottom sheet
│       ├── about/                  # Navigation Engine technical specification screen
│       ├── benchmark/              # Outage Benchmark screen and background isolate runner
│       ├── ai_motion/              # TFLite speed estimator integration & stillness gate
│       ├── navigation_engine/      # Domain models (UncertaintyModel, NavigationState)
│       ├── data_acquisition/       # Frame models and stream controllers
│       └── boot/                   # Branded start-up screen and transition
└── test/                           # Automated unit, widget, and navigation benchmark tests
```

---

## Core Subsystems & State Management

### 1. `LiveSessionController`
The central nervous system of the app (`lib/features/navigation_ui/presentation/controllers/live_session_controller.dart`). It:
- Ingests raw IMU, magnetometer, barometer, and GNSS frames.
- Feeds data chronologically through `TimeSync` to eliminate timestamp skew.
- Evaluates engine health to determine whether the navigation core or kinematic fallback drives the vehicle marker.
- Emits unified `NavigationState` updates to the UI at up to 10 Hz.
- Flushes drive logs to disk when the app is backgrounded.

### 2. `LiveLocationService`
A robust 7-state machine governing satellite tracking (`lib/core/platform/location/live_location_service.dart`):
```
[initializing] ──▶ [searching] ──▶ [live] ──(>6s no fix)──▶ [stale]
       │                 │
       ▼                 ▼
[serviceOff]    [permissionDenied / permissionBlocked]
```
- **"Live"** strictly requires a fresh satellite fix within the past 6 seconds; cached positions never count.
- Outages are backdated by the elapsed time since the last valid fix, and intervals up to 15 seconds are extrapolated at the last known GNSS velocity.

### 3. `SyncStatus` & `SyncCapsule`
Provides transparent visual feedback on startup (`lib/features/navigation_ui/presentation/widgets/sync_capsule.dart`):
- Displays real-time initialization progress ("Syncing · Finding satellites").
- Automatically transitions to "Synced" once GNSS locks, dismissing after 1.6 seconds.
- Displays "Still searching · try open sky" after 40 seconds of searching.

---

## Screens & Feature Walkthrough

### 1. Home Tab
- **Real-Time Speed & Heading:** Displays current speed (km/h) and compass heading.
- **Dynamic Confidence Ring:** Visualizes real-time positioning uncertainty in metres; spins during initial satellite acquisition.
- **Status Banners:** Clear indicators for satellite lock, dead reckoning active, or sensor calibration in progress.
- **Scenario Simulator Test Hooks:** Quick-action buttons ("Tunnel test", "Urban canyon", "Reset") to demonstrate outage handling on demand.

### 2. Map Tab
- **Vector Basemap:** Sharp, high-resolution rendering powered by `vector_map_tiles` and local PMTiles archives.
- **Follow Modes:**
  - *Free:* Free panning and zooming.
  - *North-Up:* Camera follows vehicle with North locked at top.
  - *Heading-Up:* Map rotates dynamically with vehicle course, applying forward lookahead easing.
- **Track Trail:** Visualizes the route driven—**solid blue** for satellite-backed fixes and **dashed red** for dead-reckoned segments.
- **Accuracy Halo:** Scale-accurate circle illustrating horizontal position uncertainty.

### 3. Sensors Tab
- **Live Sensor Telemetry:** Real-time stream rates (Hz) and values for 3-axis accelerometer, gyroscope, magnetometer, and barometer.
- **Mount Calibration Pill:** Displays mount alignment status ("Calibrating" $\rightarrow$ "Leading").
- **Satellite Constellation Grid:** Visual representation of satellite signal strengths and tracking channels.

### 4. Profile Tab
- **Vehicle Profile Selector:** Toggle between **Car** (strict lateral constraint) and **Two-Wheeler** (lean-tolerant lateral constraint).
- **Offline Maps:** Manage installed map regions, monitor download progress, and free up storage.
- **Outage Benchmark:** Replay recorded drives or simulated reference files to score dead reckoning performance.
- **Appearance:** Toggle between Light and Dark themes with the animated top-to-bottom wipe.
- **GatiSaarth Navigation Engine:** Open technical specification sheets and model cards.

---

## Offline Vector Map Engine

GatiSaarth renders vector map tiles directly on the smartphone using OpenStreetMap data stored in **PMTiles v3** format.

```
[Installed PMTiles Archive] ──▶ [PackReader / In-Place Asset] ──▶ [vector_map_tiles] ──▶ [GPU Shader]
          │
      (missing)
          ▼
[Cached Raster Tiles] ───────▶ [Network Stadia Raster Fallback (Circuit Breaker)]
```

### In-Place APK Streaming
The bundled Delhi NCR map pack (`delhi-ncr.pmtiles`, 37 MB) is stored uncompressed inside the APK (`android/app/build.gradle`: `noCompress += ["pmtiles"]`). The native Android layer resolves its offset using `AssetManager.openFd` via the `com.gatisaarth.app/map_packs` platform channel. The Dart layer reads data directly from the APK file descriptor (`OffsetFileAt`), eliminating duplicate file storage on the phone.

### Client-Side HTTP Range Request Downloads
When downloading new regions (e.g., Pune 17 MB, Mumbai 26 MB, Maharashtra 79 MB):
- The app requests only the relevant byte ranges from the Protomaps planet build (`build.protomaps.com`).
- Files are saved as `<id>.pmtiles.part`, verified against PMTiles v3 header specifications, and atomically renamed.

---

## Edge AI Speed Estimator

An on-device neural network (`assets/models/speed_estimator.tflite`, 351 KB float32) provides supplementary velocity inference:

- **Model Architecture:** Bidirectional GRU (BiGRU) trained on 10 Hz IMU windows.
- **Input Contract:** 10 Hz raw accelerometer data *including gravity* (levelled vehicle frame + 9.81 m/s² on the vertical axis).
- **Advisory Role:** The neural model operates as a stillness gate. It can halt vehicle marker creep when stopped, but never overrides physics-based EKF velocity or position states.
- **Visual Disclosure:** The AI inference panel displays `--` until the model has executed on real sensor frames, preventing heuristic estimates from being misrepresented as AI output.

---

## Commands & Build Workflows

### Standard Development Commands

```bash
# Fetch dependencies
flutter pub get

# Run static analysis (must pass with zero errors)
flutter analyze

# Run headless unit and widget tests
flutter test

# Run the app on a connected device or emulator
flutter run
```

### Production Build Commands

```bash
# Build debug APK
flutter build apk --debug

# Build release APK (all architectures, ~77 MB fat binary)
flutter build apk --release

# Build release APKs split by ABI (~58 MB per architecture)
flutter build apk --release --split-per-abi

# Build Android App Bundle (for Google Play deployment)
flutter build appbundle
```

### Headless Outage Benchmarking

```bash
# Run benchmark on bundled simulated reference drive
flutter test test/nav/reference_drive_asset_test.dart

# Score a real drive recorded on a phone
DRIVE_LOG=path/to/drive.jsonl.gz flutter test test/nav/score_drive_test.dart
```

---

## Testing Rules & Gotchas

When writing or maintaining tests for the frontend, adhere to these established practices:

1. **Load Fonts in Widget Tests:**
   - Always call `loadAppFonts()` (`test/support/load_fonts.dart`). Without it, Flutter's default test font renders glyphs as wide rectangles, causing false layout overflow errors.

2. **Never Use `pumpAndSettle` with Navigation Widgets:**
   - Maps, loading spinners, and the sync capsule contain continuous or repeating animations. Calling `pumpAndSettle()` will time out.
   - Use bounded frame pumping via `frames(tester, count: 10, ms: 50)` from `test/support/app_harness.dart`.

3. **Clean Up Vector Map Timers:**
   - Widgets mounting `NavigationMap` start a 3-second cache maintenance timer and require `mockPathProvider()`.
   - Conclude map tests with `pumpWidget(const SizedBox.shrink())` followed by `tester.pump(const Duration(seconds: 5))` to clear pending timers.

4. **Dynamic Color Token Testing:**
   - Verify that UI components adapt properly when `ThemeController.toggle()` is executed. Always reset `AppColors.isDark = false` in `tearDown()`.

---

## Live Presentation & Demo Playbook

For presentations, hackathons, and technical evaluations, follow this quick-reference demonstration sequence:

| Step | Action | Expected Behavior |
|:---:|:---|:---|
| **1** | Launch App | Branded 1.4s boot animation; Sync Capsule displays satellite acquisition status. |
| **2** | Normal Map View | Vehicle marker renders with scale-accurate accuracy circle; track draws in solid blue. |
| **3** | Tap "Tunnel test" | Satellite fix is severed; track switches to **dashed red**; EKF dead reckoning takes over; uncertainty circle expands honestly. |
| **4** | Tap "Exit Tunnel" | Satellites restore; vehicle marker glides smoothly back to true fix without teleporting. |
| **5** | Tap "Urban canyon" | Injected multipath jump is rejected by the Chi-Square integrity gate; anomaly alert is logged. |
| **6** | Enable Airplane Mode | Offline vector map continues to render crisply from local PMTiles at all zoom levels. |
| **7** | Outage Benchmark | Open Profile > Outage Benchmark to replay and score drives with withheld GNSS. |

---

## Hardware, Permissions & Notes

- **Android Emulator GPS:** The Android emulator does not simulate GPS movement automatically. Inject coordinates via ADB:
  ```bash
  adb emu geo fix 73.8567 18.5204   # Pune coordinates
  ```
- **Permissions:**
  - `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` are requested at runtime for satellite positioning.
  - `INTERNET` is used solely for downloading optional offline map packs.
  - `VIBRATE` is used strictly for the three defined haptic events.
- **Map Attribution:** © OpenStreetMap contributors · Protomaps · Stadia Maps.
