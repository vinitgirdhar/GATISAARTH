"""Time alignment of the phone stream to the VBOX stream, mount-yaw estimation and the phone->vehicle axis remap.

What "synchronised" turned out to mean in IO-VNBD (measured, see `01_dataset_summary.json`):
  * S and V were trimmed by hand so that row i of S is roughly row i of V.  Row counts match in 63 of 72 trips,
    but pairing by row index is off by up to ~9 s (S2: 8.7 s) because the phone drops rows.
  * Both files carry wall-clock time (phone: DATE column in local time, VBOX: GPS time of day in UTC).
    Re-sampling the phone onto the VBOX 10 Hz grid by wall clock (whole-hour timezone offset removed) leaves a
    residual clock offset of a few tenths of a second (larger, but constant per recording session, for some
    sessions), which is estimated from the yaw rate: VBOX yaw rate vs the phone gyro column labelled "Pitch".
  * The phone GPS speed is not a usable clock reference: it is held between fixes for 1-10 s.

Everything here is pure numpy/pandas so it can be tested on synthetic data (`ml/tests/test_sync.py`).
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import pandas as pd
from scipy.signal import correlate, savgol_filter

DT = 0.1
MIN_SEG = 20            # runs of valid samples shorter than one 2 s window are dropped
GAP_S = 0.35            # a phone gap longer than this splits a trip into segments
EDGE_TOL_S = 0.05       # a VBOX sample this close outside the phone's time span still counts as covered
YAW_GYRO_COL = "gyro_pitch_col"   # the phone column labelled "Pitch" carries the yaw rate (CCW positive)
IMU_COLS = ["acc_x", "acc_y", "acc_z", "gyro_yaw_col", "gyro_pitch_col", "gyro_roll_col"]
HELD_COLS = ["gps_speed_ms", "gps_acc_m", "gps_lat", "gps_lon"]            # zero-order hold, never interpolated
N_EFF_SAMPLES = 50      # yaw rate decorrelates in ~5 s: heuristic effective-sample divisor for significance
OWN_LAG_Z = 3.0         # z = corr * sqrt(n / N_EFF_SAMPLES) needed to trust a trip's own lag


@dataclass
class Aligned:
    t: np.ndarray                 # seconds from the first VBOX sample, VBOX 10 Hz grid
    phone: pd.DataFrame           # phone channels on the VBOX grid (NaN where the phone has no data)
    vbox: pd.DataFrame            # VBOX channels (as recorded)
    info: dict = field(default_factory=dict)


def xcorr_lag(ref, sig, max_lag: int) -> tuple[int, float]:
    """Lag L in [-max_lag, max_lag] maximising corr(ref[t], sig[t+L]); L > 0 means `sig` is late by L samples.
    NaNs are ignored. Returns (L, correlation at L)."""
    ref = np.asarray(ref, float)
    sig = np.asarray(sig, float)
    ok = np.isfinite(ref) & np.isfinite(sig)
    if ok.sum() < 50:
        return 0, 0.0
    a = np.where(ok, ref - ref[ok].mean(), 0.0)
    b = np.where(ok, sig - sig[ok].mean(), 0.0)
    full = correlate(b, a, mode="full", method="fft")          # index k <-> lag k - (n-1)
    n = len(a)
    lags = np.arange(-max_lag, max_lag + 1)
    vals = full[lags + n - 1] / (ok.sum() * a[ok].std() * b[ok].std() + 1e-12)
    best = int(np.argmax(np.abs(vals)))
    return int(lags[best]), float(vals[best])


def _unwrap_day(x: np.ndarray) -> np.ndarray:
    """Add 86400 s after each midnight roll-over of a seconds-of-day clock."""
    dx = np.diff(np.where(np.isfinite(x), x, np.nan))
    return x + 86400.0 * np.cumsum(np.r_[0, np.nan_to_num(dx) < -43200])


def fix_vbox_time(tv: np.ndarray) -> np.ndarray:
    """Repair the rare duplicated VBOX timestamps (x, x, x+0.2 -> x, x+0.1, x+0.2)."""
    tv = _unwrap_day(np.asarray(tv, float))
    good = np.isfinite(tv) & np.r_[True, np.diff(tv) > 0]
    return np.interp(np.arange(len(tv)), np.flatnonzero(good), tv[good])


def align_to_vbox(s: pd.DataFrame, v: pd.DataFrame, min_overlap: float = 0.5) -> Aligned:
    """Put the phone channels on the VBOX 10 Hz grid by wall-clock time (falls back to row index when the two
    wall clocks cannot be reconciled, `info['mode'] == 'row'`)."""
    n_v = len(v)
    tv = fix_vbox_time(v["v_time_s"].to_numpy(float))
    info = {"rows_phone": int(len(s)), "rows_vbox": int(n_v)}
    wall = _unwrap_day(s["wall_s"].to_numpy(float))
    row_ok = np.isfinite(wall)
    row_ok[row_ok] = np.r_[True, np.diff(wall[row_ok]) > 0]     # strictly increasing wall clock only
    m = min(len(s), n_v)
    tz = int(np.round(np.nanmedian(wall[:m] - tv[:m]) / 3600.0)) if row_ok.any() else 0
    tp = wall[row_ok] - 3600.0 * tz
    valid = np.zeros(n_v, bool)
    if len(tp) > 1:
        idx = np.clip(np.searchsorted(tp, tv), 1, len(tp) - 1)
        valid = (tv >= tp[0] - EDGE_TOL_S) & (tv <= tp[-1] + EDGE_TOL_S) & ((tp[idx] - tp[idx - 1]) <= GAP_S)
    info["phone_gaps"] = int(np.sum(np.diff(tp) > GAP_S)) if len(tp) > 1 else 0
    info["phone_max_gap_s"] = round(float(np.max(np.diff(tp))), 2) if len(tp) > 1 else None
    info["start_offset_s"] = round(float(tp[0] - tv[0]), 2) if len(tp) else None   # phone log start minus VBOX start
    phone = {}
    if valid.mean() >= min_overlap:
        info.update(mode="wall", tz_hours=tz, overlap=round(float(valid.mean()), 4))
        idx = np.clip(np.searchsorted(tp, tv, side="right") - 1, 0, len(tp) - 1)
        for c in IMU_COLS:
            phone[c] = np.where(valid, np.interp(tv, tp, s[c].to_numpy(float)[row_ok]), np.nan)
        for c in HELD_COLS:
            phone[c] = np.where(valid, s[c].to_numpy(float)[row_ok][idx], np.nan)
    else:
        info.update(mode="row", tz_hours=None, overlap=round(float(valid.mean()), 4))
        for c in IMU_COLS + HELD_COLS:
            col = np.full(n_v, np.nan)
            col[:m] = s[c].to_numpy(float)[:m]
            phone[c] = col
    return Aligned(t=tv - tv[0], phone=pd.DataFrame(phone), vbox=v.reset_index(drop=True), info=info)


def yaw_lag_record(al: Aligned, max_lag: int | None = None) -> dict:
    """Residual clock offset of the phone: lag (samples) of the phone yaw gyro against the VBOX yaw rate."""
    max_lag = max_lag or (60 if al.info["mode"] == "wall" else 150)
    ref = np.deg2rad(al.vbox["v_yaw_dps"].to_numpy(float))
    sig = al.phone[YAW_GYRO_COL].to_numpy(float)
    lag, corr = xcorr_lag(ref, sig, max_lag)
    n = int((np.isfinite(ref) & np.isfinite(sig)).sum())
    return {"lag": lag, "corr": corr, "n": n, "z": abs(corr) * np.sqrt(n / N_EFF_SAMPLES)}


def choose_lags(records: list[dict]) -> dict[str, tuple[int, str]]:
    """records: dicts with trip_id, session, lag, corr, n. A trip keeps its own lag when it is statistically clear
    (z >= OWN_LAG_Z); otherwise it takes the weighted median lag of the clear trips of its recording session;
    otherwise it is 'unverified' (lag 0, to be excluded by the caller)."""
    for r in records:
        r["z"] = abs(r["corr"]) * np.sqrt(r["n"] / N_EFF_SAMPLES)
    own = [r for r in records if r["z"] >= OWN_LAG_Z]
    out: dict[str, tuple[int, str]] = {}
    for r in records:
        if r["z"] >= OWN_LAG_Z:
            out[r["trip_id"]] = (int(r["lag"]), "own")
            continue
        mates = [q for q in own if q["session"] == r["session"]]
        out[r["trip_id"]] = (_weighted_median([q["lag"] for q in mates], [q["n"] * q["corr"] ** 2 for q in mates]),
                             "session") if mates else (0, "unverified")
    return out


def _weighted_median(values: list[float], weights: list[float]) -> int:
    order = np.argsort(values)
    v = np.asarray(values)[order]
    cw = np.cumsum(np.asarray(weights)[order])
    return int(v[np.searchsorted(cw, cw[-1] / 2.0)])


def shift_phone(al: Aligned, lag: int) -> Aligned:
    """phone'[t] = phone[t + lag]: removes the phone clock offset (lag > 0: the phone stream was late)."""
    info = dict(al.info, lag_samples=int(lag))
    return Aligned(t=al.t, phone=al.phone.shift(-int(lag)), vbox=al.vbox, info=info)


def vbox_truth_accels(speed_ms: np.ndarray, yaw_dps: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Vehicle-frame longitudinal / lateral acceleration (forward, left) from the VBOX: d(speed)/dt and speed*yaw rate."""
    v = np.nan_to_num(np.asarray(speed_ms, float))
    a_long = savgol_filter(np.gradient(v, DT), 11, 2)
    a_lat = v * np.deg2rad(np.nan_to_num(np.asarray(yaw_dps, float)))
    return a_long, a_lat


def mount_stats(px, py, a_long, a_lat) -> dict:
    """Additive sufficient statistics of the 2-D Procrustes fit of the phone's horizontal acceleration (px, py) to
    the VBOX (forward, left) acceleration; statistics of several trips can simply be summed (`pool_mount_stats`)."""
    px, py, tl, tt = (np.asarray(x, float) for x in (px, py, a_long, a_lat))
    ok = np.isfinite(px) & np.isfinite(py) & np.isfinite(tl) & np.isfinite(tt)
    px, py = px[ok] - px[ok].mean(), py[ok] - py[ok].mean()
    tl, tt = tl[ok] - tl[ok].mean(), tt[ok] - tt[ok].mean()
    return {"a": float(np.sum(tl * px + tt * py)), "b": float(np.sum(tl * py - tt * px)),
            "ee": float(np.sum(tl ** 2 + tt ** 2)), "pp": float(np.sum(px ** 2 + py ** 2)), "n": int(len(px))}         if len(px) >= 2 else {"a": 0.0, "b": 0.0, "ee": 0.0, "pp": 0.0, "n": 0}


def pool_mount_stats(stats: list[dict]) -> dict:
    return {k: sum(s[k] for s in stats) for k in ("a", "b", "ee", "pp", "n")}


def mount_from_stats(s: dict) -> tuple[float, float, float]:
    """(theta radians, rho, z): rho is the rotation-invariant correlation of the fit, z = rho*sqrt(n/N_EFF_SAMPLES)."""
    if s["n"] < 50:
        return 0.0, 0.0, 0.0
    rho = float(np.hypot(s["a"], s["b"]) / np.sqrt(s["ee"] * s["pp"] + 1e-12))
    return float(np.arctan2(s["b"], s["a"])), rho, rho * float(np.sqrt(s["n"] / N_EFF_SAMPLES))


def estimate_mount_yaw(px, py, a_long, a_lat) -> tuple[float, float]:
    """Yaw angle theta of the vehicle's forward axis in the phone's horizontal frame:
    a_long ~ cos(theta)*px + sin(theta)*py and a_lat ~ -sin(theta)*px + cos(theta)*py.  Returns (theta, rho)."""
    theta, rho, _ = mount_from_stats(mount_stats(px, py, a_long, a_lat))
    return theta, rho


def phone_to_vehicle(acc_x, acc_y, acc_z, gyro_yaw_col, gyro_pitch_col, gyro_roll_col, theta: float) -> dict:
    """THE phone -> vehicle axis remap (forward, left, up), used exactly once by the pipeline.

    Measured on IO-VNBD (Huawei P20 Pro, phone lying flat, screen up in every trip: mean gravity = (0, 0, +9.81)):
      * up is the phone's z axis (accelerometer includes gravity, as the app feeds the model),
      * the horizontal plane is rotated by a per-trip mount yaw `theta` (forward = (cos t, sin t) in phone x/y),
        estimated with `estimate_mount_yaw`; theta = 0 leaves the phone axes untouched,
      * the yaw rate (CCW positive, same sign as the VBOX yaw rate) is in the column labelled "Pitch";
        the two other gyro columns cannot be tied to a vehicle axis from this data and are passed on unrotated
        as gx (column "Roll") and gy (column "Yaw").
    The paper's Figure 2 draws x as the direction of travel; the data say the horizontal axes are only
    approximately aligned with the car, hence the estimated theta.
    """
    c, s = np.cos(theta), np.sin(theta)
    return {
        "ax": c * acc_x + s * acc_y, "ay": -s * acc_x + c * acc_y, "az": acc_z,
        "gx": gyro_roll_col, "gy": gyro_yaw_col, "gz": gyro_pitch_col,
    }


def valid_segments(valid: np.ndarray, min_len: int) -> list[tuple[int, int]]:
    """[start, stop) index pairs of the runs of True in `valid` that are at least `min_len` long."""
    edges = np.flatnonzero(np.diff(np.r_[False, valid, False].astype(np.int8)))
    return [(int(a), int(b)) for a, b in zip(edges[::2], edges[1::2]) if b - a >= min_len]
