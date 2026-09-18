# GatiSaarth

**Intelligent navigation beyond GNSS.**

GatiSaarth is an Android app that keeps a vehicle's position on the map when the satellite signal drops — in tunnels, underground parking, urban canyons or under jamming. It uses only the phone's own sensors (accelerometer, gyroscope, magnetometer, barometer) to dead-reckon until GNSS returns, and it tells the driver honestly how much to trust the position it is showing.

> **Status:** work in progress. This is not the final product — new features are still being added.

---

## What works today

| Area | Details |
|---|---|
| **Live GNSS state** | Explicit states — initializing, location off, permission denied/blocked, searching, live, stale. "Live" only ever means a real fix arrived in the last 6 s; a cached position never counts. |
| **Dead reckoning** | When GNSS is lost the app integrates speed along a magnetometer heading, with zero-velocity updates and non-holonomic constraints. The outage is backdated to the last real fix so the unobserved seconds still count. |
| **Driver-facing confidence** | A modelled position margin: live = GNSS accuracy; outage = accuracy at loss + 5 % of distance + 0.15 m per second. `--` is shown when there is no basis for a number. |
| **Vehicle profiles** | Car and two-wheeler constraint profiles; gravity-based pitch/roll alignment of the phone. |
| **Smooth reacquisition** | When GNSS returns the marker glides to the new fix instead of jumping. |
| **Offline maps** | Bundled OpenStreetMap tiles → on-device cache → optional online fetch (with a circuit breaker) → transparent fallback. Core navigation works with no network. |
| **Optional telemetry** | Streams state to the backend with exponential backoff; the app is fully functional without it. |
| **Road anomalies** | Potholes / speed breakers detected from vertical acceleration, with haptics. |
| **Scenario simulator** | "Tunnel" and "Urban canyon" tests to demonstrate outage behaviour on demand. |
| **Low-power design** | Sensors and GPS pause in the background; the UI refreshes at most 10 Hz; the neural model idles while GNSS is live; reduced-motion is respected. |
| **Interface** | iOS-style design system (layered shadows, sentence case, Cupertino transitions). |

## Known limits (read before relying on it)

- **The on-device neural speed model is not included.** The `.tflite` files in this repository are Git LFS pointer files, not real models, so the app currently runs its rule-based fallback and the AI panel shows `--` / "Model not loaded". The ONNX export is present in `ml/`; regenerate the INT8 TFLite from it to enable the model.
- **Satellite / NavIC panels are demo data** and are labelled as such — Android `GnssStatus` is not wired in yet.
- **No yaw alignment.** Heading assumes the phone is flat with its top pointing forward, so dead-reckoning direction is only trustworthy in that pose.
- **The stationary rule is variance-based**, so a very smooth steady cruise can be mistaken for a stop (the app waits 3 s at speed before zeroing).
- **Map matching (HMM/OSM), the backend EKF and the C++ core are not connected to the app.** They exist as separate components.
- **Accuracy has not been measured against ground truth.** Confidence numbers are modelled, not measured.
- Android is the tested target. iOS/Web folders are unmaintained scaffolding.

---

## Repository layout

```
frontend/      Flutter app (the product). lib/, assets/ (offline tiles), test/
backend/       Optional services: Python FastAPI (REST, auth, model hub) and a
               TypeScript WebSocket / EKF engine
ml/            PyTorch training pipeline, ONNX exports, evaluation metrics
cpp-core/      C++17 inertial-navigation / UKF library (not yet used by the app)
maps/          OSM ingestion and road-graph tooling
simulation/    Outage injection and scenario replay
docs/          Architecture notes
config/, scripts/, datasets/, docker-compose.yml
```

## Run the app

```bash
cd frontend
flutter pub get
flutter run          # pick an Android device or emulator
```

- Grant the location permission when asked. On an **emulator** there is no real GPS — set a location in the emulator's Extended controls, or:
  `adb emu geo fix <longitude> <latitude>`
- Debug build without launching: `flutter build apk --debug`

## Test

```bash
cd frontend
flutter analyze
flutter test        # headless: state machines, dead-reckoning maths, telemetry, screens at 320/360/411 dp
```

## Optional backend

The app does not need it. To try telemetry upload:

```bash
# Python API (port 8000)
python -m venv .venv && .venv/Scripts/activate
pip install -r backend/requirements.txt
cd backend && python -m uvicorn app.main:app --port 8000

# TypeScript engine (port 8080)
cd backend && npm install && npm run dev
```

On the Android emulator the host machine is reachable at `10.0.2.2`; the app already tries that address.

## Further reading

- [`frontend/README.md`](frontend/README.md) — app architecture
- [`backend/README.md`](backend/README.md) — services
- [`ml/README.md`](ml/README.md) — training pipeline
- [`cpp-core/README.md`](cpp-core/README.md) — native core
- [`docs/architecture/`](docs/architecture/) — design notes
