"""Held-out evaluation on IO-VNBD: speed metrics, baselines on the same windows, dead-reckoning position drift.

Everything works on the cleaned table (`ml.src.dataset.build`) and the window index (`windows.make_windows`), with
VBOX as ground truth.  Baselines are evaluated in the GNSS-outage protocol: every 30 s block of a segment starts from
the phone GPS speed as recorded (which is stale, see the dataset audit) and the GPS is then unavailable for the block.
"""
from __future__ import annotations

from typing import Callable

import numpy as np
import pandas as pd
from scipy.stats import spearmanr

DT = 0.1
KMH = 3.6
BAND_EDGES_KMH = (0, 10, 30, 60, 90, 250)
ZUPT_WINDOW = 10            # samples (1 s)
ZUPT_STD_MS2 = 0.15         # rolling std of |a| below this ...
ZUPT_GYRO_RAD_S = 0.02      # ... and rolling mean |yaw rate| below this = stationary
ZUPT_MAX_SPEED_MS = 2.0     # ... and the speed estimate is already this low (else a smooth cruise reads as a stop)


def speed_metrics(y, p) -> dict:
    y, p = np.asarray(y, float), np.asarray(p, float)
    e = p - y
    ss_tot = float(np.sum((y - y.mean()) ** 2))
    r2 = 1.0 - float(np.sum(e ** 2)) / ss_tot if ss_tot > 0 else float("nan")
    mae, rmse = float(np.mean(np.abs(e))), float(np.sqrt(np.mean(e ** 2)))
    return {"n": int(len(y)), "mae_m_s": mae, "rmse_m_s": rmse, "mae_km_h": mae * KMH, "rmse_km_h": rmse * KMH,
            "r2": r2, "bias_m_s": float(e.mean()), "median_abs_err_m_s": float(np.median(np.abs(e))),
            "p90_abs_err_m_s": float(np.percentile(np.abs(e), 90)), "p95_abs_err_m_s": float(np.percentile(np.abs(e), 95))}


def band_table(y, p, edges_kmh=BAND_EDGES_KMH) -> list[dict]:
    y, p = np.asarray(y, float), np.asarray(p, float)
    kmh = y * KMH
    rows = []
    for lo, hi in zip(edges_kmh[:-1], edges_kmh[1:]):
        m = (kmh >= lo) & (kmh < hi)
        if m.sum() == 0:
            continue
        e = p[m] - y[m]
        rows.append({"band_kmh": f"{lo}-{hi}", "n": int(m.sum()), "mae_m_s": float(np.mean(np.abs(e))),
                     "rmse_m_s": float(np.sqrt(np.mean(e ** 2))), "bias_m_s": float(e.mean())})
    return rows


def per_trip_table(trip_ids, y, p) -> dict:
    trip_ids = np.asarray(trip_ids)
    return {str(t): speed_metrics(np.asarray(y)[trip_ids == t], np.asarray(p)[trip_ids == t]) for t in sorted(set(trip_ids))}


def calibration(y, p, sigma, n_bins: int = 5) -> dict:
    """Does the predicted sigma track the actual error?"""
    err = np.asarray(p, float) - np.asarray(y, float)
    sigma = np.asarray(sigma, float)
    ae = np.abs(err)
    rho = float(spearmanr(ae, sigma).statistic)
    edges = np.quantile(sigma, np.linspace(0, 1, n_bins + 1))
    bins = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = (sigma >= lo) & (sigma <= hi)
        bins.append({"sigma_range_m_s": [float(lo), float(hi)], "n": int(m.sum()), "mean_sigma_m_s": float(sigma[m].mean()),
                     "mean_abs_err_m_s": float(ae[m].mean()), "rmse_m_s": float(np.sqrt(np.mean(err[m] ** 2)))})
    return {"spearman_abs_err_vs_sigma": rho, "coverage_1_sigma": float(np.mean(ae <= sigma)),
            "coverage_2_sigma": float(np.mean(ae <= 2 * sigma)), "z_std": float(np.std(err / sigma)),
            "mean_sigma_m_s": float(sigma.mean()), "mean_abs_err_m_s": float(ae.mean()), "sigma_quintile_table": bins}


# ------------------------------------------------------------------ baselines on windows
def _segment_first_rows(table: pd.DataFrame) -> np.ndarray:
    codes = pd.factorize(table["trip_id"])[0]
    seg = table["seg_id"].to_numpy()
    new = np.r_[True, (codes[1:] != codes[:-1]) | (seg[1:] != seg[:-1])]
    return np.maximum.accumulate(np.where(new, np.arange(len(table)), 0))


def _anchor_rows(table: pd.DataFrame, meta: pd.DataFrame, block_s: float) -> tuple[np.ndarray, np.ndarray]:
    first = _segment_first_rows(table)
    end = meta["stop"].to_numpy() - 1
    b = int(round(block_s / DT))
    return end, first[end] + ((end - first[end]) // b) * b


def baseline_hold_gps(table: pd.DataFrame, meta: pd.DataFrame, block_s: float = 30.0) -> np.ndarray:
    """GNSS outage of `block_s`: the speed of the last phone GPS reading before the block, held."""
    _, anchor = _anchor_rows(table, meta, block_s)
    return table["gps_speed_ms"].to_numpy(float)[anchor]


def stationary_flags(table: pd.DataFrame) -> np.ndarray:
    """Heuristic stationarity used by the classical baseline: 1 s rolling std of |a| and mean |yaw rate| both small."""
    ay = table["ay"].to_numpy(float) if "ay" in table else 0.0
    norm = np.sqrt(table["ax"].to_numpy(float) ** 2 + ay ** 2 + table["az"].to_numpy(float) ** 2)
    std = pd.Series(norm).rolling(ZUPT_WINDOW, min_periods=ZUPT_WINDOW).std().to_numpy()
    gyro = pd.Series(np.abs(table["gz"].to_numpy(float))).rolling(ZUPT_WINDOW, min_periods=ZUPT_WINDOW).mean().to_numpy()
    return (std < ZUPT_STD_MS2) & (gyro < ZUPT_GYRO_RAD_S)


def integrate_forward(ax: np.ndarray, quiet: np.ndarray, v0: float, zupt_max_speed: float = ZUPT_MAX_SPEED_MS) -> np.ndarray:
    """Speed after each sample: v <- 0 when flagged stationary AND v < zupt_max_speed, else max(0, v + ax*dt)
    (classical DR with heuristic ZUPT)."""
    v = np.empty(len(ax))
    cur = max(v0, 0.0)
    for k in range(len(ax)):
        cur = 0.0 if (quiet[k] and cur < zupt_max_speed) else max(0.0, cur + ax[k] * DT)
        v[k] = cur
    return v


def baseline_classical_dr(table: pd.DataFrame, meta: pd.DataFrame, block_s: float = 30.0) -> np.ndarray:
    """Classical DR in the outage protocol: from the block's GPS-anchored speed, integrate the forward accelerometer
    (no bias estimate, no gravity model beyond the levelled frame) with the heuristic ZUPT above (only below 2 m/s)."""
    end, anchor = _anchor_rows(table, meta, block_s)
    ax, quiet = table["ax"].to_numpy(float), stationary_flags(table)
    gps = table["gps_speed_ms"].to_numpy(float)
    out = np.empty(len(meta))
    order = np.argsort(anchor, kind="stable")
    i = 0
    while i < len(order):                      # group windows by block, integrate each block once up to its last window
        j = i
        while j < len(order) and anchor[order[j]] == anchor[order[i]]:
            j += 1
        idx = order[i:j]
        a0, last = int(anchor[idx[0]]), int(end[idx].max())
        v = integrate_forward(ax[a0 + 1:last + 1], quiet[a0 + 1:last + 1], gps[a0])
        v = np.r_[gps[a0], v]                  # v[r] = speed at row a0 + r
        out[idx] = v[end[idx] - a0]
        i = j
    return out


def naive_double_integration(table_seg: pd.DataFrame) -> dict:
    """The v2 notebook baselines on one whole segment: unaided double integration and per-sample heuristic ZUPT."""
    ax, gz = table_seg["ax"].to_numpy(float), table_seg["gz"].to_numpy(float)
    truth = float(np.sum(table_seg["speed_ms"].to_numpy(float)) * DT)
    naive_dist = float(np.sum(np.cumsum(ax * DT) * DT))
    v = np.zeros(len(ax))
    for k in range(1, len(ax)):
        v[k] = 0.0 if (abs(ax[k]) < 0.15 and abs(gz[k]) < 0.05) else max(0.0, v[k - 1] + ax[k] * DT)
    zupt_dist = float(np.sum(v) * DT)
    return {"duration_s": round(len(ax) * DT, 1), "true_distance_m": round(truth, 1),
            "naive_double_integration_error_pct": round(abs(naive_dist - truth) / max(truth, 1e-3) * 100, 1),
            "heuristic_zupt_error_pct": round(abs(zupt_dist - truth) / max(truth, 1e-3) * 100, 1)}


# ------------------------------------------------------------------ dead-reckoning position drift
def hold_gps_window(seg: pd.DataFrame, i0: int, i1: int) -> np.ndarray:
    """Speed over samples i0+1..i1 for an outage starting at i0: the last phone GPS speed held."""
    return np.full(i1 - i0, float(seg["gps_speed_ms"].iloc[i0]))


def classical_dr_window(seg: pd.DataFrame, i0: int, i1: int) -> np.ndarray:
    quiet = stationary_flags(seg.iloc[max(0, i0 - ZUPT_WINDOW):i1 + 1])[ZUPT_WINDOW if i0 >= ZUPT_WINDOW else i0:][1:]
    return integrate_forward(seg["ax"].to_numpy(float)[i0 + 1:i1 + 1], quiet[:i1 - i0], float(seg["gps_speed_ms"].iloc[i0]))


def _headings(seg: dict, i0: int, i1: int, mode: str) -> np.ndarray:
    h = seg["heading"]
    if mode == "vbox_heading":
        return h[i0 + 1:i1 + 1]
    return h[i0] - np.degrees(np.cumsum(seg["gz"][i0 + 1:i1 + 1] * DT))     # yaw rate is CCW positive, compass is CW


def dr_displacement(v: np.ndarray, heading_deg: np.ndarray) -> tuple[float, float]:
    h = np.radians(heading_deg)
    return float(np.sum(v * np.sin(h)) * DT), float(np.sum(v * np.cos(h)) * DT)


def dr_track(seg: pd.DataFrame, i0: int, i1: int, speed, mode: str) -> tuple[np.ndarray, np.ndarray]:
    """Cumulative (east, north) metres of a DR outage over samples i0..i1 starting at the origin."""
    s = {"heading": seg["heading_deg"].to_numpy(float), "gz": seg["gz"].to_numpy(float)}
    v = speed(seg, i0, i1) if callable(speed) else np.asarray(speed, float)[i0 + 1:i1 + 1]
    h = np.radians(_headings(s, i0, i1, mode))
    return np.r_[0.0, np.cumsum(v * np.sin(h) * DT)], np.r_[0.0, np.cumsum(v * np.cos(h) * DT)]


def _summ(pcts: list[float], skipped: int, dists: list[float], durs: list[float]) -> dict:
    if not pcts:
        return {"n_windows": 0, "skipped_slow_or_missing": skipped}
    a = np.asarray(pcts)
    return {"n_windows": int(len(a)), "median_pct": float(np.median(a)), "mean_pct": float(a.mean()),
            "p90_pct": float(np.percentile(a, 90)), "share_under_10_pct": float(np.mean(a < 10.0)),
            "median_distance_m": float(np.median(dists)), "median_duration_s": float(np.median(durs)),
            "skipped_slow_or_missing": skipped}


def drift_over_windows(table: pd.DataFrame, speed_pred: dict, horizons_s=(30, 60), stride_s: float = 10.0,
                       min_mean_speed: float = 3.0, distance_windows_m=(1000.0,), first_valid: int = 19) -> dict:
    """Final-position drift, as % of the distance travelled, of DR outages that start every `stride_s` seconds.

    speed_pred: {name: per-row speed array (NaN = no prediction) | callable(seg, i0, i1) -> speeds of samples i0+1..i1}.
    Headings: 'vbox_heading' (VBOX compass heading) and 'phone_heading' (VBOX heading at the outage start, then the phone
    yaw-rate integrated).  Windows with a mean true speed below `min_mean_speed` m/s are skipped (percent of ~0 m is noise).
    Returns {name: {heading: {"30s": stats, "1000m": stats}}}.
    """
    acc = {n: {m: {} for m in ("vbox_heading", "phone_heading")} for n in speed_pred}
    stride = int(round(stride_s / DT))
    for (trip, seg_id), idx in table.groupby(["trip_id", "seg_id"], sort=False).indices.items():
        seg = table.iloc[idx]
        n = len(seg)
        truth_v = seg["speed_ms"].to_numpy(float)
        cum_d = np.r_[0.0, np.cumsum(truth_v[1:] * DT)]
        east, north = seg["east_m"].to_numpy(float), seg["north_m"].to_numpy(float)
        seg_arrays = {k: (v if callable(v) else np.asarray(v, float)[idx]) for k, v in speed_pred.items()}
        windows = [(f"{int(h)}s", i0, i0 + int(round(h / DT))) for h in horizons_s for i0 in range(first_valid, n, stride)]
        for d in distance_windows_m:
            for i0 in range(first_valid, n, stride):
                i1 = int(np.searchsorted(cum_d, cum_d[i0] + d))
                windows.append((f"{int(d)}m", i0, i1 if i1 < n else n + 1))
        sarr = {"heading": seg["heading_deg"].to_numpy(float), "gz": seg["gz"].to_numpy(float)}
        for label, i0, i1 in windows:
            for name, spd in seg_arrays.items():
                for mode in ("vbox_heading", "phone_heading"):
                    bucket = acc[name][mode].setdefault(label, {"p": [], "d": [], "t": [], "skip": 0})
                    if i1 >= n:
                        continue                                              # window does not fit in the segment
                    dist = cum_d[i1] - cum_d[i0]
                    if dist / ((i1 - i0) * DT) < min_mean_speed:
                        bucket["skip"] += 1
                        continue
                    v = spd(seg, i0, i1) if callable(spd) else spd[i0 + 1:i1 + 1]
                    if not np.all(np.isfinite(v)):
                        bucket["skip"] += 1
                        continue
                    de, dn = dr_displacement(v, _headings(sarr, i0, i1, mode))
                    err = np.hypot(de - (east[i1] - east[i0]), dn - (north[i1] - north[i0]))
                    bucket["p"].append(100.0 * err / dist)
                    bucket["d"].append(dist)
                    bucket["t"].append((i1 - i0) * DT)
    return {n: {m: {lab: _summ(b["p"], b["skip"], b["d"], b["t"]) for lab, b in acc[n][m].items()}
                for m in acc[n]} for n in acc}
