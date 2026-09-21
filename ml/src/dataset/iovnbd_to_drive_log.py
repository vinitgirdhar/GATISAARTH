#!/usr/bin/env python3
"""Convert IO-VNBD synchronised smartphone + vehicle (VBOX) trips to GatiSaarth drive logs.

The app's replay engine and outage benchmark (`frontend/lib/core/nav/replay`,
`.../benchmark/outage_benchmark.dart`) read a JSONL drive log: one header line, then
raw phone-frame IMU lines (`t: i`), GNSS fixes (`t: g`) and, optionally, ground truth
(`t: r`). This script turns a real IO-VNBD trip into exactly that, so the SAME engine that
runs on the phone can be scored on public data:

* IMU   = the smartphone's accelerometer / gyroscope / magnetometer (10 Hz, phone frame);
* GNSS  = the Racelogic VBOX position at 1 Hz (``--gnss vbox``, default: a survey-grade-ish
          receiver, timely) or the phone's own 1 Hz GPS (``--gnss phone``: what a real phone
          log holds, but it reaches the log ~3-4 s late in this data);
* truth = the VBOX 10 Hz position / heading / speed (`t: r` lines).

A second mode, ``--imu vehicle``, builds the IMU from the vehicle's own ESP/CAN channels
(longitudinal and lateral acceleration, yaw rate) instead of the phone: a clean, planar,
vehicle-frame stand-in for an EXTERNAL IMU (not a FOG or an industrial IMU: it has no vertical
or roll/pitch channels and the accelerometers are the car's stability-control sensors). The
smartphone accelerometer in this dataset is 10 Hz and aliased - its horizontal axes explain
about 2 % of the variance of the VBOX acceleration (`docs/evidence/iovnbd_dataset_notes.md`) -
so the engine's mount alignment, which fits accelerations against the GNSS speed derivative,
cannot converge on it, correctly. Sign conventions were checked on real trips: longitudinal
acceleration correlates +0.63..+0.91 with dv/dt, lateral acceleration +0.91..+0.97 with
v * yaw-rate (both left / counter-clockwise positive, i.e. x forward, y left, z up).

Two facts about the data that this script measures instead of assuming (see
``docs/evidence/iovnbd_dataset_notes.md``):

1. The phone gyroscope's vertical (yaw) axis is the column named ``GYROSCOPE Pitch``:
   its best-lag cross-correlation with the VBOX yaw rate is 0.97 (trip M) and 0.94 (S1),
   against ~0.1 for the column named ``Yaw``. The other two columns are assigned
   x = ``Yaw``, y = ``Roll`` (an assumption; they only matter for tilt rates).
2. "Synchronised" is approximate. The IMU is shifted onto the VBOX clock by the lag that
   maximises the gyro/yaw-rate correlation, and a trip is only converted when that
   correlation clears ``--min-gyro-corr`` (some pairs are not aligned at all).

Usage::

    python ml/src/dataset/iovnbd_to_drive_log.py --all
    python ml/src/dataset/iovnbd_to_drive_log.py --trip "M (Driver B)" --gnss phone
"""

from __future__ import annotations

import argparse
import gzip
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[3]
DEFAULT_ROOT = (
    REPO / "ml/data/raw/IO-VNBD_repo/Synchronised V abd S datasets/Categorised IOVNB Dataset"
)
DEFAULT_OUT = REPO / "ml/data/processed/drive_logs"

#: The first record must not be at t = 0: the header is stamped 0 and the benchmark
#: takes the start of the drive from the first sensor line (see CLAUDE.md, field-test notes).
T0_US = 5_000_000
G = 9.80665
MAX_LAG_SAMPLES = 900  # +/- 90 s at 10 Hz


def _col(df: pd.DataFrame, *keys: str) -> str:
    for c in df.columns:
        upper = c.strip().upper()
        if all(k in upper for k in keys):
            return c
    raise KeyError(f"no column with {keys} in {list(df.columns)[:6]}...")


def _num(df: pd.DataFrame, *keys: str) -> np.ndarray:
    return pd.to_numeric(df[_col(df, *keys)], errors="coerce").to_numpy(dtype=float)


def best_lag(a: np.ndarray, b: np.ndarray, max_lag: int) -> tuple[int, float]:
    """Lag (samples) and correlation at which ``a[i + lag]`` best matches ``b[i]``.

    FFT cross-correlation, normalised per lag by the overlap, so a lag of a minute
    costs the same as a lag of a second.
    """
    from scipy.signal import fftconvolve

    ok = np.isfinite(a) & np.isfinite(b)
    a = np.where(ok, a, 0.0)
    b = np.where(ok, b, 0.0)
    a = (a - a[ok].mean()) / (a[ok].std() + 1e-12) * ok
    b = (b - b[ok].mean()) / (b[ok].std() + 1e-12) * ok
    n = len(a)
    full = fftconvolve(a, b[::-1], mode="full")  # index n-1+lag <-> a[i+lag] . b[i]
    lags = np.arange(-(n - 1), n)
    keep = (np.abs(lags) <= max_lag) & (n - np.abs(lags) >= 200)
    overlap = np.maximum(n - np.abs(lags), 1)
    score = np.where(keep, full / overlap, 0.0)
    i = int(np.argmax(np.abs(score)))
    return int(lags[i]), float(score[i])


def read_pair(s_csv: Path, v_csv: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    s = pd.read_csv(s_csv, encoding="latin1")
    v = pd.read_csv(v_csv, encoding="latin1")
    n = min(len(s), len(v))
    return s.iloc[:n].reset_index(drop=True), v.iloc[:n].reset_index(drop=True)


BLOCK = 3000  # 5 min of 10 Hz samples per local lag estimate
LOCAL_SEARCH = 80  # +/- 8 s around the global lag


def align(s: pd.DataFrame, v: pd.DataFrame) -> dict:
    """How the phone clock relates to the VBOX clock, and how well the pair correlates.

    A global lag first (the correlation peak over +/- 90 s), then a lag per 5-minute block
    around it: the two loggers' clocks drift apart over a multi-hour trip, so the shift is a
    straight line in time (least squares over the blocks that correlate), not one number.
    """
    gz = _num(s, "GYROSCOPE", "PITCH")  # the phone's vertical axis (see module docstring)
    yaw_rate = np.radians(_num(v, "YAW RATE"))  # counter-clockwise positive, like gz
    speed_v = _num(v, "VELOCITY") / 3.6
    speed_p = _num(s, "GPS SPEED") / 3.6
    lag0, corr0 = best_lag(gz, yaw_rate, MAX_LAG_SAMPLES)
    gps_lag, gps_corr = best_lag(speed_p, speed_v, MAX_LAG_SAMPLES)

    centres, lags = [], []
    for start in range(0, len(gz) - BLOCK, BLOCK // 2):
        lo, hi = start + lag0, start + lag0 + BLOCK
        if lo < 0 or hi > len(gz):
            continue
        lag, corr = best_lag(gz[lo:hi], yaw_rate[start:start + BLOCK], LOCAL_SEARCH)
        if abs(corr) >= 0.5:
            centres.append(start + BLOCK / 2)
            lags.append(lag0 + lag)
    slope, offset = 0.0, float(lag0)
    if len(centres) >= 4:
        c = np.asarray(centres)
        l = np.asarray(lags, dtype=float)
        keep = np.abs(l - np.median(l)) <= 30  # ignore blocks that latched onto a wrong peak
        if keep.sum() >= 4:
            slope, offset = np.polyfit(c[keep], l[keep], 1)
    return {
        "gyro_lag_samples": int(round(lag0)),
        "gyro_lag_offset_samples": round(float(offset), 2),
        "gyro_lag_drift_samples_per_hour": round(float(slope) * 36000.0, 2),
        "gyro_corr": round(abs(corr0), 3),
        "blocks_correlating": len(centres),
        "phone_gps_speed_lag_s": round(gps_lag / 10.0, 1),
        "phone_gps_speed_corr": round(abs(gps_corr), 3),
    }


def convert(
    s: pd.DataFrame,
    v: pd.DataFrame,
    quality: dict,
    out_path: Path,
    gnss: str,
    trip: str,
    max_seconds: float | None,
    gyro_map: tuple[str, str, str] = ("YAW", "ROLL", "PITCH"),
    gyro_sign: tuple[float, float, float] = (1.0, 1.0, 1.0),
) -> dict:
    t_ms = _num(s, "TIME SINCE START")
    keep = np.isfinite(t_ms)
    order = np.arange(len(t_ms))[keep]
    t_ms = t_ms[keep]
    # The IMU sits on the VBOX clock: shift it by the measured, drifting lag.
    slope = quality["gyro_lag_drift_samples_per_hour"] / 36000.0
    offset = quality["gyro_lag_offset_samples"]
    row = np.arange(len(t_ms))
    shift_us_arr = np.round(-(offset + slope * row) * 0.1 * 1e6).astype(np.int64)
    shift_us = int(np.median(shift_us_arr))

    ax, ay, az = (_num(s, "ACCELEROMETER", a)[keep] for a in "XYZ")
    g_cols = {k: _num(s, "GYROSCOPE", k)[keep] for k in ("YAW", "PITCH", "ROLL")}
    mx, my, mz = (_num(s, "MAGNETIC FIELD", a)[keep] for a in "XYZ")
    # gz must be the vertical axis ("Pitch" in every trip checked, see the docstring).
    gx, gy, gz = (gyro_sign[i] * g_cols[gyro_map[i]] for i in range(3))

    lat_v, lon_v = _num(v, "LATITUDE")[keep], _num(v, "LONGITUDE")[keep]
    hdg_v, vel_v = _num(v, "HEADING")[keep], _num(v, "VELOCITY")[keep] / 3.6
    sats_v = _num(v, "NO OF GPS SATELLITES")[keep]

    us = T0_US + ((t_ms - t_ms[0]) * 1000).astype(np.int64)
    lines: list[tuple[int, str]] = []
    n = len(us)
    limit_us = None if max_seconds is None else T0_US + int(max_seconds * 1e6)
    imu_ok = np.isfinite([ax, ay, az, gx, gy, gz]).all(axis=0)
    for i in range(n):
        if limit_us is not None and us[i] > limit_us:
            break
        if imu_ok[i]:
            rec = {
                "t": "i",
                "u": int(us[i]) + int(shift_us_arr[i]),
                "a": [float(ax[i]), float(ay[i]), float(az[i])],
                "g": [float(gx[i]), float(gy[i]), float(gz[i])],
            }
            if np.isfinite([mx[i], my[i], mz[i]]).all():
                rec["m"] = [float(mx[i]), float(my[i]), float(mz[i])]
            lines.append((rec["u"], json.dumps(rec, separators=(",", ":"))))
        if np.isfinite([lat_v[i], lon_v[i], hdg_v[i], vel_v[i]]).all():
            truth = {
                "t": "r",
                "u": int(us[i]),
                "lat": float(lat_v[i]),
                "lon": float(lon_v[i]),
                "hdg": float(hdg_v[i]) % 360.0,
                "spd": float(vel_v[i]),
            }
            lines.append((truth["u"], json.dumps(truth, separators=(",", ":"))))

    if gnss == "vbox":
        for i in range(0, n, 10):
            if limit_us is not None and us[i] > limit_us:
                break
            if not np.isfinite([lat_v[i], lon_v[i], vel_v[i], hdg_v[i]]).all():
                continue
            fix = {
                "t": "g", "u": int(us[i]),
                "lat": float(lat_v[i]), "lon": float(lon_v[i]),
                "acc": 2.5, "spd": float(vel_v[i]), "sac": 0.1,
                "brg": float(hdg_v[i]) % 360.0, "bac": 2.0,
            }
            if np.isfinite(sats_v[i]):
                fix["sat"] = int(sats_v[i])
            lines.append((fix["u"], json.dumps(fix, separators=(",", ":"))))
    else:
        lat_p, lon_p = _num(s, "GPS LATITUDE")[keep], _num(s, "GPS LONGITUDE")[keep]
        spd_p = _num(s, "GPS SPEED")[keep] / 3.6
        acc_p = _num(s, "GPS ACCURACY")[keep]
        brg_p = _num(s, "GPS ORIENTATION")[keep]
        last = None
        for i in range(n):
            if limit_us is not None and us[i] > limit_us:
                break
            key = (lat_p[i], lon_p[i])
            if key == last or not np.isfinite(key).all():
                continue
            last = key
            fix = {
                "t": "g", "u": int(us[i]),
                "lat": float(lat_p[i]), "lon": float(lon_p[i]),
                "acc": float(acc_p[i]) if np.isfinite(acc_p[i]) else 8.0,
                "spd": float(spd_p[i]) if np.isfinite(spd_p[i]) else 0.0,
                "brg": float(brg_p[i]) % 360.0 if np.isfinite(brg_p[i]) else None,
            }
            fix = {k: v_ for k, v_ in fix.items() if v_ is not None}
            lines.append((fix["u"], json.dumps(fix, separators=(",", ":"))))

    lines.sort(key=lambda pair: pair[0])  # stable: same-time records keep their order
    meta = {
        "t": "m", "u": 0,
        "sid": f"iovnbd-{trip}", "start": 0,
        "dev": "IO-VNBD smartphone (Huawei P20 Pro / Moto G7 Power / BlackBerry Priv)",
        "veh": "car", "mount": "phone holder, orientation unknown to the engine",
        "note": (f"IO-VNBD real trip; IMU shifted {shift_us / 1e6:+.1f} s (drifting "
                 f"{quality['gyro_lag_drift_samples_per_hour'] * 0.1:+.1f} s/h) onto the VBOX clock; "
                 f"GNSS = {'VBOX 1 Hz' if gnss == 'vbox' else 'phone GPS 1 Hz'}; "
                 "truth = VBOX 10 Hz"),
        "cfg": 1,
    }
    opener = gzip.open if out_path.suffix == ".gz" else open
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with opener(out_path, "wt", encoding="utf-8") as f:
        f.write(json.dumps(meta, separators=(",", ":")) + "\n")
        for _, text in lines:
            f.write(text + "\n")

    dist_km = float(np.nansum(np.clip(vel_v[1:], 0, 60) * 0.1) / 1000)
    return {
        "trip": trip,
        "file": rel(out_path),
        "rows": int(n),
        "minutes": round(n / 600.0, 1),
        "vbox_km": round(dist_km, 2),
        "gnss": gnss,
        **quality,
    }


def convert_vehicle(v: pd.DataFrame, out_path: Path, trip: str, gnss: str,
                    max_seconds: float | None, imu_hz: int = 10) -> dict:
    """Drive log whose IMU is the vehicle's ESP/CAN channels (planar, vehicle frame)."""
    t_s = _num(v, "TIME SINCE START OF DAY")
    lat, lon = _num(v, "LATITUDE"), _num(v, "LONGITUDE")
    hdg, vel = _num(v, "HEADING"), _num(v, "VELOCITY") / 3.6
    long_acc = _num(v, "INDICATED LONGITUDINAL") * G
    lat_acc = _num(v, "INDICATED LATERAL") * G
    yaw = np.radians(_num(v, "YAW RATE"))  # counter-clockwise positive
    sats = _num(v, "NO OF GPS SATELLITES")
    good = np.isfinite(t_s)
    n = len(t_s)
    us = T0_US + np.round((t_s - t_s[good][0]) * 1e6).astype(np.int64)
    limit_us = None if max_seconds is None else T0_US + int(max_seconds * 1e6)
    lines: list[tuple[int, str]] = []
    last_u = -1
    for i in range(n):
        if not good[i] or us[i] <= last_u:
            continue  # the log must be strictly increasing in time
        if limit_us is not None and us[i] > limit_us:
            break
        last_u = int(us[i])
        if np.isfinite([long_acc[i], lat_acc[i], yaw[i]]).all():
            # imu_hz > 10: linear interpolation towards the next sample (a stand-in
            # for a faster external IMU; the values stay those of the 10 Hz source).
            sub = max(1, imu_hz // 10)
            nxt = i + 1 if i + 1 < n and np.isfinite([long_acc[i + 1], lat_acc[i + 1], yaw[i + 1]]).all() else i
            for k in range(sub):
                w = k / sub
                u_k = last_u + int(round(w * (us[nxt] - us[i]))) if nxt != i else last_u + k * 100000 // sub
                rec = {"t": "i", "u": u_k,
                       "a": [float((1 - w) * long_acc[i] + w * long_acc[nxt]),
                             float((1 - w) * lat_acc[i] + w * lat_acc[nxt]), G],
                       "g": [0.0, 0.0, float((1 - w) * yaw[i] + w * yaw[nxt])]}
                lines.append((u_k, json.dumps(rec, separators=(",", ":"))))
        if np.isfinite([lat[i], lon[i], hdg[i], vel[i]]).all():
            truth = {"t": "r", "u": last_u, "lat": float(lat[i]), "lon": float(lon[i]),
                     "hdg": float(hdg[i]) % 360.0, "spd": float(vel[i])}
            lines.append((last_u, json.dumps(truth, separators=(",", ":"))))
            if i % 10 == 0:
                fix = {"t": "g", "u": last_u, "lat": float(lat[i]), "lon": float(lon[i]),
                       "acc": 2.5, "spd": float(vel[i]), "sac": 0.1,
                       "brg": float(hdg[i]) % 360.0, "bac": 2.0}
                if np.isfinite(sats[i]):
                    fix["sat"] = int(sats[i])
                lines.append((last_u, json.dumps(fix, separators=(",", ":"))))
    meta = {
        "t": "m", "u": 0, "sid": f"iovnbd-vehicle-{trip}", "start": 0,
        "dev": "IO-VNBD vehicle ESP/CAN channels as an external planar IMU (not a phone)",
        "veh": "car", "mount": "vehicle frame: x forward, y left, z up",
        "note": "IO-VNBD real trip; IMU = CAN longitudinal/lateral acceleration + yaw rate; "
                "GNSS = VBOX 1 Hz; truth = VBOX 10 Hz",
        "cfg": 1,
    }
    opener = gzip.open if out_path.suffix == ".gz" else open
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with opener(out_path, "wt", encoding="utf-8") as f:
        f.write(json.dumps(meta, separators=(",", ":")) + "\n")
        for _, text in lines:
            f.write(text + "\n")
    dist_km = float(np.nansum(np.clip(vel[1:], 0, 60) * 0.1) / 1000)
    return {"trip": trip, "file": rel(out_path),
            "imu": "vehicle", "rows": int(n), "minutes": round(n / 600.0, 1),
            "vbox_km": round(dist_km, 2), "gnss": gnss}


def rel(path: Path) -> str:
    """Path relative to the repo when it is inside it, else as given (scratch output)."""
    try:
        return str(path.relative_to(REPO)).replace("\\", "/")
    except ValueError:
        return str(path)


def discover(root: Path) -> list[tuple[str, Path, Path]]:
    pairs = []
    for s_csv in sorted(root.rglob("S-*.csv")):
        v_csv = s_csv.with_name("V-" + s_csv.name[2:])
        if v_csv.exists():
            trip = f"{s_csv.parent.relative_to(root)}/{s_csv.stem[2:]}".replace("\\", "/")
            pairs.append((trip, s_csv, v_csv))
    return pairs


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument("--trip", help="substring of the trip path, e.g. 'M (Driver B)'")
    p.add_argument("--all", action="store_true", help="convert every trip that passes the gate")
    p.add_argument("--gnss", choices=("vbox", "phone"), default="vbox")
    p.add_argument("--imu", choices=("phone", "vehicle"), default="phone",
                   help="phone IMU (needs the S file) or the vehicle CAN channels as an external IMU")
    p.add_argument("--min-gyro-corr", type=float, default=0.5,
                   help="gate: |corr| of phone yaw gyro vs VBOX yaw rate at the best lag")
    p.add_argument("--min-minutes", type=float, default=3.0)
    p.add_argument("--max-seconds", type=float, default=None)
    p.add_argument("--gz", action="store_true", help="write .jsonl.gz")
    p.add_argument("--imu-hz", type=int, default=10, choices=(10, 20, 50, 100),
                   help="vehicle mode: interpolate the 10 Hz channels up to this rate")
    p.add_argument("--gyro-map", default="YAW,ROLL,PITCH",
                   help="file columns for the phone gyro x,y,z (z must be the vertical axis)")
    p.add_argument("--gyro-sign", default="1,1,1", help="signs for x,y,z")
    args = p.parse_args(argv)

    if not (args.all or args.trip):
        p.error("give --trip or --all")
    pairs = [t for t in discover(args.root) if args.all or args.trip in t[0]]
    if not pairs:
        print(f"no trips found under {args.root}", file=sys.stderr)
        return 1

    manifest, skipped = [], []
    for trip, s_csv, v_csv in pairs:
        if args.imu == "vehicle":
            v = pd.read_csv(v_csv, encoding="latin1")
            if len(v) < args.min_minutes * 600:
                skipped.append({"trip": trip, "reason": f"only {len(v) / 600:.1f} min"})
                continue
            name = trip.replace("/", "__").replace(" ", "_").replace("(", "").replace(")", "")
            out = args.out / (name + (".jsonl.gz" if args.gz else ".jsonl"))
            info = convert_vehicle(v, out, trip, args.gnss, args.max_seconds, args.imu_hz)
            manifest.append(info)
            print(f"{trip}: {info['minutes']} min, {info['vbox_km']} km -> {info['file']}")
            continue
        s, v = read_pair(s_csv, v_csv)
        if len(s) < args.min_minutes * 600:
            skipped.append({"trip": trip, "reason": f"only {len(s) / 600:.1f} min"})
            continue
        q = align(s, v)
        if q["gyro_corr"] < args.min_gyro_corr:
            skipped.append({"trip": trip, "reason": "not aligned with the VBOX", **q})
            continue
        name = trip.replace("/", "__").replace(" ", "_").replace("(", "").replace(")", "")
        out = args.out / (name + (".jsonl.gz" if args.gz else ".jsonl"))
        info = convert(
            s, v, q, out, args.gnss, trip, args.max_seconds,
            tuple(args.gyro_map.split(",")),  # type: ignore[arg-type]
            tuple(float(x) for x in args.gyro_sign.split(",")),  # type: ignore[arg-type]
        )
        manifest.append(info)
        print(f"{trip}: {info['minutes']} min, {info['vbox_km']} km, gyro corr {q['gyro_corr']}, "
              f"IMU shift {-q['gyro_lag_offset_samples'] * 0.1:+.1f} s, drift "
              f"{q['gyro_lag_drift_samples_per_hour'] * 0.1:+.1f} s/h -> {info['file']}")
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "manifest.json").write_text(
        json.dumps({"converted": manifest, "skipped": skipped}, indent=2), encoding="utf-8")
    print(f"{len(manifest)} converted, {len(skipped)} skipped -> {args.out / 'manifest.json'}")
    return 0 if manifest else 1


if __name__ == "__main__":
    raise SystemExit(main())
