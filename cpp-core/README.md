# GatiSaarth edge engine (C++17)

A standalone port of the navigation core for edge hardware and external IMUs. The
Flutter app does **not** link it (the app runs the Dart core in
`frontend/lib/core/nav/`); this is for boards such as a Raspberry Pi fed by a USB,
serial or UDP IMU, and for replaying recorded streams quickly.

## What is in it

| Path | What it is |
|---|---|
| `include/engine/nav_engine.h` | Strapdown INS in a local-level NED frame with a 15-state error-state Kalman filter: GNSS position/velocity/altitude, ZUPT, ZARU, non-holonomic constraint, external forward speed. A plain value type, so copying it forks the filter. |
| `include/engine/earth.h` | WGS-84 normal gravity, Coriolis, attitude propagation. |
| `include/engine/edge_pipeline.h` | Producer/consumer pipeline over a lock-free SPSC queue (`spsc_queue.h`); a full queue drops the newest event and counts it. |
| `include/engine/sensor_source.h` | Input abstraction and the CSV reader (format below). |
| `include/engine/replay.h` | Outage replay and scoring against ground truth. |
| `tools/replay_external_imu.cpp` | Drive the engine from a CSV (or stdin) and score GNSS outages. |
| `tools/bench_200hz.cpp` | Throughput, latency and buffer behaviour at ~200 Hz. |
| `tools/iovnbd_to_external_imu.py` | Converts an IO-VNBD trip into the CSV format. |

## CSV input

One row may carry any subset of the groups, so streams at different rates share a
file. Header names are case-insensitive and column order is free.

```
t                                 seconds, non-decreasing
ax ay az gx gy gz                 m/s^2 specific force, rad/s (all six or none)
mx my mz                          microtesla (optional)
gnss_lat gnss_lon                 degrees (both or neither)
gnss_alt gnss_speed gnss_course gnss_acc   optional
truth_lat truth_lon               ground truth, for scoring only
```

## Build and test

```bash
cmake -S cpp-core -B cpp-core/build -DCMAKE_BUILD_TYPE=Release
cmake --build cpp-core/build --config Release
ctest --test-dir cpp-core/build -C Release
```

Measured numbers (throughput, latency, the external-IMU replay) are in
`docs/evidence/codex_edge_200hz.json` and `docs/evidence/codex_external_imu_replay.json`.
The 200 Hz run uses a synthetic drive and IO-VNBD data interpolated up from 10 Hz; no
physical 200 Hz or FOG IMU has been tested yet.
