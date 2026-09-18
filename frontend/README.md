# GatiSaarth — Flutter app

The `frontend/` directory is the GatiSaarth Android app (Dart package `gatisaarth`, application id `com.gatisaarth.app`). See the [root README](../README.md) for what the product does and its known limits.

## Architecture

One live pipeline feeds thin screens.

```
lib/
├── main.dart, app_widget.dart        boot, lifecycle (pause sensors/GPS in background)
├── core/
│   ├── platform/
│   │   ├── location/                 LiveLocationService — GNSS state machine
│   │   ├── hardware/                 sensor driver, vehicle alignment (gravity, NHC)
│   │   ├── maps/                     offline tile provider (bundled → cache → network)
│   │   └── network/                  telemetry client with backoff
│   ├── theme/, widgets/              design tokens, shared motion widgets
│   └── utils/
└── features/
    ├── ai_motion/                    speed estimator (TFLite + rule-based fallback)
    ├── navigation_engine/            fusion modes, modelled uncertainty
    └── navigation_ui/
        ├── presentation/controllers/ LiveSessionController — the single pipeline
        ├── presentation/screens/     dashboard, full-screen navigation
        └── presentation/widgets/
```

- **`LiveSessionController`** owns the sensors, GNSS, dead reckoning, uncertainty and telemetry. Screens only observe it — never add sensor subscriptions or timers to a screen. Listeners are notified at most 10 Hz.
- **`LiveLocationService`** models GNSS as `initializing / serviceOff / permissionDenied / permissionBlocked / searching / live / stale`.
- **Uncertainty is modelled, not hard-coded** (`uncertainty_model.dart`); `null` means "no basis" and the UI shows `--`.
- **Speed model contract:** the estimator expects 10 Hz raw accelerometer data including gravity. The bundled `.tflite` files are currently LFS pointers, so a rule-based fallback runs until real models are added.

## Commands

```bash
flutter pub get
flutter analyze
flutter test                 # headless, no device needed
flutter build apk --debug    # compile only
flutter run                  # Android device or emulator
```

Widget tests call `loadAppFonts()` (`test/support/load_fonts.dart`); without it Flutter's test font is far wider than the real one and produces false overflow failures.

## Notes

- The Android emulator has no real GPS — set a location in its Extended controls or with `adb emu geo fix <lon> <lat>`.
- `android/local.properties`, `build/` and `.dart_tool/` are generated and git-ignored.
- Map attribution: © OpenStreetMap contributors · Stadia Maps.
