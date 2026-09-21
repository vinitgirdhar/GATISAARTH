# GatiSaarth v3 — implementation plan (v3.0 development → v3.1 release)

Source of truth for scope: [`pending_work.md`](../../pending_work.md) (SIH26168 gap list).
Previous release: **v2.0**. Development from `pending_work.md` is tracked as **v3.0.x**; the finished
update ships as **v3.1** (app `3.1.0+31`, models `v3.1.0`, notebook `v3.1`).

## 0. A fact that shaped the plan: the IO-VNBD folder holds pointers, not data

`IO-VNBD_DATASET/IO-VNBD-master` was fetched without Git LFS: all 564 CSV, 161 JPG and both ZIP files are
130-byte LFS *pointer* files (for example `S-M.csv` says `size 19798721`). The real objects are public and
are served by `media.githubusercontent.com/media/onyekpeu/IO-VNBD/master/<path>`; a real pair was fetched
and its SHA-256 matched the pointer's `oid`. So "integrate the dataset" starts with a verified fetch tool
(`ml/src/dataset/fetch_iovnbd.py`) that reads the pointers in that folder, downloads the real files into the
git-ignored `ml/data/raw/IO-VNBD_repo/` (the path the existing master notebook already scans) and checks
size + SHA-256 for every file. Nothing in `IO-VNBD_DATASET/` is modified.

Real data layout (checked): `S-*.csv` smartphone (10 Hz IMU + 1 Hz GPS, 24 columns, accelerometer
m/s², gyro rad/s, magnetometer µT), `V-*.csv` vehicle/VBOX (10 Hz, 29 columns: VBOX GPS lat/lon,
velocity km/h, heading, wheel speeds, yaw rate, CAN longitudinal/lateral acceleration, brake, steering).
The synchronised sets pair the two, so the VBOX gives real ground truth for speed *and* position.

## 1. Where each pending item stands (verified against the code, 2026-09-21)

| # | Item (`pending_work.md`) | State now | Depends on |
|---|---|---|---|
| — | Alignment, IMU ingest, sync, calibration/faults, INS, 15-state ESKF, NHC/ZUPT/ZARU, GNSS quality, GNSS↔DR handover, 10 Hz output, UI, TFLite infra, C++ architecture | **Done** | — |
| — | Marker held to real roads during outages (tile-derived graph, `RoadFollower`) — *new since the gap list was written* | **Done (v2.x)**, marker path only | — |
| P9 | Download + integrate real IO-VNBD | **Not done** → fetch tool + ingestion | — (foundation) |
| P10 | Train / validate / test the models on real IO-VNBD | **Not done** | P9 |
| P11 | Held-out inference results + position plots | **Not done** | P10 |
| P1 | ML forward speed as an EKF measurement | **Partial**: model runs on the phone, `NavigationFilter.updateForwardSpeed` exists, engine never receives the model output | P10 (model), engine port |
| P2 | AI/statistical vibration + disturbance filtering | **Not done**: only thresholds and process noise | P10, P1's port |
| P3 | AI in the GNSS+INS fusion loop | **Not done**: deterministic quality score only | P10, P1's port |
| P4/P5 | Real Delhi NCR / Maharashtra road graphs | **Partial**: graphs are built on the phone from the installed packs; the engine's matcher is still handed an empty graph | packs |
| P6 | Live map matching in the engine | **Not done** (matcher exists, `MapMatchConfig.enabled = false`) | P4/P5 |
| P7 | Topological / carriageway constraints demonstrated on real roads | **Partial / unverified** | P6 |
| P8 | Lane level | **Not achieved** → document the validated scope, claim nothing more | P7 |
| P13/P14 | Real ground truth + <10 % drift evidence | **Not done** → IO-VNBD replay through the *Dart engine*, VBOX truth | P9, P1–P3, P6 |
| P15 | External-IMU validation | **Not done** | C++ harness, P9 |
| P16 | ~200 Hz edge benchmark | **Not done** | C++ harness |
| P12 | Physical vehicle GNSS-denied test | **Not doable by software alone** → protocol + tooling, needs the user's vehicle | P14 |

## 2. Dependency graph and order

```
P9 fetch+ingest ──► P10 train ──► P11 plots ───────────────┐
                        │                                   ▼
                        ├──► P1 AI speed ──► P2 ──► P3 ──► P13/P14 IO-VNBD replay in Dart engine
                        │                                   ▲
P4/P5 graphs ──► P6 map matching ──► P7 constraints ────────┤
                                                            │
C++ harness ──► P15 external IMU ──► P16 200 Hz ────────────┘  ──► P8 scope + P12 protocol ──► v3.1
```

Order (foundation first, independent streams in parallel):

1. **Stream A — data and models** (P9 → P10 → P11): fetch tool, real-data ingestion in the *existing* master
   notebook, trip-level leak-free splits, retrain the four models, held-out metrics, trajectory plots; then
   export ONNX/TFLite and deploy assets (v3.1.0 metadata).
2. **Stream B — engine AI path** (P1 → P2 → P3), built against the fixed model I/O contract so it does not
   wait for the retrain: ports + gates + noise scaling + controller wiring + unit tests; turned on only when
   the IO-VNBD replay shows it helps (the rule already written into `AiConfig`).
3. **Stream C — roads** (P4/P5 → P6 → P7): hand the tile-derived graph to `NavigationEngine`, enable the HMM
   matcher, export graph artifacts for Delhi NCR and Maharashtra with statistics, real-road tests.
4. **Stream D — edge** (P15, P16): C++ engine builds with CMake + MSVC, a CSV/stream harness for an external
   IMU, a 200 Hz throughput/latency benchmark.
5. **Join — evidence** (P13/P14): convert IO-VNBD synchronised trips to drive logs, run the outage benchmark
   in the Dart engine with AI/map on and off, table + plots, all against VBOX truth.
6. **Close** (P8, P12, versioning, verification): lane-level scope statement, field-test protocol, bump to
   3.1, full test suite, analyzer, ML pipeline re-run, APK build, install and smoke test on the emulator.

## 3. Rules for every feature

Implement → test (unit + real-data where the data exists) → run the full suite to prove nothing regressed →
tick it in `pending_work.md` with the version and the evidence path → next. Nothing is marked done on
simulation alone; what stays undemonstrated (physical vehicle, real lane truth) is written down as such.
