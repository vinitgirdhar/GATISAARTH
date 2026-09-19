# GatiSaarth — Navigation Engine Evolution Plan

Audit date: 2026-09-19 · Baseline state: `flutter analyze` = 1 warning, `flutter test` = 113 pass.

This is the §85 pre-implementation package: audit, gap analysis, dependency graph, target
architecture, data/sensor/ML/EKF/map designs, test strategy, migration plan. Implementation
follows in P0 → P4 order, not all at once.

---

## 1. Current architecture audit

### 1.1 What actually executes on a phone

```
main.dart
 └─ app_widget.dart  (lifecycle: pause/resume sensors+GPS on background)
     └─ LiveSessionScope  ──provides──▶  LiveSessionController   ◀── the entire nav engine
         ├─ /boot      BootScreen + BootSequence (4 real stages, poll-budgeted)
         ├─ /          DashboardScreen      (observer only)
         ├─ /nav       ActiveNavScreen      (observer only)
         └─ /diag      DiagnosticsScreen    (reads DemoNavigationRepository — not live)
```

`LiveSessionController` (683 LOC, `features/navigation_ui/presentation/controllers/`) owns:
sensor subscription, GNSS state, dead reckoning, ML feed, uncertainty, anomalies, telemetry,
position easing, last-position cache. It is a `ChangeNotifier` living in the **presentation**
layer. Both screens observe it; neither computes navigation. That single-source-of-truth rule
(§72) is already honoured — the problem is *what* the single source computes, not where it lives.

### 1.2 Live subsystems, as built

| Subsystem | File | What it really does |
|---|---|---|
| Sensor driver | `core/platform/hardware/sensor_mobile.dart` | Accel at `gameInterval` (~50 Hz) drives frames; gyro/mag at `uiInterval` (~15 Hz) **latched, not timestamped**; barometer at `normalInterval`. Emits a positional `List<double>` of 12 slots. |
| Location | `core/platform/location/live_location_service.dart` + `geolocator_gateway.dart` | 7-state machine, 1 Hz `bestForNavigation`, `staleAfter` 6 s, error backoff x2 to x16, MSL altitude. Solid. |
| Alignment | `core/platform/hardware/vehicle_alignment_engine.dart` | alpha=0.98 LPF gravity, then pitch/roll only. **No yaw.** NHC = hard-zero lateral/vertical (car) or fixed 0.35/0.5 attenuation (two-wheeler). |
| Heading | `LiveSessionController._updateHeading` | `atan2(-mx, my)`, complementary blend 0.45. **Flat-phone assumption, no tilt compensation, no gyro integration, no hard/soft-iron correction.** |
| Speed | `features/ai_motion/data/datasources/ml_speed_estimator.dart` | Singleton. Tries `Interpreter.fromAsset(speed_estimator_int8.tflite)`; the asset is a **130-byte Git-LFS pointer**, so the load always fails and the rule-based `_kinematicFallbackSpeed` runs. Variance-only stationary gate. |
| Dead reckoning | `LiveSessionController._advanceMotion` / `_integrate` | `distance = speed x dt` projected on the magnetometer heading; flat-earth lat/lon Euler step. No velocity state, no attitude state, no bias state. |
| Uncertainty | `features/navigation_engine/domain/uncertainty_model.dart` | Closed form: `accuracy_at_loss + 0.05 x distance + 0.15 x seconds`, linear map to confidence. Model parameters, not covariance. |
| Anomalies | `LiveSessionController._detectAnomaly` | `abs(norm(a) - 9.81) > 4.5` gives speed breaker, `> 7.0` gives pothole, 2.5 s refractory plus haptic. |
| Thermal | `device_hardware_service.dart` + `MainActivity.kt` | Real battery temperature via `ACTION_BATTERY_CHANGED`. `thermalBiasCorrection` is a **polynomial with invented coefficients** — computed, displayed, but never applied to any sensor. |
| Maps | `core/platform/maps/offline_tile_provider.dart` | Bundled tiles, then disk cache, then optional network with a circuit breaker. Works offline. Raster only. |
| Telemetry | `backend_telemetry_client.dart` | Candidate-URL probing, exponential backoff, fully optional. |

### 1.3 Components that exist but are **not connected**

| Component | Size | Status |
|---|---|---|
| `cpp-core/` | 450 LOC total, mostly headers | Stubs. `idr_api.cpp` is 75 lines. No UKF body, no mechanization body. Dart side: `ffi_mobile.dart` is `class FfiMobile extends FfiStub {}`. Zero `DynamicLibrary` calls anywhere in `lib/`. |
| `ml/` TFLite exports | 130 B each | Git-LFS pointer files. `speed_estimator.onnx` (264 KB) and `vibration_classifier.onnx` (95 KB) **are real**. |
| `maps/processed_graphs/` | `{"edges": []}` | Empty. No road graph exists. |
| `backend/src/core/kalmanFilter.ts` | — | Server-side, never reached by the app. |
| `simulation/` | Python | Offline scripts, not wired to the app. |
| `mock_data.dart` + `demo_navigation_repository.dart` | — | Feeds `DiagnosticsScreen` only; labelled "illustrative demo values" in the UI. |

### 1.4 Dead Dart files (never imported)

26 of 80. `core/di/injection.dart` (empty `ServiceContainer`), `core/errors/*`,
`core/storage/local_storage.dart`, `core/utils/math_utils.dart`, `core/utils/time_formatter.dart`,
all 9 files under `features/data_acquisition/**` (a parallel abandoned sensor stack),
`features/ai_motion/domain/usecases/*`, `nav_engine_controller.dart`,
`handle_gnss_outage_usecase.dart`, `map_view.dart`, `map_view_controller.dart`,
`speedometer.dart`, `custom_compass.dart`, `ffi_mobile.dart`, `ffi_web.dart`, `sensor_web.dart`.

This matters for §82: `features/data_acquisition/**` is a *duplicate* sensor abstraction. The new
sensor layer replaces it rather than becoming a third one.

### 1.5 Honest assessment

The app is a well-built, honestly-labelled **heuristic** dead-reckoning demo with an
excellent GNSS state machine and a disciplined no-fake-data culture. It is not yet a
navigation *estimator*: there is no state vector, no covariance, no attitude filter, no
bias estimation, no measurement gating, and no map. The published drift number
(`ml/evaluation/metrics/08_gnss_outage_benchmark_results.json`, `outage_30s_drift_reduction_pct: -309.0`)
says the current AI path is **worse** than classical DR on its own synthetic set.

---

## 2. Feature gap analysis

Legend: DONE / PART / NONE

| § | Requirement | State | Gap |
|---|---|---|---|
| 3 | Sensor abstraction with metadata | NONE | Positional `List<double>`; no sequence number, no accuracy, no validity, no capability detection. |
| 4 | Timestamp synchronization | NONE | Gyro/mag latched from the accel callback, so up to 66 ms stale, attributed to the accel timestamp. No drop accounting, no rate estimation. |
| 5 | Calibration subsystem | NONE | Gravity LPF only. No bias/scale/misalignment estimation, no persistence, no quality score. |
| 6 | Phone-to-vehicle alignment | PART | Pitch/roll only. **Yaw offset unknown** — the single largest DR error source today. |
| 7 | Vehicle-dynamics classifier | PART | 4-level vibration RMS bucket only. |
| 8 | Neural velocity estimation | PART | Code path and trained ONNX exist; the TFLite asset is an LFS pointer, so it has never run on-device. |
| 9 | Model quality gating | PART | Warm-up frames plus a stationary gate. No distribution check, no latency gate, no physics-disagreement gate, no separate confidence/contribution. |
| 10 | Strapdown INS | NONE | No quaternion, no velocity state, no mechanization. |
| 11 | Error-state Kalman filter | NONE | None on device. |
| 12 | Adaptive noise model | NONE | Fixed constants. |
| 13 | GNSS quality engine | PART | Binary live/not-live plus accuracy. No composite score, no jump or multipath detection. |
| 14 | GNSS outlier rejection | NONE | Every fix is applied verbatim. One bad fix teleports the marker. |
| 15 | GNSS integrity monitor | NONE | Absent. |
| 16 | ZUPT | PART | Variance-only, known false positive on smooth cruise; the 3 s delay is a workaround, not a fix. |
| 17 | Non-holonomic constraint | PART | Applied to *acceleration* as a clamp, not as a velocity-domain measurement update. Two-wheeler ratios are fixed, not lean-derived. |
| 18 | Barometer integration | PART | Read and displayed; not used in estimation. |
| 19-21 | Map matching / multi-hypothesis | NONE | No road graph, no matcher. |
| 22-24 | Tunnel / canyon / parking modes | PART | Tunnel and canyon are UI simulation flags, not detected modes. |
| 25 | Mode controller | PART | 4 fusion modes derived ad-hoc from getters; no explicit transition table, no transition log. |
| 26 | Reacquisition | PART | 3 s visual ease plus snap. No residual check, no state correction, no rejection. |
| 27 | Uncertainty engine | PART | Heuristic scalar margin; no covariance, no heading or velocity uncertainty. |
| 28 | Navigation integrity | NONE | Not separated from confidence. |
| 29 | Sensor fault detection | NONE | Presence-only health flags. |
| 30-31 | Thermal / battery modes | PART | Temperature is read; bias correction is computed but **never applied**; no operating modes. |
| 32-33 | Offline map engine / road graph | PART | Raster tiles work well. No graph, no region download, no versioning. |
| 34 | Route continuity | NONE | No routing at all. |
| 35 | Position history | NONE | Not recorded. |
| 36-37 | Drive recorder / replay | NONE | Absent (Python `simulation/` is offline-only). |
| 38 | Scenario simulator | PART | 2 of 22 scenarios, no parameters. |
| 39-41 | Ground-truth eval / ablation / benchmarks | NONE | No on-device evaluation. Offline `ml/evaluation` measures the synthetic set only. |
| 42-43 | Dataset pipeline / device profiles | NONE | Absent. |
| 44 | Performance monitoring | PART | ML latency only. |
| 45-46 | Native core / threading | NONE | Everything on the UI isolate. `cpp-core` is stubs. |
| 47 | Data integrity | PART | Getter soup; no immutable snapshot, no sequence number. |
| 48 | Privacy | DONE | Telemetry optional, offline-first, no account. |
| 49-51 | Drive mode / trust / explainable fusion | PART | Confidence ring and honest `--` exist. No drive mode, no fusion-contribution breakdown. |
| 52-53 | Anomaly engine / event timeline | PART | Road anomalies only, 5-entry ring buffer, no timeline. |
| 54-57 | Road intelligence / predictive GNSS loss | NONE | Absent (P3/P4). |
| 58-59 | Map-aware fusion / consistency score | NONE | Absent. |
| 60 | Health dashboard | PART | `DiagnosticsScreen` is static demo data. |
| 61-62 | Regression tests / numerical safety | PART | 113 good tests, but none for INS/EKF/quaternion — they do not exist yet. |
| 63-66 | Observability / diagnostics / real-vs-demo | PART | `debugPrint` only. Demo panels *are* labelled — the culture is right, the mechanism is missing. |
| 67-68 | Offline-first / optional backend | DONE | Genuinely offline-first. |
| 69-70 | Model update / config system | NONE | Constants scattered across 6 files. |
| 71 | State snapshot | NONE | About 30 individual getters. |
| 76 | <10 % drift target | NONE | **Never measured.** |
| 83 | No fake capabilities | DONE | Best-in-class here; must be preserved. |

**Top 8 by impact on drift** — these are what actually move the §76 number:

1. Yaw alignment (§6) — heading error is the dominant DR error term.
2. Error-state EKF plus INS (§10-11) — replaces open-loop integration.
3. GNSS outlier rejection and quality (§13-14) — stops corrupting the state.
4. Real neural velocity model (§8) — the asset is a pointer file today.
5. ZUPT/NHC as measurement updates (§16-17) — currently clamps, not observations.
6. Timestamp synchronization (§4) — 66 ms sensor skew is about 1.4 m at 80 km/h.
7. Map matching (§19) — needs a graph first.
8. Ground-truth evaluation (§39) — without it, nothing above is provable.

---

## 3. Navigation-engine dependency graph (current)

```
sensors_plus ─▶ MobileSensorDriver ─(List<double> x12 @50 Hz)─┐
geolocator ──▶ GeolocatorGateway ─▶ LiveLocationService ──────┤
MethodChannel ▶ DeviceHardwareService ────────────────────────┤
                                                               ▼
                                                    LiveSessionController
                                                     │  _onImu
                                                     │   ├─▶ VehicleAlignmentEngine (pitch/roll, NHC)
                                                     │   ├─▶ MlSpeedEstimator (TFLite fails → heuristic)
                                                     │   ├─▶ _updateHeading (magnetometer)
                                                     │   ├─▶ _advanceMotion ─▶ _integrate (lat/lon Euler)
                                                     │   └─▶ _detectAnomaly
                                                     │  _onLocationChanged ─▶ _applyFix (unconditional)
                                                     │  tick() @10 Hz ─▶ _syncOutage ─▶ OutageTracker
                                                     │                  └─▶ _easePosition
                                                     └─▶ notifyListeners() ≤10 Hz
                                                               │
                              ┌────────────────────────────────┼───────────────────┐
                              ▼                ▼               ▼                   ▼
                       DashboardScreen  ActiveNavScreen  TelemetrySink      BootSequence
```

Cycle risk: none. Coupling problem: every consumer reads about 30 loose getters off a mutable
`ChangeNotifier`, so there is no atomic, timestamped view of the estimate (§47, §71).

---

## 4. Proposed target architecture

Keep what is good — the location state machine, the offline tile stack, the honesty
discipline, the single-pipeline rule, the 10 Hz UI cap. Replace the estimator core.

```
                       ┌──────────────────── Dart, navigation core ──────────────────────┐
sensors_plus ─┐        │                                                                 │
geolocator  ──┼─▶ SensorHub ─▶ TimeSync ─▶ Calibration ─▶ FrameAlignment                  │
barometer ────┘   (typed        (monotonic,   (bias,        (R_phone_to_vehicle,          │
                   samples)      reorder,      scale,        yaw from motion)             │
                                 rate est.)    noise)             │                       │
                                                                  ▼                       │
                                                        VehicleStateClassifier            │
                                                                  │                       │
                                        ┌─────────────────────────┼──────────────┐        │
                                        ▼                         ▼              ▼        │
                                 NeuralVelocity            StrapdownINS     GnssQuality    │
                                 (+ uncertainty,           (quaternion,     (+ gating,     │
                                  + AI gate)                bias states)     integrity)    │
                                        └───────────┬─────────────┴──────────────┘         │
                                                    ▼                                      │
                                         AdaptiveErrorStateEKF                             │
                                       (15-state, covariance P)                            │
                                                    │                                      │
                                            MapMatcher (HMM)                               │
                                                    │                                      │
                                          IntegrityMonitor                                 │
                                                    │                                      │
                                          NavigationModeController                         │
                                                    ▼                                      │
                                       NavigationSnapshot (immutable)                      │
                       └──────────────────────────┬──────────────────────────────────────┘
                                                  │ ≤10 Hz
                      ┌───────────────────────────┼────────────────┬──────────────┐
                      ▼                           ▼                ▼              ▼
                 DriverUI                  DiagnosticsUI     DriveRecorder   TelemetrySink
                (dashboard, nav)          (research mode)     (JSONL log)     (optional)
```

Rules that constrain the build:

- `NavigationEngine` is pure Dart: no Flutter imports, no `ChangeNotifier`. It is unit-testable
  and replay-deterministic. `LiveSessionController` becomes a thin adapter — feed the engine,
  publish snapshots — and keeps its existing public getters as a compatibility facade so the
  113 existing tests and both screens keep working (§82 backward compatibility).
- Anything the engine cannot measure reports `null`, never a placeholder (§65, §83).
- `cpp-core` stays out until §44 profiling shows Dart is the bottleneck (§45). Dart on a
  15-state EKF at 50 Hz is microseconds — measure before porting.

---

## 5. Data-model changes

New, all immutable, all under `lib/core/nav/model/`:

```dart
enum SensorType { accel, gyro, mag, gravity, linearAccel, rotationVector,
                  gnss, barometer, temperature }
enum SampleQuality { excellent, good, degraded, invalid }
enum DataSource   { real, simulated, estimated, unavailable }   // §65

class SensorSample {            // §3
  final SensorType type;
  final int monotonicUs;        // device event time
  final int? wallClockUs;
  final List<double> values;
  final int accuracy;           // platform status, -1 = unknown
  final int sequence;
  final double? intervalUs;     // estimated from arrival history
  final bool valid;
}

class NavigationSnapshot {      // §71 — the one thing the UI observes
  final int sequence;
  final DateTime timestamp;
  final double latitude, longitude, altitude;
  final double speedMps, headingDeg;
  final Covariance3 positionCov;           // horizontal 2x2 plus vertical
  final double? headingSigmaDeg, speedSigmaMps;
  final GnssQuality gnss;
  final NavMode mode;
  final VehicleProfile vehicle;
  final SensorHealth sensors;
  final AiHealth ai;
  final MapMatchState? mapMatch;
  final Integrity integrity;
  final ThermalMode thermal;
  final FusionContribution contribution;   // §51
}
```

`DashboardDataModel`, `SatelliteBreakdownModel` and `mock_data.dart` stay, but only
`DemoNavigationRepository` may construct them, and only `DataSource.simulated` values reach
the UI through them (§66). Production code paths never touch `mock_data.dart`.

Deletions (§82): all 9 files under `features/data_acquisition/**`, `core/di/injection.dart`,
`core/errors/*`, `core/storage/local_storage.dart`, `core/utils/math_utils.dart`,
`core/utils/time_formatter.dart`, `features/ai_motion/domain/usecases/*`,
`nav_engine_controller.dart`, `handle_gnss_outage_usecase.dart`, `map_view.dart`,
`map_view_controller.dart`, `speedometer.dart`, `custom_compass.dart`, `ffi_mobile.dart`,
`ffi_web.dart`, `sensor_web.dart`.

---

## 6. Sensor pipeline changes

1. **`SensorHub`** replaces `MobileSensorDriver`'s positional list. Each physical sensor gets
   its own subscription emitting a `SensorSample` carrying its *own* event timestamp — no latching.
2. **Capability detection**: probe each stream once at start; a stream that errors or never
   emits within its budget is recorded `unavailable`. The engine must run with accel and gyro only.
3. **`TimeSync`**: monotonic base from the first sample; per-type EWMA interval estimate;
   out-of-order samples reordered inside a bounded 200 ms window; duplicates dropped by
   `(type, monotonicUs)`; gaps over 3x the expected interval counted as drops. Publishes
   `SampleQuality` and effective Hz per sensor (§4, §64).
4. **Fusion cadence**: the EKF predicts on gyro/accel at native rate, bounded to 100 Hz, and
   updates on GNSS / ZUPT / NHC / baro / neural-velocity as they arrive. UI stays at 10 Hz.
5. **Bounded queues** everywhere; drop-oldest with a counter, never unbounded growth (§46).

Threading: start single-isolate with the pipeline off the widget build path. Move to a
navigation `Isolate` only if §44 measurements show frame impact — `sensors_plus` delivers on
the platform thread into the root isolate, so a second isolate costs a port hop per sample.

---

## 7. ML pipeline changes

The blocking defect is packaging, not the model: `speed_estimator_int8.tflite` is a 130-byte
LFS pointer.

1. **Regenerate TFLite from the real ONNX** (`ml/models/speed_estimator/exported/speed_estimator.onnx`,
   264 KB) via the existing `ml/src/export/onnx_to_tflite.py`; commit the real artifact, or
   fetch it with `git lfs pull` and verify size and SHA-256 at build time.
2. **Model manifest** (`assets/models/manifest.json`): version, architecture, training-set
   version, SHA-256, input contract (rate, window, feature order, scaler), minimum app version.
   The runtime verifies the checksum before `Interpreter.fromAsset` (§69).
3. **Smoke test on load**: run one canned window with a known expected output; a mismatch
   rejects the model, keeps the previous or fallback path, and reports `AiHealth.failed` (§69).
4. **Uncertainty output already exists** — the head emits `[speed, log_variance]`. Feed
   `sigma = sqrt(exp(log_var))` into the EKF as measurement noise instead of the current
   cosmetic `confidence` number (§8).
5. **AI gate** (§9) computes `contribution` in [0,1] from: input-distribution distance (feature
   z-scores against the training scaler), inference latency, vibration level, classifier state,
   and physics disagreement `abs(v_ml - v_ins)` against the combined sigma. Confidence and
   contribution are displayed separately.
6. **Retraining is required before any accuracy claim.** The shipped model's own benchmark
   reports -309 % drift "improvement". Until real Indian-road drives exist (§42), the model
   ships **gated off by default**, with the honest label the app already uses.

---

## 8. EKF state definition

Error-state (indirect) formulation. The nominal state is propagated by the INS; the filter
estimates the *error* and feeds corrections back.

**Nominal state** (strapdown, §10):
`p_n` (lat, lon, alt) · `v_n` (vN, vE, vD) · `q_bn` (body-to-nav quaternion) · `b_a` · `b_g`

**Error state** `dx` in R^15:

| idx | symbol | meaning | unit |
|---|---|---|---|
| 0-2 | dp | position error (N, E, D) | m |
| 3-5 | dv | velocity error (N, E, D) | m/s |
| 6-8 | dtheta | attitude error (small-angle, nav frame) | rad |
| 9-11 | db_a | accelerometer bias error | m/s^2 |
| 12-14 | db_g | gyroscope bias error | rad/s |

Reserved extension slots (§11): accelerometer scale factor, magnetic heading bias,
neural-velocity bias, barometric altitude bias — added as states 15-18 only once
observability is demonstrated, not before.

**Propagation** (continuous `F`, first-order or van-Loan discretization at dt):

```
dp'      = dv
dv'      = -[C_bn * f_b  x] dtheta  -  C_bn * db_a  +  w_a
dtheta'  = -C_bn * db_g  +  w_g
db_a'    = -(1/tau_a) db_a  +  w_ba      (first-order Gauss-Markov)
db_g'    = -(1/tau_g) db_g  +  w_bg
```

**Measurement updates.** Each carries a residual `r`, innovation covariance `S = H P H' + R`,
a NIS gate `r' S^-1 r < chi2(n, 0.99)`, and gain `K = P H' S^-1`:

| Update | H rows | R source | When |
|---|---|---|---|
| GNSS position | dp | `accuracy^2`, inflated by the GNSS quality score | fix accepted by §13/§14 |
| GNSS velocity | dv | speed/bearing accuracy where exposed | fix has valid speed |
| ZUPT | dv = 0 | tight, (0.01 m/s)^2 | stationary detector with hysteresis |
| ZARU | db_g | gyro noise | stationary |
| NHC (car) | v_lat = v_vert = 0 in vehicle frame | (0.1 m/s)^2, loosened on a two-wheeler by lean angle | moving, not turning hard |
| Neural velocity | v_forward | `exp(log_var)` scaled by the AI gate | model loaded and gate open |
| Barometric altitude | dp_D | baro noise plus drift | barometer present |
| Map heading | dtheta_z | road-heading sigma over match confidence | map-match confidence above threshold |

**Adaptive R** (§12): each `R` is scaled by vehicle state and sensor quality — accelerometer R
times (1 + vibration RMS), magnetometer heading R times a magnetic-disturbance factor,
GNSS R times (1 + jump statistic).

**Numerical safety** (§62): Joseph-form covariance update, symmetrization `P = (P + P')/2`,
eigenvalue floor, quaternion renormalization every step, and a NaN/Inf guard that freezes the
filter into `SENSOR_FAILURE` rather than emitting garbage.

---

## 9. Map-matching design

**Graph format** (`assets/maps/graph/<region>.bin`, built by `maps/tools/graph_builder.py`,
which currently emits `{"edges": []}`):

- nodes: id, lat, lon
- edges: id, from, to, polyline (delta-encoded int32 microdegrees), road class, one-way flag,
  max speed, tunnel/bridge flag, vehicle restrictions
- spatial index: uniform grid (about 200 m cells) keyed cell-to-edge-ids. Flat array,
  memory-mappable, no runtime tree build.

**Matcher**: HMM (Newson-Krumm) over a sliding window of the last N = 10 fused positions.

- Emission: `P(z|e)` proportional to `exp(-0.5 (d_perp / sigma_z)^2)`, with `sigma_z` taken
  from the EKF horizontal covariance, times a heading-compatibility factor `cos(dPsi)`.
- Transition: `P(e_i -> e_j)` proportional to `exp(-abs(d_route - d_greatcircle) / beta)`.
- Viterbi over the window. **Emit the matched position only when the top candidate's posterior
  exceeds `snapThreshold` (0.6) and beats the runner-up by a margin** (§19, §21). Otherwise
  publish the raw fused position and `mapMatch = null`.
- Multi-hypothesis: keep the top three posteriors in the snapshot for the UI (§21).
- Feedback into the filter is a *soft heading measurement only* (§58); position is never
  force-snapped into the state.

**No graph data ships until `graph_builder.py` produces a real region.** Until then the matcher
reports `unavailable` — never a fabricated match percentage. The old fake "Map match %" was
already removed; it does not come back as a fake.

---

## 10. Testing strategy

| Layer | What | Where |
|---|---|---|
| Unit — math | quaternion normalize/compose/rotate round-trips, `C_bn` orthonormality, small-angle to quaternion, lat/lon to NED | `test/nav/math_test.dart` |
| Unit — EKF | covariance stays symmetric positive-definite over 10^4 steps; measurement-free propagation grows P monotonically; a perfect measurement collapses P; the NIS gate rejects a 10-sigma outlier | `test/nav/ekf_test.dart` |
| Unit — INS | a stationary phone keeps velocity under 0.05 m/s for 60 s with bias estimation on; a constant-rate turn integrates to the right heading | `test/nav/ins_test.dart` |
| Unit — GNSS gate | teleport, impossible speed, impossible acceleration, stale fix, out-of-bounds coordinates are all rejected | `test/nav/gnss_gate_test.dart` |
| Unit — timesync | out-of-order, duplicate, gap, rate estimation | `test/nav/timesync_test.dart` |
| Unit — map match | straight road, parallel roads (must NOT snap), fork, tunnel | `test/nav/map_match_test.dart` |
| State machine | every §25 transition has an explicit trigger test and a logged reason | `test/nav/mode_controller_test.dart` |
| Replay / golden | a recorded JSONL drive produces a trajectory within tolerance of a committed golden; **drift % must not regress** | `test/nav/replay_golden_test.dart` |
| Existing 113 | must keep passing unchanged — the compatibility facade is what guarantees this | `test/**` |

Golden trajectories live in `datasets/benchmarks/` as JSONL sensor logs plus expected metrics.
A change that worsens drift on a golden fails CI (§61).

---

## 11. Migration plan

Each phase ends with: `flutter analyze` clean, `flutter test` green, replay drift compared to
the previous phase, latency and memory measured. No phase merges on a regression.

### P0 — Navigation core (critical path to §76)

Status as of 2026-09-19. Baseline was 113 tests; the suite now runs **328**,
analyzer clean.

| # | Step | Status | Where |
|---|---|---|---|
| 0.1 | `lib/core/nav/` skeleton, versioned config, matrix + frame maths | **DONE** (32 tests) | `nav_config.dart`, `math/` |
| 0.2 | `TimeSync`: k-way merge, reorder, duplicates, drops, real-Hz, capability detection | **DONE** (20 tests) | `sensors/` |
| 0.3 | Calibration: gyro bias, accel bias/scale, mag hard+soft iron, noise stats, persistence, staleness | **DONE** (27 tests) | `calibration/` |
| 0.4 | Phone-to-vehicle alignment, yaw included | **DONE** (24 tests) | `alignment/mount_alignment.dart` |
| 0.5 | Strapdown INS (quaternion mechanization) | **DONE** | `ins/`, `ekf/` |
| 0.6 | 15-state error-state EKF, Joseph update, NIS gating, reject-streak recovery, bias-sigma floors | **DONE** (34 tests) | `ekf/navigation_filter.dart` |
| 0.7 | GNSS quality engine, outlier rejection, integrity monitor | **DONE** (26 tests) | `gnss/gnss_quality.dart` |
| 0.8 | Real TFLite model, manifest, checksum, smoke test, AI gate | **BLOCKED** — the asset is a 130-byte LFS pointer. Ships gated **off**. | `nav_config.dart` `AiConfig.enabled = false` |
| 0.9 | ZUPT/ZARU/NHC as measurement updates, motion classifier | **DONE** (22 tests) | `motion/`, `ekf/` |
| 0.10 | Engine assembled and wired into the live app *alongside* the existing pipeline | **DONE** (18 + 9 tests) | `navigation_engine.dart`, `live_session_controller.dart` |

The core runs on every real sensor frame in the app and publishes a
`NavigationSnapshot`, but **nothing the driver sees comes from it yet**. The
handover waits on a replay of recorded phone data (P2) — simulation is not that
evidence.

Measured cost: **20 us per sensor frame, 74 us peak** (200 frames, debug build).
At 50 Hz that is about 0.1 % of one core, so §45's native port stays
unjustified — measure before porting, as planned.

#### Simulated drift benchmark (§39, §76)

Car, phone yawed 35 deg on a tilted console, constant accel bias
[0.08, -0.05, 0.06] m/s^2 and gyro bias [0.002, -0.001, 0.004] rad/s plus
noise, 1 Hz GNSS at 5 m. Reproduce with
`flutter test test/nav/drift_benchmark_test.dart`.

| Outage | Distance | Final error | Drift | p95 | Heading err | Filter sigma | 3-sigma covers error |
|---|---|---|---|---|---|---|---|
| 30 s | 370 m | 7.1 m | **1.92 %** | 6.4 m | 0.4 deg | 49 m | yes |
| 60 s | 740 m | 13.0 m | **1.75 %** | 10.9 m | 1.1 deg | 50 m | yes |
| 120 s | 1480 m | 25.7 m | **1.74 %** | 22.8 m | 2.8 deg | 67 m | yes |
| 300 s | 3700 m | 208.7 m | **5.64 %** | 189.7 m | 14.4 deg | 90 m | yes |

Mount orientation makes no material difference (flat 1.85 % vs tilted 1.75 % at
60 s) — which is the entire point of step 0.4. A deliberately poor IMU
(0.3 m/s^2 bias) gives 17.25 % at 60 s, with the uncertainty still covering it.

**This is a bound on the estimator under modelled sensor error, not a field
measurement**, and must never be quoted as measured accuracy (§83). Real phones
add temperature drift, non-constant bias, vibration, multipath and mounts that
slip. Its job is to fail CI when a change makes drift worse (§61).

#### Findings from building P0 (things the plan did not predict)

1. **`vector_math`'s `Quaternion.rotated()` applies the opposite rotation to the
   same quaternion's `asRotationMatrix()`.** Every rotation in the core goes
   through `NavMath.rotateBodyToNav` / `rotateNavToBody`; a guard test pins the
   discrepancy so a package upgrade that fixes it fails loudly instead of
   silently flipping the heading sign.
2. **At rest, accelerometer bias and tilt are not separately observable.**
   Measured: a 0.3 m/s^2 forward bias is absorbed as 1.744 deg of pitch
   (9.80665 x sin 1.744 deg = 0.2984). ZUPT still removes the velocity drift
   completely (residual 1.2e-7 m/s), which is what matters for position — but
   the app must never claim it "learns the accelerometer bias at a stop".
3. **NHC alone cannot observe yaw.** Its residual is perfectly correlated with
   the yaw error (`dv_lat = V x dPsi`), so `H P H'` cancels and the gain is
   zero. With an independent velocity reference it is decisive: measured final
   yaw error 0.00 deg / sigma 0.68 deg with NHC versus 5.42 deg / sigma 34 deg
   without.
4. **The GNSS heading-rate gate has to be speed-aware.** A flat 180 deg/s limit
   passes a 170 deg/s bearing flip. Grip bounds it instead:
   `yawRate <= a_lat / v`, so at 20 m/s and 8 m/s^2 the real limit is 23 deg/s.
5. **A measurement gate needs an escape hatch.** A filter that rejects the same
   measurement forever has decided the world is wrong. After
   `consecutiveRejectLimit` rejections the core inflates the covariance of
   exactly the states that measurement observes, then listens again.
6. **Alignment information arrives at GNSS rate, not IMU rate.** The forward
   axis is regressed against the GNSS speed derivative, so one braking event is
   one independent observation however many IMU samples fall inside it.
   Confidence counts *events*; the IMU samples only average down direction
   noise. Getting this wrong made the fit look 50x better informed than it was.
7. **Gravity must be estimated only while the vehicle is not accelerating.**
   A longitudinal acceleration barely changes `|a|` (1.8 m/s^2 moves it by
   0.17), so no magnitude test can catch it — but it tilts the estimated
   horizontal plane, and a tilted plane pours gravity straight into the forward
   axis. Gating gravity updates on the GNSS speed derivative took the recovered
   forward axis from 4 deg of error to under 0.1 deg.
8. **A filter that cannot propagate must not be initialised.** The engine
   originally seeded the filter from the first fix while the mount was still
   unknown. With no body frame there is no prediction, so its position froze
   while the vehicle drove away — after which the NIS gate correctly rejected
   70 % of subsequent fixes. During calibration the fix *is* the position.
9. **Seeding attitude from gravity and then declaring it +/-20 deg uncertain
   throws the seed away.** The filter promptly re-explained an accelerometer
   bias as 8 deg of pitch, a 1.37 m/s^2 gravity leak. Roll and pitch are only
   as uncertain as the gravity vector that set them.
10. **A constant acceleration has zero variance, so a variance-based stillness
    test is blind to it.** Pulling away at a steady 1.8 m/s^2 read as "still"
    for a full second every cycle (the GNSS speed that would have vetoed it is
    up to 1 s stale), and ZUPT told the filter it was stationary through real
    acceleration. Fixed by testing *horizontal specific force* over the newest
    few samples: slow to declare a stop, quick to abandon one.
11. **Floor the bias covariance.** Without it the filter drove its bias
    variance to near zero while GNSS was healthy, then entered an outage
    believing it knew the bias exactly: 404 m of error at 300 s while still
    reporting a 65 m sigma. Adding the floor fixed the honesty *and* the
    accuracy — 300 s drift fell from 10.93 % to 5.64 %.

### P1 - Accuracy

Status as of 2026-09-19. Suite: **416 tests**, analyzer clean.

| Item | Status | Where |
|---|---|---|
| Road graph: format, spatial index, bounded routing | **DONE** (31 tests) | `map/road_graph.dart` |
| HMM map matcher, multi-hypothesis, refusal to snap | **DONE** | `map/map_matcher.dart` |
| Graph builder (OSM to graph) + cross-language contract test | **DONE** (5 tests) | `maps/tools/graph_builder.py`, `test/nav/graph_builder_contract_test.dart` |
| Map-assisted dead reckoning wired into the engine | **DONE** (6 tests) | `navigation_engine.dart` |
| Barometer: relative height, ramps, car-park floors, drifting sigma | **DONE** | `sensors/barometer.dart` |
| Sensor fault detection: frozen, stalled, out-of-range, noisy, magnetic | **DONE** (22 tests with baro) | `sensors/sensor_fault_detector.dart` |
| Vehicle-state classifier | DONE in P0.9 | `motion/motion_classifier.dart` |
| Integrity monitor | DONE in P0.10 | `navigation_engine.dart` `_integrity()` |
| Reacquisition with residual validation | DONE in P0.10 | gate + settling window |
| Covariance-driven uncertainty **in the UI** | TODO - it is in the snapshot, no screen reads it yet | - |

**No road graph ships.** `maps/processed_graphs/road_edges.json` is still
`{"edges": []}`, so on a stock build the matcher reports `unavailable` and
`NavMode.mapAssistedDeadReckoning` never occurs. Build one with:

```
python -m maps.tools.graph_builder overpass.json out.json --region delhi
```

### P2 - Validation

| Item | Status | Where |
|---|---|---|
| Drive recorder (JSONL, bounded, records rejected fixes too) | **DONE** (20 tests with replay) | `replay/drive_recorder.dart` |
| Deterministic replay engine with step/seek/scoring | **DONE** | `replay/replay_engine.dart` |
| Ground-truth metrics (§39) | **DONE** | `replay/replay_engine.dart`, `test/nav/support/drift_evaluator.dart` |
| Ablation harness (§40), seed-averaged | **DONE** (4 tests) | `test/nav/ablation_test.dart` |
| Dataset format + event labels (§42) | **DONE** | `replay/drive_log.dart` `DriveMeta`, markers |
| Drive recorder wired into the live app, opt-in and local-only | **DONE** (11 tests) | `platform/storage/drive_log_store.dart`, `live_session_controller.dart` |
| Per-vehicle benchmarks (§41) | TODO - the harness takes a `VehicleClass`, no two-wheeler drive profile yet | - |
| Device capability profile (§43) | TODO | - |

#### Recording a real drive

`LiveSessionController.startRecording()` writes a JSONL log to the app's
private storage and `stopRecording()` closes it; `markEvent(label)` drops a
labelled marker for a tunnel entry, a pothole, whatever the driver taps.
Nothing starts on its own and nothing is uploaded — a drive log is a complete
record of where the phone went, so it is opt-in, local-only and deletable
(§48). `test/drive_recording_test.dart` asserts that a drive recorded through
the live controller replays back through the engine.

This is the step that unblocks the P0.10 handover: the engine takes over the
driver-facing position only once a replay of *recorded phone data* shows it
beating the heuristic. Simulation was never going to be that evidence.

#### Replay determinism

`test/nav/replay_test.dart` asserts **exact** equality, not approximate: the
engine has no clock, no timers and no randomness, and the log stores every
sensor value at full double precision, so a replay reproduces the live run bit
for bit. That is what makes a drift change attributable to a code change rather
than to the weather on the day. Rounding log values to "sensible" decimals
would quietly make a replay a different experiment, so it is not done.

#### Measured ablation (§40)

60 s GNSS outage, 740 m travelled, **averaged over 5 seeded drives** because a
single drive is an anecdote. `flutter test test/nav/ablation_test.dart`.

| Configuration | Mean drift | Worst | Best |
|---|---|---|---|
| A raw inertial | 35.13 % | 43.73 % | 21.65 % |
| B + GNSS velocity | 15.37 % | 35.55 % | 5.93 % |
| C + non-holonomic constraint | **1.36 %** | 1.52 % | 1.23 % |
| D + ZUPT / ZARU | 1.37 % | 1.78 % | 0.98 % |
| E + adaptive GNSS covariance | 1.37 % | 1.78 % | 0.98 % |
| F complete (no map, no AI) | 1.37 % | 1.78 % | 0.98 % |

What this actually says, stated plainly:

* **The non-holonomic constraint is the whole game.** An 11x reduction, from
  15.4 % to 1.4 %. Everything else is refinement.
* **ZUPT/ZARU shows no measurable benefit on these profiles.** Its mean is
  inside the spread of the rung below it. That is not a claim it is useless —
  these drives cruise with one brief stop per 30 s cycle, which is the wrong
  test for a stationary-phase constraint. It needs a stop-and-go city profile
  before anything is claimed either way.
* **Adaptive GNSS covariance is untestable by this metric**, because there is
  no GNSS during the outage being scored. It needs a degraded-GNSS scenario.
* **The neural-velocity rung of §40 is absent, not skipped quietly**: the model
  asset is a 130-byte Git-LFS pointer, so there is nothing to ablate.

### P3 — Productization

Drive mode, route continuity, region download, drive history, functional diagnostics,
performance dashboard, model management, optional backend sync.

### P4 — Advanced research

Predictive GNSS loss, collective road intelligence, learned map priors, advanced anomaly
detection, native acceleration (only if profiled).

### Compatibility and risk

- The facade on `LiveSessionController` means screens and tests change last, not first.
- Every new subsystem ships behind a config flag defaulting to today's behaviour until its own
  tests and replay comparison pass.
- Nothing claims to be ACTIVE until it is (§83). `DataSource` on every displayed value is the
  mechanism that enforces this, replacing today's convention-by-discipline.
