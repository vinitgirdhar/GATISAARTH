# GatiSaarth — Master AI/ML Training Pipeline Notebook (v3.0, real IO-VNBD data)

The unified pipeline for the **GatiSaarth smartphone inertial dead-reckoning system**. v3.0 replaces the v2 synthetic data with the
real **IO-VNBD** trips (smartphone + Racelogic VBOX). Results are in [`../README.md`](../README.md); every number is written to
`ml/evaluation/metrics/*.json` by the notebook itself.

* **File:** [`gati_ai_dead_reckoning_master_pipeline.ipynb`](gati_ai_dead_reckoning_master_pipeline.ipynb) (updated in place)
* **Headless runner:** [`../run_pipeline_script_mode.py`](../run_pipeline_script_mode.py) executes the code cells in order in one namespace.

## Before the first run: fetch the real data

`IO-VNBD_DATASET/IO-VNBD-master` only contains Git-LFS **pointer** files (130 bytes each), not data. Fetch the real files (default: the 144
synchronised + categorised csv files, 426 MB) into the git-ignored `ml/data/raw/IO-VNBD_repo/`; every file is checked against the size and
SHA-256 in its pointer:

```bash
python ml/src/dataset/fetch_iovnbd.py            # --dry-run, --subset {sync-categorised,sync-all,all}, --include-images
python -m pytest ml/tests -q                     # offline unit tests (fetch tool, sync, windows, evaluation)
```

## Running

```bash
python ml/run_pipeline_script_mode.py                 # whole pipeline, ~30-40 min on a GPU (speed model <= 20 min)
python ml/run_pipeline_script_mode.py --upto 14       # data, split, baselines, training, evaluation, position drift only
python ml/run_pipeline_script_mode.py --force-reprocess   # re-synchronise the raw csv even if the cleaned parquet exists
jupyter notebook ml/notebooks/gati_ai_dead_reckoning_master_pipeline.ipynb    # interactive: Restart & Run All
```

The repository root is discovered from the working directory (or `GATISAARTH_ROOT`), so the notebook runs from any checkout location.
Smoke-run knobs: `GATI_SPEED_EPOCHS=2` and `GATI_AUX_EPOCHS=1` shorten the speed / vibration / motion-quality training.
The notebook only writes under `ml/`; it does **not** touch `frontend/` or `mobile/` (deployment is stage 2).

## Cell map

| Cell | Phase | What it does | Main outputs |
|---|---|---|---|
| 01 | 0 | imports, seeds, device | — |
| 02 | 0 | portable paths, `ml/src` imports | `ml/` directory tree |
| 03 | 1 STEP 1 | manifest + size check of the fetched files, pairs S/V, schema and physics audit | — |
| 04 | 1 STEP 2 | wall-clock S<->V pairing, yaw-rate clock lag, mount-yaw estimate, vehicle-frame remap, cleaning | `cleaned/iovnbd_cleaned_10hz.parquet`, `cleaned/trip_audit.json`, `01_sampling_jitter_before_after.png` |
| 05 | 1 STEP 3 | integrity gate, quality gate, trip-level split | `01_dataset_summary.json` |
| 06 | 1.2 | 13-channel features (contract unchanged) | — |
| 07 | 1.2 | windows (20 samples @ 10 Hz, stride 2) per split, leak checks | `splits/dataset_splits.json`, `02_speed_distribution_splits.png` |
| 08 | 1.3 | classical baselines on the held-out windows | `03_classical_baseline_metrics.json`, `03_classical_dr_trajectory_drift.png` |
| 09-10 | 2 | scaler fitted on train windows only, window shards | `scalers/imu_feature_scaler.json` + `.pkl`, `windows/*.npz`, `04_*.png` |
| 11-12 | 2 | `SpeedEstimatorNet` (unchanged architecture), heteroscedastic Huber loss | — |
| 13 | 2 | training: warmup + cosine, grad clip 1.0, early stopping (patience 5), <= 20 min | `speed_model_best.pth` |
| 14 | 2 | held-out MAE / RMSE / R2 (per trip, per speed band), calibration, baselines on the same windows | `05_speed_estimator_evaluation.json`, `05_*.png` |
| 14b | 2 | IO-VNBD held-out position reconstruction and drift (30 s, 60 s, ~1 km) | `11_iovnbd_position_drift.json`, `11_iovnbd_position_<trip>.png` |
| 15-17 | 2.3 | `VibrationClassifierNet` (v2 recipe, proxy labels) | `06_*` |
| 18-19 | 2.4 | `MotionQualityNet` (v2 recipe, proxy labels) | `07_*` |
| 20-22 | 3 | AI + adaptive UKF outage demo (v2 simulation on a held-out segment) | `08_*` |
| 23-24 | 4 | GNSS anomaly gating demo | `09_*` |
| 25 | 5 | ONNX export (skipped with a message if the exporter is unavailable) | `models/*/exported/*.onnx` |
| 26 | 5 | TFLite conversion: **skipped** (stage 2; needs tensorflow) — the `.tflite` next to the ONNX is the stale v2 model | — |
| 27 | 5 | ONNX parity (needs onnxruntime) and CPU latency | `10_model_benchmarks_and_parity.json` |
| 28 | 5 | hand-off metadata | `models/speed_estimator/exported/model_metadata_v3.0.json` |

## What v3.0 changed (data pipeline)

1. **Ground truth = VBOX**: 10 Hz speed, position and heading. The phone's own "GPS SPEED (Kmh)" column is in m/s, is held between fixes (median 9 s) and lags
   the VBOX by 3-4 s, so it is only used for the baselines.
2. **Synchronisation** ([`ml/src/dataset/sync.py`](../src/dataset/sync.py)): "synchronised" only means the authors trimmed both files by hand. Phone rows are
   re-paired by wall-clock time (phone `DATE` column vs VBOX GPS time of day, whole-hour timezone removed), then the remaining clock offset is measured
   by cross-correlating the phone vertical gyro (the column named **"Pitch"**) with the VBOX yaw rate. A trip keeps its own offset when it is statistically
   clear, otherwise it borrows the median of its recording session.
3. **Axes**: the phone lies flat (gravity on z) at an arbitrary yaw per trip. The mount yaw is estimated from the horizontal acceleration against the VBOX
   forward/lateral acceleration and applied **once**, in `sync.phone_to_vehicle`, giving the vehicle frame (ax forward, ay left, az up + gravity, gz yaw rate
   counter-clockwise positive) that the app also feeds the model.
4. **Quality gate** ([`ml/src/dataset/build.py`](../src/dataset/build.py)): trips shorter than 30 s, trips whose clock cannot be verified, trips not shown to be the
   same drive (yaw rate unverified *and* phone GPS speed correlation < 0.8) and trips without a mount estimate are excluded; each exclusion and its reason is
   listed in `01_dataset_summary.json`. Only trips whose **own** yaw rate verified the clock (`eval_eligible`) may be used for validation and test.
5. **Split** (trip level, deterministic): test = whole drivers **B** and **D** + the whole category **Vtb**; validation = one eval-eligible trip per remaining category;
   train = the rest. A window never crosses a trip or a gap segment (asserted in Cell 07). The scaler is fitted on train windows only.

## Stage-2 hand-over (search the notebook for `TODO(v3.1 stage 2)`)

* Vibration and motion-quality labels are **proxies computed from the input itself** (or from the speed model's error on its own training windows): their scores
  are not evidence. Replace them with labels tied to real events / road classes and evaluate on the held-out trips.
* The UKF outage demo and the GNSS anomaly detector are v2 simulations. The real IO-VNBD outage evidence is the position-drift table of Cell 14b.
* ONNX -> TFLite (`ml/src/export/onnx_to_tflite.py`, needs tensorflow) and copying model + metadata into the app are not done here.
* Contract notes for the app: jerk features are `(a[t] - a[t-1]) / 0.1 s` in training (the Dart `MlSpeedEstimator` uses the raw per-frame difference), and pitch/roll are
  computed from the levelled accelerometer (`atan2(ax, sqrt(ay^2+az^2))`, `atan2(ay, az)`), not passed as 0.
