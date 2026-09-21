# IO-VNBD in GatiSaarth: what the data really is (v3)

Facts measured on the real files. Nothing here is taken from the README alone.

## 1. What was in the folder

`IO-VNBD_DATASET/IO-VNBD-master` was downloaded without Git LFS: all 564 CSV, 161 JPG and both ZIP
files were 130-byte pointer stubs (`version https://git-lfs.github.com/spec/v1`, `oid sha256:`, `size`).
The real objects are public at `https://media.githubusercontent.com/media/onyekpeu/IO-VNBD/master/<path>`;
the response size and ETag equal the pointer's `size` and `oid`, and a downloaded file's SHA-256 matched.
`python ml/src/dataset/fetch_iovnbd.py` reads the pointers and fetches + verifies (size and SHA-256 of
every file) into the git-ignored `ml/data/raw/IO-VNBD_repo/` (the path the master notebook scans). The
default subset is `Synchronised V abd S datasets/Categorised IOVNB Dataset`: 144 CSV = 72 phone/vehicle
pairs, ~408 MB. `IO-VNBD_DATASET/` itself is never modified.

## 2. Layout

Five drivers: A (`S`, trips S1 S2 S3a S3b S3c S4), B (`M`), D (`Y`), E (`Vf`, `Vta`, `Vtb`, `Vw`).
`S-*.csv` = smartphone, 10 Hz IMU rows (accelerometer m/s², gyroscope rad/s, magnetometer µT, gravity,
orientation) with GPS repeating at 1 Hz; `V-*.csv` = vehicle: Racelogic VBOX position / velocity /
heading at 10 Hz plus CAN (wheel speeds, yaw rate, longitudinal / lateral acceleration in g, steering,
brake, engine). Row counts match in 63 of 72 pairs. The VBOX gives real ground truth for speed and
position (10 Hz, 0.1 km/h velocity resolution).

## 3. "Synchronised" is approximate

* **Phone GPS lags the VBOX by 2–11 s, and by a different amount per trip** (best cross-correlation of the
  phone's GPS speed with VBOX velocity: M 2.1 s, S1 4.2 s, S3c 4.0 s, S3a 11.3 s, S2 −4.2 s). Any phone-GPS
  target or truth carries that latency; the VBOX must be the truth.
* The IMU vs the VBOX clock is off by a per-trip constant and sometimes drifts: estimated from the
  vertical gyro against the VBOX yaw rate, M +0.4 s (−1.2 s/h), S1 +0.3 s, S2 +8.7 s, S3a −6.7 s,
  S3c +0.5 s (`iovnbd_to_drive_log.py`, `align()`).
* **Only 5 of 72 pairs pass a gyro-vs-yaw-rate gate (|corr| ≥ 0.5): M, S1, S2, S3a, S3c**
  (~520 min, ~289 km). The Driver E trips (Vta / Vtb / Vw / Vf) correlate 0.03–0.36 and Driver D's Y1
  (70,285 rows) not at all (speed corr 0.0), so a row-for-row pairing of those with the phone is not valid.
  36 pairs are shorter than 3 minutes.

## 4. The phone gyro's vertical axis is the column named "Pitch"

Best-lag correlation with the VBOX yaw rate: **Pitch 0.97 (M), 0.95 (S1), 0.996 (S3c)**; "Yaw" ≈ 0.1,
"Roll" ≈ −0.3. Gravity is on the accelerometer z axis (the phone lies flat), so this file's column names
do not follow the usual axis meaning; a notebook that maps "Yaw" to z (as v2 did) feeds the wrong axis.
Positive Pitch = counter-clockwise, like the VBOX yaw rate. The assignment of the other two columns to
x / y is an assumption (they only carry tilt rates; all eight assignments and signs were tried and none
changes the outcome below).

## 5. The phone accelerometer cannot be used to align the mount

The phone's horizontal accelerometer axes explain **0.3–1.7 % of the variance of the VBOX acceleration**
at the best lag (R² 0.003–0.017; per-axis std 1.0–1.3 m/s²): at 10 Hz the vibration is aliased into the
signal. The engine's mount alignment fits accelerations against the GNSS speed derivative and requires
R² ≥ 0.45, so on this data it never becomes calibrated, and refuses to lead ("The core never finished
aligning to the vehicle"), which is the correct behaviour on data that carries no usable forward-axis
information. Consequence for the evidence plan: the phone IMU is used where the data supports it — the
neural speed model (`ml/`), which learns from windows — and the engine is scored with the vehicle's own
ESP/CAN channels as an external-IMU proxy, which are clean (longitudinal acceleration correlates
+0.63…+0.91 with dv/dt, lateral acceleration +0.91…+0.97 with v·yaw-rate; x forward, y left, z up, yaw
rate counter-clockwise positive).

## 6. Converting a trip for the app's replay engine

`python ml/src/dataset/iovnbd_to_drive_log.py --all` (phone IMU, gated on alignment) or `--imu vehicle --all`
(external-IMU proxy, every trip ≥ 5 min) writes the app's JSONL drive-log format
(`ml/data/processed/drive_logs*/`, git-ignored): IMU lines, GNSS = VBOX 1 Hz (or the phone's own with
`--gnss phone`), and VBOX truth. `flutter test test/nav/score_drive_test.dart` (one log, `DRIVE_LOG=`) and
`test/nav/iovnbd_outage_benchmark_test.dart` (a folder, `IOVNBD_LOG_DIR=`) score them with the same
outage benchmark the phone runs on its own recordings.
