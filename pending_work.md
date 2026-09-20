# GatiSaarth - Pending Work for SIH26168

## Purpose

This document captures the remaining technical work and validation evidence required to move **GatiSaarth** from its current implementation state toward the full technical endpoint described in **SIH26168: AI-ML based Intelligent Dead Reckoning system for seamless navigation**.

This is a **status and endpoint document**, not an implementation roadmap. It intentionally does not prescribe an order in which the work must be completed.

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
| AI forward-speed estimation | **PARTIAL** | ML model exists, but its forward-speed output must become an active navigation-filter measurement |
| AI/statistical vibration filtering | **NOT DONE** | Local model must actively identify/filter road vibration, potholes, bumps, and related disturbances as required |
| AI-based GNSS+INS fusion | **NOT DONE** | AI/ML component must actively participate in fusion, rather than relying only on deterministic GNSS quality logic |
| Real offline road graph | **NOT DONE** | Populate Delhi NCR and Maharashtra road graphs with real OSM-derived topology |
| Live map matching | **NOT DONE** | Real DR trajectory must be constrained to the populated road network during GNSS outage |
| Carriageway/topological constraints | **PARTIAL / UNVERIFIED** | Must be demonstrated against real road-network data |
| Lane-level accuracy | **NOT ACHIEVED** | SIH statement explicitly asks for lane-level accuracy; current model is road/carriageway level |
| IO-VNBD training | **NOT DONE** | Actual IO-VNBD data must be used rather than synthetic data that only mimics it |
| IO-VNBD testing + position plots | **NOT DONE** | Held-out inference results and position plots must be produced for proposal/evaluation evidence |
| Real vehicle validation | **NOT DONE** | Physical phone + vehicle GNSS-denied tests required |
| Real quantitative drift evidence | **NOT DONE** | Real test evidence needed for the <10% drift benchmark |
| External IMU validation | **NOT DONE** | Same engine must be demonstrated with external IMU data |
| ~200 Hz edge validation | **NOT DONE** | Edge engine must be benchmarked with a high-rate stream around 200 Hz |
| C++ edge engine architecture | **DONE / UNVERIFIED** | Standalone C++ engine exists; real high-rate/external-IMU execution still needs evidence |
| On-device TFLite inference infrastructure | **DONE** | Lightweight model execution exists on the phone |

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

**PARTIAL**

### Current state

A neural speed-estimation model exists and runs locally on-device. However, its output is currently advisory and is not an active forward-speed measurement update inside the navigation filter.

The current vibration/pothole handling is primarily deterministic thresholding and EKF process-noise treatment rather than an active AI/statistical vibration model.

### Remaining requirements

#### 3.1 Active forward-velocity measurement

The ML model must become part of the navigation estimation loop:

```text
IMU
  -> ML speed model
  -> forward velocity + uncertainty
  -> navigation-filter measurement update
```

The neural prediction should be accepted/rejected using an appropriate measurement gate and its predicted uncertainty should affect measurement noise.

#### 3.2 AI/statistical disturbance filtering

The final system needs an on-device method that addresses the disturbances named by SIH, including:

- engine/idling vibration
- high-frequency road noise
- pothole shocks
- bumps
- related non-navigation motions
- accidental phone movement/misalignment where applicable

### Endpoint

The phone's noisy IMU stream produces a reliable forward-speed estimate and disturbance-aware navigation measurements locally, without requiring vehicle OBD/speedometer data.

---

## 4. Requirement 3: Advanced Map Matching & Kinematic Constraints

### Kinematic Constraints

**Status: DONE**

Current navigation already includes vehicle-frame non-holonomic constraints and stationary/turn-related constraints such as NHC, ZUPT, and ZARU.

### Real Map Matching

**Status: NOT DONE**

The HMM map-matching implementation exists, but the actual road graph currently contains no edges in the inspected build. Therefore, the live phone build is not currently constraining the DR trajectory against a real OSM road network.

### Required endpoint

During GNSS outage:

```text
INS / fused trajectory
       -> real offline OSM road graph
       -> road candidate matching
       -> road heading / topology constraints
       -> kinematic constraints
       -> road-constrained navigation estimate
```

The result must work on actual target-region road data rather than dummy/in-memory test segments.

### Road-network capabilities expected at endpoint

- Road centerlines
- Directed road geometry
- One-way information
- Intersections
- Connectivity/topology
- Parallel carriageway handling
- Road class information as available
- Consistent heading constraints

---

## 5. Requirement 4: GNSS+INS Fusion Engine

### Conventional GNSS+INS Fusion

**Status: DONE**

A 15-state Error-State Kalman Filter is already present with GNSS/IMU integration, uncertainty handling, NIS gating, and adaptive GNSS covariance logic.

### AI-based fusion

**Status: NOT DONE**

The current fusion weighting is deterministic/statistical rather than an active neural fusion model.

### Required endpoint

An AI/ML model must actively contribute to the fusion process. A valid implementation can, for example, predict fusion confidence or scaling factors that dynamically affect process/measurement noise or another well-defined fusion parameter.

The important condition is that AI is part of the actual GNSS+INS fusion loop, not only shown in diagnostics.

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

**NOT DONE**

### Current state

The repository contains an intended IO-VNBD ingestion/training pipeline, but the inspected training build does not contain the actual official IO-VNBD trajectories. Current training data is synthetic data designed to mimic IO-VNBD characteristics.

### Required endpoint

Actual IO-VNBD data must be incorporated into the model-development/evaluation process.

Minimum evidence required by the problem statement:

```text
IO-VNBD subset
      -> train / validation / test
      -> trained preliminary AI model(s)
      -> held-out inference
      -> position / trajectory plot
      -> quantitative results
```

The preliminary AI models and corresponding IO-VNBD inference position plots are part of proposal screening evidence.

---

## 9. Lane-Level Accuracy

### Status

**NOT ACHIEVED**

### Current state

The current navigation/map model is road/carriageway-oriented. It does not model explicit lane indices or lane geometry.

### Required endpoint

The literal SIH wording calls for maintaining lane-level accuracy during GNSS outage.

A lane-level claim should only be made if the system can actually localize to individual lanes and this behavior is validated. Otherwise, the current defensible capability remains road/carriageway-level constrained navigation.

---

## 10. Real-World Vehicle Validation

### Status

**NOT DONE**

### Current state

The current reported drift results are based on simulation/replay testing. No physical vehicle test with an intentionally unavailable GNSS signal has yet established real-world drift performance.

### Required endpoint

A physical smartphone mounted in a vehicle must demonstrate:

```text
GNSS lock
  -> vehicle motion
  -> GNSS outage / denied segment
  -> continuous DR
  -> GNSS recovery
  -> measured trajectory error
```

The evidence should include recorded sensor/navigation logs and quantitative error measurements.

---

## 11. Dead-Reckoning Performance Benchmark

### SIH target

Positional drift must remain below **10% of the total distance travelled** during GNSS blackout.

Examples stated in the problem statement include:

- Less than 5 m drift over 50 m during a GNSS-denied interval under approximately one minute.
- Less than 100 m drift over 1 km at approximately 60 km/h in a GNSS-denied environment, or a similar simulated environment.

### Current status

**SIMULATION PASS / REAL-WORLD NOT VERIFIED**

Current internal simulation results documented for GatiSaarth are approximately:

- 30 s outage: ~1.1% drift
- 60 s outage: ~1.75% drift
- 300 s outage: ~5.64% drift

These figures demonstrate the simulated benchmark behavior but do not substitute for physical-vehicle evidence.

### Endpoint

Produce reproducible real or evaluation-dataset measurements showing the final system remains below the SIH drift threshold, with the test setup and ground-truth source clearly documented.

---

## 12. External IMU / Edge-Deployable Engine

### Status

**ARCHITECTURE EXISTS / VALIDATION NOT DONE**

### Current state

The C++17 edge engine provides a standalone navigation-engine architecture with interfaces designed for high-rate IMU ingestion.

However, the inspected system has not yet demonstrated an actual external FOG, industrial IMU, USB IMU, ROS IMU stream, or equivalent external source through the deployed engine.

### Required endpoint

The same navigation algorithms/models must accept external IMU data independently of the Android sensor stack and operate correctly as an edge-deployable engine.

---

## 13. ~200 Hz Edge Requirement

### Status

**ARCHITECTURE EXISTS / BENCHMARK NOT DONE**

### Current state

The C++ engine contains high-rate buffering/interfaces intended for approximately 200 Hz operation, but actual 200 Hz execution and performance have not been demonstrated.

### Required endpoint

A reproducible benchmark should demonstrate a high-rate input stream around 200 Hz being processed by the edge engine without buffer instability or unacceptable latency, with measured throughput/latency results.

---

## 14. On-Device Execution Requirement

### Status

**MOSTLY DONE**

### Current state

The project already contains a lightweight TFLite inference path for on-device speed estimation.

### Remaining condition

All final AI/ML components needed by the complete system must execute on-device during navigation inference, while model training remains an offline/cloud/desktop activity.

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

### Completed

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

### Pending / Not Yet Demonstrated

- [ ] Active ML forward-speed measurement inside EKF
- [ ] AI/statistical vibration filtering in the navigation pipeline
- [ ] Active AI-based GNSS+INS fusion
- [ ] Populate real Delhi NCR road graph
- [ ] Populate real Maharashtra road graph
- [ ] Activate live map matching using those graphs
- [ ] Demonstrate road/topological constraints on real road data
- [ ] Address the SIH lane-level accuracy requirement, or document the validated scope if not achievable
- [ ] Download and integrate actual IO-VNBD data
- [ ] Train/evaluate the models on actual IO-VNBD data
- [ ] Produce required IO-VNBD preliminary model results and position plots
- [ ] Perform physical vehicle GNSS-denied testing
- [ ] Establish real ground-truth comparison
- [ ] Demonstrate <10% drift with real/evaluation evidence
- [ ] Validate external IMU input
- [ ] Benchmark edge processing around 200 Hz

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
