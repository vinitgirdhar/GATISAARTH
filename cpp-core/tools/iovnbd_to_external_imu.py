#!/usr/bin/env python3
"""Convert an IO-VNBD vehicle trip (V-*.csv, Racelogic VBOX + Ford Fiesta CAN bus, 10 Hz) to the
generic external-IMU CSV read by `replay_external_imu` (format: cpp-core/README.md).

What the output is (and is not)
* IMU   = the car's own ESP/CAN channels used as a vehicle-frame planar IMU: forward specific
          force = Indicated Longitudinal Acceleration, lateral (left) = Indicated Lateral
          Acceleration, vertical = local gravity, yaw rate = CAN yaw rate (counter-clockwise
          positive), roll/pitch rates = 0. Axes are FLU (x forward, y left, z up).
          THIS IS A PROXY for an external vehicle IMU, NOT a FOG or an industrial IMU: no
          roll/pitch/vertical channels, stability-control-grade sensors, 10 Hz, quantised.
* GNSS  = the VBOX position/speed/heading every `--gnss-period` seconds (default 1 s). With the
          default zero noise this mirrors ml/src/dataset/iovnbd_to_drive_log.py so the C++ engine
          and the Dart engine see the same GNSS; `--gnss-noise-*` adds seeded Gaussian noise.
* truth = the VBOX 10 Hz position (lat/lon), used only for scoring.
The phone (S-*.csv) IMU is deliberately not offered: its accelerometer is 10 Hz and aliased, its
accelerometer and gyro columns are in different frames and its clock has gaps; see
docs/evidence/edge_external_imu_and_200hz.md.

Sign conventions are measured, not assumed: the script prints the correlation of the CAN
longitudinal acceleration with dv/dt, of the lateral acceleration with v * yaw-rate, and of the
yaw rate with -d(heading)/dt, plus the at-rest scatter used to size the filter noise.

    python cpp-core/tools/iovnbd_to_external_imu.py --v-csv ".../V-S3c.csv" --out cpp-core/build-data/s3c.csv
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

G_STD = 9.80665


def load(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, encoding="latin1", skipinitialspace=True)
    df.columns = [re.sub(r"[^\x20-\x7e]", "?", c).strip() for c in df.columns]
    return df


def col(df: pd.DataFrame, prefix: str) -> np.ndarray:
    for c in df.columns:
        if c.upper().startswith(prefix.upper()):
            return pd.to_numeric(df[c], errors="coerce").to_numpy(dtype=float)
    raise KeyError(f"no column starting with {prefix!r} in {list(df.columns)[:5]}...")


def somigliana(lat_deg: float, height_m: float) -> float:
    s2 = math.sin(math.radians(lat_deg)) ** 2
    ecc2 = 6.69437999014e-3
    return 9.7803253359 * (1 + 0.00193185265241 * s2) / math.sqrt(1 - ecc2 * s2) - 3.086e-6 * height_m


def best_lag(a: np.ndarray, b: np.ndarray, max_lag: int = 20) -> tuple[int, float]:
    """Lag k (samples) maximising corr(a[i], b[i+k])."""
    best = (0, -2.0)
    for k in range(-max_lag, max_lag + 1):
        x, y = (a[: len(a) - k], b[k:]) if k >= 0 else (a[-k:], b[: len(b) + k])
        c = float(np.corrcoef(x, y)[0, 1])
        if c > best[1]:
            best = (k, c)
    return best


def diagnostics(t, v, yaw, long_acc, lat_acc, heading_deg, rest) -> None:
    dt = float(np.median(np.diff(t)))
    dv = np.gradient(v, t)
    dh = np.gradient(np.unwrap(np.radians(heading_deg)), t)
    moving = v > 3.0
    k, c = best_lag(yaw[moving], -dh[moving])
    print(f"[check] CAN yaw rate vs -d(heading)/dt: corr {np.corrcoef(yaw[moving], -dh[moving])[0, 1]:+.3f} "
          f"(best lag {k * dt:+.2f} s, corr {c:+.3f})", file=sys.stderr)
    print(f"[check] CAN longitudinal accel vs dv/dt: corr {np.corrcoef(long_acc[moving], dv[moving])[0, 1]:+.3f}",
          file=sys.stderr)
    print(f"[check] CAN lateral accel vs v*yaw-rate: corr {np.corrcoef(lat_acc[moving], (v * yaw)[moving])[0, 1]:+.3f}",
          file=sys.stderr)
    if rest.sum() > 100:
        print(f"[check] at rest ({rest.sum() / 10:.0f} s, v < 0.05 m/s): long mean {long_acc[rest].mean():+.3f} std "
              f"{long_acc[rest].std():.3f} m/s2 | lat mean {lat_acc[rest].mean():+.3f} std {lat_acc[rest].std():.3f} m/s2 | "
              f"yaw mean {yaw[rest].mean():+.5f} std {yaw[rest].std():.5f} rad/s", file=sys.stderr)


def convert(v_csv: Path, out: Path, max_seconds: float | None, start_seconds: float, gnss_period: float,
            noise_pos: float, noise_speed: float, noise_course: float, gnss_acc: float, gnss_altitude: bool,
            seed: int) -> dict:
    df = load(v_csv)
    tod = col(df, "Time Since Start of Day")
    lat, lon = col(df, "Latitude"), col(df, "Longitude")
    speed = col(df, "Velocity") / 3.6
    heading = col(df, "Heading")
    height = col(df, "Height")          # header says km, values are metres (Coventry ~ 100)
    yaw = np.radians(col(df, "Yaw Rate"))
    long_acc = col(df, "Indicated Longitudinal") * G_STD
    lat_acc = col(df, "Indicated Lateral") * G_STD

    ok = np.isfinite([tod, lat, lon, speed, heading, height, yaw, long_acc, lat_acc]).all(axis=0)
    keep = ok & np.r_[True, np.diff(tod) > 1e-6]      # strictly increasing time only
    tod, lat, lon, speed, heading, height, yaw, long_acc, lat_acc = (a[keep] for a in
        (tod, lat, lon, speed, heading, height, yaw, long_acc, lat_acc))
    t = tod - tod[0]
    sel = t >= start_seconds
    if max_seconds is not None:
        sel &= t < start_seconds + max_seconds
    tod, lat, lon, speed, heading, height, yaw, long_acc, lat_acc, t = (a[sel] for a in
        (tod, lat, lon, speed, heading, height, yaw, long_acc, lat_acc, t))
    t = t - t[0]
    diagnostics(t, speed, yaw, long_acc, lat_acc, heading, speed < 0.05)

    rng = np.random.default_rng(seed)
    g_local = somigliana(float(lat[0]), float(height[0]))
    n = len(t)
    frame = pd.DataFrame({
        "t": t, "ax": long_acc, "ay": lat_acc, "az": np.full(n, g_local),
        "gx": np.zeros(n), "gy": np.zeros(n), "gz": yaw,
        "truth_lat": lat, "truth_lon": lon,
    })
    # GNSS at the first sample of every `gnss_period` seconds.
    epoch = np.floor((t + 1e-9) / gnss_period).astype(int)
    is_fix = np.r_[True, np.diff(epoch) > 0]
    idx = np.flatnonzero(is_fix)
    m = 111_320.0
    glat = lat[idx] + rng.normal(0, noise_pos, len(idx)) / m
    glon = lon[idx] + rng.normal(0, noise_pos, len(idx)) / (m * math.cos(math.radians(lat[0])))
    gspd = np.maximum(0.0, speed[idx] + rng.normal(0, noise_speed, len(idx)))
    gcrs = (heading[idx] + rng.normal(0, noise_course, len(idx))) % 360.0
    gnss = pd.DataFrame({"gnss_lat": glat, "gnss_lon": glon,
                         "gnss_alt": height[idx] if gnss_altitude else np.nan,
                         "gnss_speed": gspd, "gnss_course": gcrs, "gnss_acc": gnss_acc}, index=idx)
    frame = frame.join(gnss)
    order = ["t", "ax", "ay", "az", "gx", "gy", "gz", "gnss_lat", "gnss_lon", "gnss_alt", "gnss_speed",
             "gnss_course", "gnss_acc", "truth_lat", "truth_lon"]
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", newline="\n") as f:
        f.write(f"# IO-VNBD {v_csv.name}: vehicle ESP/CAN channels as a planar external IMU (axes FLU), "
                f"GNSS = VBOX every {gnss_period:g} s (noise pos {noise_pos:g} m, speed {noise_speed:g} m/s, "
                f"course {noise_course:g} deg, seed {seed}), truth = VBOX 10 Hz\n")
        frame[order].to_csv(f, index=False, float_format="%.10g")
    dist = float(np.sum(0.5 * (speed[1:] + speed[:-1]) * np.diff(t)))
    return {"rows": n, "minutes": round(float(t[-1]) / 60, 1), "km": round(dist / 1000, 2), "fixes": int(len(idx)),
            "g_local": round(g_local, 4), "out": str(out)}


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--v-csv", type=Path, required=True, help="IO-VNBD V-*.csv (read as latin1)")
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--max-seconds", type=float, default=None)
    p.add_argument("--start-seconds", type=float, default=0.0)
    p.add_argument("--gnss-period", type=float, default=1.0, help="seconds between GNSS fixes")
    p.add_argument("--gnss-noise-pos", type=float, default=0.0, help="per-axis position noise, m")
    p.add_argument("--gnss-noise-speed", type=float, default=0.0, help="speed noise, m/s")
    p.add_argument("--gnss-noise-course", type=float, default=0.0, help="course noise, deg")
    p.add_argument("--gnss-acc", type=float, default=2.5, help="reported 1-sigma horizontal accuracy, m")
    p.add_argument("--gnss-altitude", action="store_true", help="include VBOX height as GNSS altitude")
    p.add_argument("--seed", type=int, default=1)
    a = p.parse_args(argv)
    info = convert(a.v_csv, a.out, a.max_seconds, a.start_seconds, a.gnss_period, a.gnss_noise_pos,
                   a.gnss_noise_speed, a.gnss_noise_course, a.gnss_acc, a.gnss_altitude, a.seed)
    print(info)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
