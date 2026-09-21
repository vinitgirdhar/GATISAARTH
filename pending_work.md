# GatiSaarth - Pending Work for SIH26168

## Purpose

This document captures the remaining technical work and validation evidence required to move **GatiSaarth** from its current implementation state toward the full technical endpoint described in **SIH26168: AI-ML based Intelligent Dead Reckoning system for seamless navigation**.

This is a **status and endpoint document**, not an implementation roadmap. It intentionally does not prescribe an order in which the work must be completed.

---

> [!IMPORTANT]
> ### 🚨 CRITICAL REMAINING WORK FOR SIH26168 FULL TECHNICAL ENDPOINT
> **ATTENTION AGENTS & DEVELOPERS**:
> The core AI/ML pipeline, EKF navigation filter, offline vector-tile road matcher, and 10 Hz mobile UI are **fully implemented, calibrated, and verified** (all 54 test suite checks passing).
> **DO NOT** rewrite or refactor completed navigation core or UI modules.
> 
> The following **5 tasks are still pending or partially satisfied** against the official SIH problem statement and must be addressed one by one:
> 
> 1. 🔴 **Task 1: Physical Vehicle Field Validation** (`docs/field_testing_protocol.md`)
>    - *Status*: **OPEN (`[ ]`)**
>    - *Requirement*: Real phone + real vehicle + real route + real GNSS-denied segment (tunnel/underpass) + measured drift.
> 2. 🟠 **Task 2: Consistent <10% DR Drift on 30s–60s Outages** (`iovnbd_outage_benchmark.json`)
>    - *Status*: **PARTIALLY SATISFIED (`[-]`)**
>    - *Requirement*: 10 s outage passes at 5.6% median drift; however, 30 s median is currently **10.7%** (exceeds 10% target). Must optimize EKF/AI along-track gating to consistently achieve $<10\%$ drift across 30 s and 60 s outages.
> 3. 🟡 **Task 3: Physical FOG-Specific 200 Hz IMU Stream Validation** (`codex_edge_200hz.json`)
>    - *Status*: **ENGINE CAPABILITY PROVEN / FOG STREAM PENDING (`[-]`)**
>    - *Requirement*: C++ engine executes 480k updates/s (P99 < 2.5 µs), but test was run with resampled IMU data. Needs validation against an actual Fiber Optic Gyro (FOG) IMU log stream.
> 4. 🟡 **Task 4: External IMU Hardware Interface Bench Test** (`codex_external_imu_replay.json`)
>    - *Status*: **SOFTWARE COMPATIBILITY PROVEN / HARDWARE PENDING (`[-]`)**
>    - *Requirement*: IO-VNBD ESP/CAN external IMU software replay passes cleanly; physical hardware bench integration (USB/CAN to edge engine) remains open.
> 5. 🔵 **Task 5: Lane-Level Accuracy Scope Defense & Heuristics** (`docs/evidence/road_graph_and_map_matching.md`)
>    - *Status*: **UNSATISFIED BUT EXPLICITLY SCOPED (`[ ]`)**
>    - *Requirement*: OSM lacks lane-level geometry. Maintain defensive documentation establishing that road/carriageway constraints are the state-of-the-art achievable scope without proprietary HD lane maps.

---

## 1. Current Status Summary

| Requirement | Current Status | Endpoint / Completion Condition |
|---|---|---|
| In-Vehicle Alignment & Calibration | **DONE** | Automatic pitch, roll, and yaw estimation relative to vehicle direction, including arbitrary phone mounting |
| Smartphone IMU processing | **DONE** | Continuous accelerometer/gyro/magnetometer processing with calibration, synchronization, and fault detection |
| Strapdown INS + 15-state ESKF | **DONE** | Continuous inertial navigation with GNSS/IMU fusion support |
| NHC / ZUPT / ZARU | **DONE** | Vehicle-motion constraints and stationary corrections active in navigation filter |
| GNSS outage detection | **DONE** | Automatic detection of stale, anomalous, or unavailable GNSS |
| GNSS -> Dead Reckoning handover | **DONE** | State-preserving transition with continuous navigation output |
| Dead Reckoning -> GNSS recovery | **DONE** | Smooth Kalman re-alignment and visual convergence without normal position jumps |
| Real-Time Navigation Interface | **DONE** | Continuous vehicle marker and navigation state during outage/recovery |
| AI forward-speed estimation | **DONE (v3.1)** | ML forward speed actively fed into EKF via `NavigationEngine.onAiSpeed` & `NavigationFilter.updateForwardSpeed` (`codex_ai_ablation_*.json`) |
| AI/statistical vibration filtering | **DONE (v3.1)** | Model/statistical disturbance handling actively scales NHC/ZUPT/ZARU noise & suspends ZARU on shock (`codex_ai_ablation_*.json`) |
| AI-based GNSS+INS fusion | **DONE (v3.1)** | Neural fusion confidence actively scales GNSS measurement noise ($1/\sqrt{\text{trust}}$) in `NavigationEngine.onFusionConfidence` |
| Real offline road graph | **DONE (v3.1)** | Delhi NCR and Maharashtra road graphs extracted from offline PMTiles packs (`docs/evidence/road_graph_coverage.json`) |
| Live map matching | **DONE (v3.1)** | HMM matcher fed directly by `LiveSessionController` via `NavigationEngine.setRoadGraph` with junction continuation logic |
| Carriageway/topological constraints | **DONE (v3.1)** | Demonstrated against real Delhi, Mumbai, and UK OSM networks (`docs/evidence/real_road_map_matching.json`, `docs/evidence/iovnbd_real_map_matching.json`) |
| Lane-level accuracy | ⚠️ **UNSATISFIED (EXPLICITLY SCOPED)** | Literal lane-level accuracy not satisfied; explicitly scoped to road/carriageway-level constraint due to lack of lane geometry in OSM map data (`docs/evidence/road_graph_and_map_matching.md` §P8) |
| IO-VNBD training | **DONE (v3.1)** | 144 real IO-VNBD files fetched via `fetch_iovnbd.py` with verified SHA-256; models retrained on real data |
| IO-VNBD testing + position plots | **DONE (v3.1)** | Held-out inference evaluated and position plots generated (`ml/evaluation/plots/11_iovnbd_position_*.png`, `11_iovnbd_position_drift.json`) |
| Real vehicle validation | ❌ **OPEN / PENDING** | Operational field-testing protocol & in-app logging tooling established in `docs/field_testing_protocol.md`; physical drive pending |
| Real quantitative drift evidence (<10% drift) | ⚠️ **PARTIALLY SATISFIED** | Demonstrated on 10 s outages (5.6% median) and cruising runs; 30 s median is 10.7% (slightly exceeds 10% target); consistent <10% across 30–60 s outages remains open (`docs/evidence/iovnbd_outage_benchmark.json`) |
| External IMU validation | ⚠️ **ALGORITHM COMPATIBILITY DONE / HARDWARE PENDING** | Replayed through engine using vehicle ESP/CAN IMU proxy (`docs/evidence/codex_external_imu_replay.json`); physical external IMU hardware bench pending |
| ~200 Hz edge validation | ⚠️ **ENGINE CAPABILITY DONE / FOG STREAM PENDING** | Standalone C++ engine benchmarked at ~480k updates/s with P99 < 2.5 µs (`docs/evidence/codex_edge_200hz.json`); physical FOG-specific IMU stream validation remains open |
| C++ edge engine architecture | **DONE (v3.1)** | Standalone C++17 engine with CMake build, ring buffers, and test suite in `cpp-core/` |
| On-device TFLite inference infrastructure | **DONE (v3.1)** | TFLite models executed locally on Android device with fallback and diagnostics |

---

## 2. Requirement 1: In-Vehicle Alignment & Calibration

### Status

**DONE**

### Current capabilities

- Automatic phone-to-vehicle coordinate alignment.
- Pitch and roll derived from gravity estimation.
- Yaw estimated relative to vehicle forward direction using motion/GNSS information.
- Full phone-to-vehicle rotation handling.
- Automatic detection of significant mount movement.
- Recalibration after mount displacement.
- Stationary IMU bias calibration.
- Magnetometer calibration.

### Endpoint

A phone can be dashboard-mounted or placed in a holder without requiring manual alignment, and the navigation engine can determine the vehicle-relative orientation automatically.

---

## 3. Requirement 2: AI Speed & Vibration Filter

### Status

**DONE (v3.1)**

### Current capabilities

- **Active Forward-Velocity Measurement**: The lightweight neural speed estimator (`speed_estimator.tflite`) runs on-device and is an active measurement update in the navigation estimation loop:
  ```text
  IMU (10 Hz window)
    -> TFLite speed model
    -> forward velocity + uncertainty
    -> NavigationEngine.onAiSpeed (gated by AiSpeedGate)
    -> NavigationFilter.updateForwardSpeed
  ```
  During GNSS availability, predictions are continuously cross-graded against Doppler speed to establish trust; during GNSS outages, passing predictions directly constrain along-track filter drift.
- **Confidence Calibration & ZUPT Prior**: Replaced the uncalibrated $1/(1+\sigma^2)$ formulation with a Gaussian Error Tolerance Cumulative Distribution Function (CDF):
  $$\text{Confidence} = \text{erf}\left(\frac{\Delta v_{\text{tol}}}{\sqrt{2}\sigma}\right)$$
  with operational tolerance $\Delta v_{\text{tol}} = 2.2\text{ m/s}$ ($8.0\text{ km/h}$), yielding $\ge 80\%$ confidence under operational driving conditions ($\sigma \le 1.6\text{ m/s}$). When stationary ($\text{stdNormA} < 0.40$ and $\text{meanNormG} < 0.25$), physical stillness triggers the ZUPT prior, clamping speed to $0.0\text{ m/s}$ with **98% confidence**.
- **Gravity Leveling Pre-Filter**: When phone-to-vehicle mount calibration is pending, instantaneous or settled gravity orientation (`_engine.upInPhone`) levels raw acceleration into the vehicle FLU frame ($a_z \approx 9.81\text{ m/s}^2$, $a_x = \|\mathbf{a}_{\text{horiz}}\|, a_y = 0.0$), preventing $-17\sigma$ out-of-distribution feature errors on tilted/upright mounts and emulators.
- **AI/Statistical Disturbance Filtering**: Implemented in `NavigationEngine.onDisturbance()`. Actively identifies road vibration, bumps, and potholes, scaling measurement noise ($\sigma$) for Non-Holonomic Constraints (NHC), ZUPT, and ZARU. During severe shock events, ZARU updates are suspended to prevent corrupted gyro integration.
- **Evidence**: Validated on real IO-VNBD trips in `docs/evidence/codex_ai_ablation_*.json`. On difficult drive `Vtb01`, enabling statistical disturbance handling combined with gated speed estimation reduced median 60 s outage drift from 133.8% to 21.9% (error from 834 m down to 162 m).

---

## 4. Requirement 3: Advanced Map Matching & Kinematic Constraints

### Kinematic Constraints

**Status: DONE**

Navigation filter includes vehicle-frame non-holonomic constraints (NHC), zero-velocity updates (ZUPT), and zero-angular-rate updates (ZARU), with dynamic disturbance scaling.

### Real Map Matching & Road Graphs

**Status: DONE (v3.1)**

- **Offline Vector-Tile Road Extraction**: Rather than shipping static, fragile JSON graphs, `tile_roads.dart` and `road_noding.dart` construct the live `RoadGraph` directly from the installed offline vector-tile map packs (`.pmtiles` format).
- **Live HMM Matcher**: Handed directly to `NavigationEngine.setRoadGraph` via `LiveSessionController`. Edges of the same road continuing through junctions within 25° pool probability (`MapMatchConfig.continuationDeg`) to eliminate false rivalries.
- **Road-Locked Dead Reckoning**: `RoadFollower` and `RoadConstraint` constrain the vehicle marker to the active carriageway during GNSS outages.
- **Evidence**:
  - Graph coverage measured in `docs/evidence/road_graph_coverage.json` (Delhi NCR: 38,969 drivable km, Mumbai: 16,424 km, etc.).
  - Matching evaluated on real streets in `docs/evidence/real_road_map_matching.json` and real IO-VNBD UK roads in `docs/evidence/iovnbd_real_map_matching.json`. Details in `docs/evidence/road_graph_and_map_matching.md`.

---

## 5. Requirement 4: GNSS+INS Fusion Engine

### Conventional GNSS+INS Fusion

**Status: DONE**

A 15-state Error-State Kalman Filter is present with GNSS/IMU integration, uncertainty handling, NIS gating, and adaptive GNSS covariance logic.

### AI-based fusion

**Status: DONE (v3.1)**

- Implemented via `NavigationEngine.onFusionConfidence(FusionConfidence)`.
- Neural fusion confidence dynamically scales GNSS horizontal and velocity measurement noise by $1/\sqrt{\text{trust}}$. Stale or degraded neural confidence safely defaults to unit scaling (1.0).
- Fully integrated into the live filter update loop in `NavigationEngine.onGnss()`.

---

## 6. Requirement 5: Seamless GNSS Deficit Handler

### Status

**DONE**

### Current capabilities

- GNSS outage detection.
- State-preserving transition into dead reckoning.
- Continuous navigation output during outage.
- GNSS reacquisition mode.
- Kalman-based reconnection.
- UI easing to avoid visible snapping under normal discrepancies.

### Endpoint

The application must continuously operate through:

```text
GNSS-aided INS
      -> GNSS blackout
      -> Dead Reckoning
      -> GNSS recovery
      -> GNSS-aided INS
```

with no normal visible freeze or position discontinuity.

---

## 7. Requirement 6: Real-Time Navigation Interface

### Status

**DONE**

### Current capabilities

- Smooth live vehicle marker.
- Navigation continues during simulated/handled GNSS outage.
- Navigation mode/state displayed.
- Dead-reckoning trail/visual state available.
- GNSS recovery transition is visually eased.
- Developer diagnostics expose sensor and navigation state.

### Endpoint

The user sees uninterrupted navigation while GNSS is unavailable and during recovery.

---

## 8. IO-VNBD Dataset Requirement

### Status

**DONE (v3.1)**

### Accomplishments

- **Real Dataset Ingestion**: 144 real IO-VNBD files downloaded and verified against Git-LFS SHA-256 hashes using `ml/src/dataset/fetch_iovnbd.py` (426 MB total data).
- **Leak-Free Splitting & Retraining**: Trip-level split applied to train, validate, and test four neural models (`speed_estimator`, `motion_quality`, `vibration_classifier`, `gnss_anomaly_detector`).
- **Export & Deployment**: Exported to ONNX and TFLite (`speed_estimator.tflite` deployed into frontend assets with updated v3.1 metadata).
- **Held-Out Position Plots & Metrics**: Generated held-out inference trajectory and position drift plots in `ml/evaluation/plots/11_iovnbd_position_*.png` and documented in `ml/evaluation/metrics/11_iovnbd_position_drift.json`.

---

## 9. Lane-Level Accuracy

### Status

**DOCUMENTED SCOPE (v3.1)**

### Validated Scope Statement

As detailed in [`docs/evidence/road_graph_and_map_matching.md` §P8](file:///c:/Users/vidhy/Downloads/gathisarthi/docs/evidence/road_graph_and_map_matching.md), OpenStreetMap data carries no explicit lane count, lane geometry, or lane index attributes, and the IO-VNBD benchmark contains no ground-truth lane markers.

Consequently, **lane-level accuracy is not claimed**. The system is validated and defensibly claimed for **road-level and carriageway-level constrained dead reckoning**:
- One-way carriageways are strictly honoured.
- Drive-on-the-left carriageway pairing prevents snapping across medians.
- True lane-level positioning would require high-definition (HD) lane-marked vector maps and camera/vision sensors.

---

## 10. Real-World Vehicle Validation

### Status

**PROTOCOL & TOOLING COMPLETE (v3.1)**

### Current state

Physical vehicle road tests cannot be executed by software alone. To satisfy this requirement, a complete, reproducible operational guide and tooling have been established in [`docs/field_testing_protocol.md`](file:///c:/Users/vidhy/Downloads/gathisarthi/docs/field_testing_protocol.md):
- In-app **Record Drive** button logs full high-rate IMU, GNSS, barometer, and driver markers to structured JSONL files.
- Built-in **Tunnel Test** and **Urban Canyon** buttons enable repeatable in-vehicle GNSS blackout experiments.
- Post-drive evaluation tools (`score_drive_test.dart`) calculate exact horizontal position error and drift percentage against the 10% SIH threshold.

---

## 11. Dead-Reckoning Performance Benchmark

### SIH target

Positional drift must remain below **10% of total distance travelled** during GNSS blackout.

### Status

**PARTIALLY SATISFIED / CONDITIONALLY PASSES (v3.1)**

Documented in `docs/evidence/iovnbd_outage_benchmark.json` and `docs/evidence/iovnbd_engine_and_map_evidence.md` against Racelogic VBOX ground truth across 32 drives:
- **10 s outage**: Median drift **5.6%** (17 of 21 scored trips under 10% — **PASS**).
- **30 s outage**: Median drift **10.7%** (10 of 21 scored trips under 10% — **exceeds 10% target**).
- **60 s outage**: Best cruising trips achieve **3.7% (Vw2)**, **6.6% (Vw16a)**, and **8.0% (Vw14b)**.
- Gated neural speed + disturbance handling significantly reduces along-track drift during extended outages (`codex_ai_ablation_*.json`).
- *Verdict*: Conditionally passes for 10 s outages and straight cruising runs; consistent <10% performance across all target 30–60 s outage scenarios remains an open validation item.

---

## 12. External IMU / Edge-Deployable Engine

### Status

**ALGORITHM COMPATIBILITY DONE / HARDWARE PENDING (v3.1)**

Demonstrated and verified using IO-VNBD vehicle ESP/CAN 10 Hz external IMU data replayed directly through the navigation engine in `docs/evidence/codex_external_imu_replay.json`. Physical bench integration with external IMU hardware remains open.

---

## 13. ~200 Hz Edge Requirement

### Status

**ENGINE CAPABILITY DONE / FOG STREAM PENDING (v3.1)**

Standalone C++17 engine benchmarked with a high-rate 200 Hz stream in `docs/evidence/codex_edge_200hz.json`:
- **Throughput**: ~480,000 updates/second.
- **P99 Latency**: < 2.5 µs per update.
- Zero buffer overflow or memory instability.
- *Note*: While the engine's compute capability easily handles 200 Hz, validating a physical stream specifically from a Fiber Optic Gyro (FOG) IMU remains open.

---

## 14. On-Device Execution Requirement

### Status

**DONE (v3.1)**

All AI models execute locally on-device using TFLite:
- Verified on Google Pixel 9 (`emulator-5554`) in `integration_test/release_smoke_test.dart`.
- TFLite speed estimator initializes, loads weights, runs inference, and verifies outputs against IO-VNBD parity fixtures with zero network dependency.

---

## 15. Full Technical Endpoint

The final GatiSaarth system should be able to demonstrate the following end-to-end behavior:

```text
                  GNSS
                    |
                    v
IMU -> TimeSync -> Alignment -> AI/ML Processing
                    |                 |
                    |                 +--> Forward Speed
                    |                 +--> Vibration / Motion Quality
                    |                 +--> Fusion Confidence
                    |                         |
                    +-------------------------+
                              |
                              v
                    GNSS + INS Fusion
                         (ESKF/UKF)
                              |
                 +------------+------------+
                 |                         |
              GNSS OK                GNSS LOST
                 |                         |
                 |                 Dead Reckoning
                 |                         |
                 |                INS + AI speed
                 |                + constraints
                 |                + map matching
                 |                         |
                 +------------+------------+
                              |
                              v
                    Continuous 10 Hz State
                              |
                              v
                     Real-Time Navigation UI
```

In addition, the navigation engine must have an edge-deployable form capable of processing external high-rate IMU data around the stated 200 Hz requirement.

---

## 16. Final Gap Checklist

### Completed (v3.1 Deliverables)

- [x] Automatic phone-to-vehicle alignment
- [x] Smartphone IMU ingestion
- [x] Sensor synchronization
- [x] Sensor calibration and fault detection
- [x] Strapdown INS
- [x] 15-state ESKF
- [x] NHC
- [x] ZUPT / ZARU
- [x] GNSS quality/integrity handling
- [x] GNSS -> DR transition
- [x] DR -> GNSS recovery
- [x] 10 Hz mobile navigation output
- [x] Real-time navigation interface
- [x] On-device TFLite inference infrastructure
- [x] Standalone C++ edge-engine architecture
- [x] Active ML forward-speed measurement inside EKF (`NavigationFilter.updateForwardSpeed`, `NavigationEngine.onAiSpeed`)
- [x] AI/statistical vibration filtering in navigation pipeline (`NavigationEngine.onDisturbance`, noise scaling, shock hold)
- [x] Active AI-based GNSS+INS fusion (`NavigationEngine.onFusionConfidence` scaling GNSS covariance)
- [x] Populate real Delhi NCR road graph (38,969 drivable km, `docs/evidence/road_graph_coverage.json`)
- [x] Populate real Maharashtra road graphs (Mumbai, Pune, Nagpur, Nashik, Chhatrapati Sambhajinagar)
- [x] Activate live map matching using on-device tile road graphs (`LiveSessionController` -> `setRoadGraph`)
- [x] Demonstrate road/topological constraints on real road data (`real_road_map_matching.json`, `iovnbd_real_map_matching.json`)
- [x] Download and integrate actual IO-VNBD data (144 verified CSVs via `fetch_iovnbd.py`)
- [x] Train/evaluate models on actual IO-VNBD data (`speed_estimator`, `motion_quality`, `vibration_classifier`)
- [x] Produce required IO-VNBD preliminary model results and position plots (`11_iovnbd_position_*.png`, `11_iovnbd_position_drift.json`)
- [x] Establish real ground-truth comparison (Racelogic VBOX ground truth in `iovnbd_outage_benchmark.json`)
- [x] Field-testing protocol and in-app drive logging tooling established (`docs/field_testing_protocol.md`)
- [x] AI Speed Estimator Confidence Calibration (Gaussian Error Tolerance CDF replacing uncalibrated variance formula; calibrated to $\ge 80\%$ in operational driving and 98% in stationary ZUPT)
- [x] Gravity leveling pre-filter in live navigation session (preventing $-17\sigma$ out-of-distribution feature errors on tilted/upright phone mounts and emulators)
- [x] UI visual refinement & card blending (dark surface `#1C1C1E` blending with 8% white hairline borders across Home, Sensors, Engine Spec, and Diagnostics)
- [x] Offscreen scroll item rendering fix (preventing ticker stalls and invisible items in `EngineSpecScreen` and `OfflineMapsScreen`)

### Actionable Remaining Tasks (Priority Order for Agents & Developers)

The following items are the only remaining tasks required to reach the full SIH26168 endpoint. When starting work, address them one by one in this order:

#### 1. 🔴 Task 1: Physical Vehicle Field Validation (Highest Priority)
- **Problem**: Software simulation and dataset replay are complete, but physical vehicle road data is required to substantiate real-world deployment.
- **Protocol**: Follow [`docs/field_testing_protocol.md`](file:///c:/Users/vidhy/Downloads/gathisarthi/docs/field_testing_protocol.md).
- **Execution Steps**:
  1. Mount an Android phone (Pixel/Galaxy) running GatiSaarth in a vehicle dashboard cradle.
  2. Start a drive in an urban or highway corridor containing a known GNSS-denied segment (tunnel, underpass, or dense urban canyon).
  3. Press **Record Drive** in the app to capture the raw multi-sensor JSONL stream.
  4. Use the in-app **Tunnel Test** trigger if testing in an open corridor, or drive through a physical tunnel.
  5. Run `flutter test test/nav/score_drive_test.dart` against the exported log to calculate horizontal error and drift %.

#### 2. 🟠 Task 2: Consistent <10% DR Drift Optimization across 30s–60s Outages (High Priority)
- **Problem**: 10 s median drift is 5.6% (passes), but 30 s median drift across 21 IO-VNBD trips is **10.7%**, which slightly exceeds the 10% requirement.
- **Target Files**:
  - [`frontend/lib/core/nav/ai/ai_speed_gate.dart`](file:///c:/Users/vidhy/Downloads/gathisarthi/frontend/lib/core/nav/ai/ai_speed_gate.dart)
  - [`frontend/lib/core/nav/filter/navigation_filter.dart`](file:///c:/Users/vidhy/Downloads/gathisarthi/frontend/lib/core/nav/filter/navigation_filter.dart)
  - [`frontend/lib/core/nav/nav_config.dart`](file:///c:/Users/vidhy/Downloads/gathisarthi/frontend/lib/core/nav/nav_config.dart)
- **Execution Steps**:
  1. Re-evaluate `test/nav/iovnbd_outage_benchmark_test.dart` with tuned along-track innovation damping and tighter NHC lateral constraints.
  2. Increase AI forward-speed Kalman weight during stable cruising segments while retaining physics sanity bounds.
  3. Re-run `iovnbd_eval.py` to bring 30 s median drift consistently below 10.0%.

#### 3. 🟡 Task 3: Physical FOG-Specific 200 Hz IMU Stream Validation (Medium Priority)
- **Problem**: The C++ engine benchmark (`codex_edge_200hz.json`) achieved 480k updates/s with resampled vehicle data, but lacks validation on a genuine Fiber Optic Gyro (FOG) IMU data stream.
- **Target Files**:
  - [`cpp-core/tools/bench_200hz.cpp`](file:///c:/Users/vidhy/Downloads/gathisarthi/cpp-core/tools/bench_200hz.cpp)
  - [`cpp-core/tools/replay_external_imu.cpp`](file:///c:/Users/vidhy/Downloads/gathisarthi/cpp-core/tools/replay_external_imu.cpp)
- **Execution Steps**:
  1. Obtain or synthesize a verified FOG noise model / high-precision optical gyro dataset.
  2. Feed the 200 Hz FOG log stream through `replay_external_imu`.
  3. Validate bias stability and angular random walk (ARW) performance, generating `docs/evidence/codex_fog_200hz.json`.

#### 4. 🟡 Task 4: External IMU Hardware Interface Bench Test (Medium Priority)
- **Problem**: Vehicle CAN/ESP replay proves algorithmic capability, but a physical hardware bench interface has not been connected.
- **Target Files**:
  - [`cpp-core/src/engine/nav_engine.cpp`](file:///c:/Users/vidhy/Downloads/gathisarthi/cpp-core/src/engine/nav_engine.cpp)
  - Backend/Edge serial ingestion scripts.
- **Execution Steps**:
  1. Implement a serial/USB or CAN bus socket reader for external IMU devices.
  2. Stream live external sensor frames into `NavEngine::addExternalImuFrame()`.
  3. Document latency and synchronization in `docs/evidence/codex_hardware_bench.json`.

#### 5. 🔵 Task 5: Lane-Level Accuracy Scope Defense & Lateral Heuristics (Medium Priority)
- **Problem**: The SIH problem statement mentions "maintaining lane-level accuracy", which OSM data cannot provide without proprietary lane-level HD maps.
- **Target Files**:
  - [`docs/evidence/road_graph_and_map_matching.md`](file:///c:/Users/vidhy/Downloads/gathisarthi/docs/evidence/road_graph_and_map_matching.md) §P8
  - [`frontend/lib/core/nav/map/road_constraint.dart`](file:///c:/Users/vidhy/Downloads/gathisarthi/frontend/lib/core/nav/map/road_constraint.dart)
- **Execution Steps**:
  1. Maintain defensible justification: OSM network models road centerlines; lane-level geometry is unavailable in open-source mapping.
  2. Implement road-width / lane-count heuristic (e.g. offsetting vehicle marker based on turn lane cues or road segment width tags where OSM `lanes=*` exists).
  3. Document bounded lateral uncertainty bounds (< 1.75 m half-lane radius).

---

## 17. Definition of "Complete"

For the implementation to be considered complete against the technical endpoint of SIH26168, the remaining items above must not exist only as code stubs, architecture diagrams, synthetic placeholders, or simulated demonstrations. The relevant AI models, map constraints, datasets, and edge/mobile behaviors need to be **executed and evidenced with reproducible results**.

The strongest completion evidence is therefore:

1. **Working mobile application** showing seamless GNSS/DR navigation.
2. **AI models running locally** for forward velocity and required disturbance/fusion behavior.
3. **Real offline OSM road network** actively constraining navigation.
4. **IO-VNBD model training/testing results and position plots.**
5. **Physical vehicle GNSS-denied test results** with quantified drift.
6. **External-IMU edge-engine validation around 200 Hz.**
7. **Clear evidence for the lane-level requirement or a precisely documented validated scope.**
