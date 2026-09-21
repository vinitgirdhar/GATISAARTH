# The navigation engine on real IO-VNBD drives (v3 evidence)

Ground truth is the Racelogic VBOX in every case. Reproduce: convert
(`python ml/src/dataset/iovnbd_to_drive_log.py --imu vehicle --all --min-minutes 5 --out ml/data/processed/drive_logs_vehicle`),
then `IOVNBD_LOG_DIR=… EVIDENCE_DIR=docs/evidence flutter test test/nav/iovnbd_outage_benchmark_test.dart`
and, for the map, `test/tool/extract_region_pack_test.dart` +
`test/nav/iovnbd_real_map_matching_test.dart`. Raw results: `iovnbd_outage_benchmark.json`,
`iovnbd_real_map_matching.json`.

## What is real and what is a stand-in

* Real: the trips (Coventry / West Midlands, UK), the VBOX position and speed used as truth and as the
  1 Hz GNSS, the vehicle ESP/CAN acceleration and yaw-rate channels, the OpenStreetMap roads.
* Stand-in: the **IMU is the car's own ESP sensors** (longitudinal / lateral acceleration, yaw rate;
  planar, vehicle frame, 10 Hz), used as an *external-IMU proxy*. It is not a smartphone IMU and not a
  FOG / industrial IMU. The dataset's smartphone accelerometer cannot be used to align the mount
  (`iovnbd_dataset_notes.md` §5), so a phone-IMU replay of the engine is not possible on this data.
* Method: the app's own outage benchmark. At many start times GNSS is withheld for 10 / 30 / 60 / 120 s;
  the error is the distance from the engine's position to the withheld fix; drift = error / distance
  travelled. "Hold velocity" (keep the last speed and course) is the baseline a product with no inertial
  filter would give.

## 1. The engine alone, 32 real trips (`iovnbd_outage_benchmark.json`)

Median over trips of each trip's median drift, in % of the distance travelled in the blackout:

| Blackout | Core | Hold velocity | Trips with core < 10 % |
|---:|---:|---:|---:|
| 10 s | 5.6 % | 16.9 % | 17 / 21 |
| 30 s | 10.7 % | 42.9 % | 10 / 21 |
| 60 s | 20.2 % | 67.1 % | 5 / 21 |
| 120 s | 24.4 % | 72.8 % | 2 / 20 |

32 trips ≥ 5 min were replayed; the core never became healthy enough to lead on 9 of them (too little
excitation for the mount alignment), so 23 have a score. Best trips at 60 s: Vw2 3.7 %, Vw16a 6.6 %,
Vw14b 8.0 %; worst: Vta30 50 %, S4 78 %, Vtb1 119 %.

## 2. Real sensors on real roads: with and without the map (`iovnbd_real_map_matching.json`)

The three long Coventry trips on which the core led, replayed with and without the road graph read from a
real OSM archive of the area (22 MB, cut with the phone's own map downloader in 30 s: it works for any
country). Median drift %, without → with the map (median error in m in brackets):

| Trip (span) | 10 s | 30 s | 60 s | 120 s |
|---|---:|---:|---:|---:|
| S1 (6.7 km) | 8.1 → 8.0 | 7.3 → 6.9 | 30.8 → 30.5 (137 → 114 m) | 41.3 → 38.8 (329 → 304 m) |
| S3c (19.2 km) | 6.8 → 6.7 | 9.8 → 9.7 | 20.2 → 23.2 (141 → 113 m) | 23.8 → 25.1 (395 → 337 m) |
| S4 (10.9 km) | 17.2 → 12.1 | 46.5 → 17.3 (185 → 46 m) | 78.0 → 20.4 (157 → 192 m) | 56.7 → 45.4 (473 → 442 m) |
| median of the three | 8.1 → 8.0 | 9.8 → 9.7 | 30.8 → 23.2 | 41.3 → 38.8 |

The road graph helps a little on average and a lot on one trip (S4); it does not change the picture on
another. Median error in metres falls in most cells; drift % moves both ways where the distance travelled
in the window varies.

## 3. What this shows and what it does not

* The engine beats "hold the last velocity" by 3× on real drives (60 s: 20 % vs 67 %), and meets the
  SIH < 10 % target for blackouts up to about 30 s on most trips and on the best trips at 60 s — but it
  does **not** meet 10 % at 60–120 s on median, with or without the map, on this data.
* It is not a phone result, not a lane-level result and not a physical-vehicle-with-phone test; those
  remain open (`pending_work.md`).
* The neural forward-speed measurement and the disturbance-aware fusion (P1–P3) are the levers that act on
  exactly the error that dominates here (along-track speed drift); their effect is reported in
  `ai_in_the_loop.md`.
