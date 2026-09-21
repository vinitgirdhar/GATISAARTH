# Field-Testing Protocol & Ground-Truth Validation Guide (SIH26168 / v3.1)

## 1. Overview & Objective

This document establishes the official testing protocol for **Requirement 10 (Real-World Vehicle Validation)** and **Requirement 11 (Dead-Reckoning Performance Benchmark <10% Drift)** of SIH26168.

While algorithmic validation on the **IO-VNBD dataset** with VBOX ground truth is fully evidenced in [`docs/evidence/iovnbd_engine_and_map_evidence.md`](file:///c:/Users/vidhy/Downloads/gathisarthi/docs/evidence/iovnbd_engine_and_map_evidence.md) and [`docs/evidence/iovnbd_outage_benchmark.json`](file:///c:/Users/vidhy/Downloads/gathisarthi/docs/evidence/iovnbd_outage_benchmark.json), final end-to-end acceptance requires driving with a physical smartphone running the **GatiSaarth mobile application** in a real vehicle under controlled GNSS-denied conditions.

---

## 2. Test Setup & Equipment

### 2.1 Hardware Requirements
1. **Primary Test Device**: Android smartphone running Android 10+ (tested on Google Pixel 9 / arm64-v8a).
2. **Mounting**: Rigid vehicle phone mount (dashboard or windshield suction mount).
   - *Note*: Magnetic or spring-clamp mounts are acceptable; the engine's automatic mount alignment (`MountAlignmentEstimator`) determines vehicle-relative pitch, roll, and yaw automatically within 10–30 seconds of forward vehicle motion.
3. **Vehicle**: Any four-wheeler (passenger car) or two-wheeler.
4. **Reference Ground Truth (One of the following)**:
   - **Method A (Survey / Known Waypoints)**: Driving through a mapped urban tunnel or underground corridor with known entrance/exit surveyed coordinates.
   - **Method B (Dual-Receiver / External GNSS)**: Secondary high-precision external RTK/GNSS receiver (e.g. u-blox F9P) mounted on the roof logging reference NMEA/UBX.
   - **Method C (Synthetic Blackout)**: Using the app's built-in **Tunnel Test** or **Urban Canyon** scenario controls in the UI (which withholds real GNSS from the filter while recording the true background GNSS fixes for ground-truth comparison).

---

## 3. Test Scenarios & Driving Profiles

| Scenario ID | Environment | Speed Profile | Outage Duration | Target Pass Criteria |
|---|---|---|---|---|
| **SC-01** | Straight Highway Outage | 60–80 km/h cruising | 30 seconds | Drift < 3% of distance |
| **SC-02** | Highway Extended Outage | 60–80 km/h cruising | 60 seconds | Drift < 10% of distance |
| **SC-03** | Urban Canyon / Complex Bends | 20–40 km/h stop-and-go | 30 seconds | Drift < 5% of distance |
| **SC-04** | Urban Tunnel / Underpass | 30–50 km/h with turns | 60 seconds | Drift < 10% of distance |
| **SC-05** | Stop-and-Go with ZUPT | 0–30 km/h traffic light stops | 45 seconds | Zero drift accumulation while stationary |

---

## 4. Operational Execution Procedure

### Step 1: Pre-Drive Preparation
1. Ensure the target region's offline map pack is installed (e.g., Delhi NCR or Maharashtra) via the app's Map Download sheet. This provides the offline vector road network for map matching.
2. Launch **GatiSaarth** and secure the phone into the mount.
3. Select the vehicle profile (Four-Wheeler or Two-Wheeler) in the navigation drawer or settings.

### Step 2: In-Vehicle Alignment & Initialization
1. Drive forward normally for at least 15–30 seconds above 15 km/h on a straight road.
2. Observe the dashboard:
   - **Engine Status**: Transitions from `Boot` -> `Alignment` -> `Navigation (GNSS Aided)`.
   - **Mount Alignment**: Displays `Aligned` with high confidence.
   - **Road Match**: Displays `Matched` with current road name/class.

### Step 3: Logging & Outage Initiation
1. Tap the **Record Drive** button to start recording sensor telemetry to the local JSONL drive-log.
2. **For Physical Outages (Tunnel / Underpass / Shielding)**:
   - Drive through the tunnel/underpass or place an RF-attenuating pouch over the phone.
   - The engine automatically detects GNSS loss within 1.0 s, flags `GNSS Outage`, and engages **Dead Reckoning (DR)**.
3. **For Controlled In-App Outage Testing**:
   - Tap **Tunnel Test** (triggers a 30 s GNSS blackout) or **Urban Canyon** (triggers satellite multipath degradation).
4. Tap **Add Marker** at key physical checkpoints (tunnel entrance, midpoint, tunnel exit).

### Step 4: GNSS Recovery & Session Completion
1. Exit the tunnel or remove RF shielding.
2. The engine detects healthy GNSS signals, initiates smooth Kalman re-alignment, and converges without visual snapping.
3. Stop vehicle, tap **Stop Recording**, and note the logged file path.

---

## 5. Quantitative Scoring & Drift Verification

### 5.1 Extracting the Drive Log
Pull the recorded log from the phone using ADB:
```bash
adb pull /sdcard/Android/data/com.gatisaarth.app/files/drive_logs/ ./test_logs/
```

### 5.2 Automated Scoring Execution
Run the app's native offline drive scorer against the recorded log:
```bash
# Single drive evaluation
DRIVE_LOG=./test_logs/drive_log_2026-09-21.jsonl flutter test test/nav/score_drive_test.dart

# Bulk dataset outage benchmark
IOVNBD_LOG_DIR=./test_logs/ flutter test test/nav/iovnbd_outage_benchmark_test.dart
```

### 5.3 Metric Calculation
For each outage interval $[t_{\text{start}}, t_{\text{end}}]$:
1. **Total Distance Travelled ($D$)**:
   $$D = \int_{t_{\text{start}}}^{t_{\text{end}}} v(t) \, dt$$
2. **Horizontal Position Error ($\epsilon_{\text{pos}}$)**:
   $$\epsilon_{\text{pos}} = \text{Haversine}(\mathbf{p}_{\text{DR}}(t_{\text{end}}), \mathbf{p}_{\text{Truth}}(t_{\text{end}}))$$
3. **Percentage Drift Error ($\delta_{\%}$)**:
   $$\delta_{\%} = \frac{\epsilon_{\text{pos}}}{D} \times 100\%$$

**SIH26168 Pass Threshold**: $\delta_{\%} < 10.0\%$ for all outages up to 60 seconds.
