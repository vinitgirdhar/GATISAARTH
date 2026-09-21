"""Build the synchronised, cleaned 10 Hz IO-VNBD table (one row per VBOX sample) plus a per-trip audit record.

Pipeline per trip:  read S+V  ->  wall-clock alignment (`sync.align_to_vbox`)  ->  residual clock lag from the yaw
rate (own, else recording-session median)  ->  mount yaw theta (own, else pooled over the recording session)  ->
phone-to-vehicle remap  ->  3-tap median + physical clipping  ->  gate.  A trip that fails the gate never reaches
train/val/test; the reasons are kept.  Two tiers: `included` (may be trained on) and `eval_eligible` (may also be
used for validation/test: its own yaw rate verified the phone clock).
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
from scipy.signal import medfilt

from . import iovnbd as io
from . import sync

MIN_SAMPLES = 300               # a trip needs >= 30 s of valid data
SAME_DRIVE_SPEED_CORR = 0.80    # phone GPS speed vs VBOX speed (any lag within +-15 s): are the two logs one drive?
THETA_MIN_Z = 3.0               # z = rho * sqrt(n/50) needed to trust a mount yaw estimate
STATIONARY_MAX_MS = 1.0
SPEED_JUMP_MS = 3.0             # |dv| per 0.1 s above this is a VBOX glitch (30 m/s^2)
ACC_CLIP, GYRO_CLIP, SPEED_CLIP = 25.0, 10.0, 55.0
CLEAN_COLS = ["ax", "ay", "az", "gx", "gy", "gz"]
KEY_VBOX = ["v_speed_kmh", "v_lat", "v_lon", "v_heading", "v_yaw_dps"]


def _raw_stats(trip: io.Trip, s: pd.DataFrame, v: pd.DataFrame) -> dict:
    """Facts about the raw pair that the audit reports (before any alignment)."""
    t_ms = s["t_ms"].to_numpy(float)
    dt_wall = np.diff(s["wall_s"].to_numpy(float))
    inner = dt_wall[(dt_wall > np.nanpercentile(dt_wall, 1)) & (dt_wall < np.nanpercentile(dt_wall, 99))]
    changed = (s["gps_lat"].diff().fillna(1) != 0) | (s["gps_lon"].diff().fillna(1) != 0)
    fix_idx = np.flatnonzero(changed.to_numpy())
    imu = s[sync.IMU_COLS].to_numpy(float)
    return {
        "size_mb": round((trip.s_path.stat().st_size + trip.v_path.stat().st_size) / 1e6, 2),
        "rows_phone": int(len(s)), "rows_vbox": int(len(v)), "rows_equal": bool(len(s) == len(v)),
        "phone_dt_ms_median": float(np.nanmedian(dt_wall) * 1000),
        "phone_dt_ms_std_1_99pct": float(np.nanstd(inner) * 1000),
        "phone_dt_hist_5ms": np.histogram(np.clip(dt_wall * 1000, 0, 399.9), bins=np.arange(0, 405, 5))[0].tolist(),
        "phone_wall_backwards": int(np.sum(dt_wall <= 0)),
        "phone_gaps_over_1s": int(np.sum(dt_wall > 1.0)),
        "phone_timestamp_col_backwards_jumps": int(np.sum(np.diff(t_ms) < 0)),
        "vbox_dt_glitches": int(np.sum(np.abs(np.diff(v["v_time_s"].to_numpy(float)) - 0.1) > 0.011)),
        "gps_fix_interval_s_median": round(float(np.median(np.diff(fix_idx)) * sync.DT), 2) if len(fix_idx) > 2 else None,
        "nan_phone_imu": int(np.isnan(imu).sum()), "nan_vbox_key": int(np.isnan(v[KEY_VBOX].to_numpy(float)).sum()),
        "phone_gravity_mean": [round(float(s[c].mean()), 3) for c in ("grav_x", "grav_y", "grav_z")],
    }


def _speed_stats(speed_ms: np.ndarray) -> dict:
    v = speed_ms[np.isfinite(speed_ms)]
    return {"distance_km": round(float(v.sum() * sync.DT / 1000.0), 3), "mean_kmh": round(float(v.mean() * 3.6), 2),
            "p95_kmh": round(float(np.percentile(v, 95) * 3.6), 1), "max_kmh": round(float(v.max() * 3.6), 1),
            "stationary_frac": round(float((v < 0.3).mean()), 3)}


def _speed_consistency(al: sync.Aligned) -> tuple[float, float]:
    """(corr, lag_s) of the phone GPS speed (m/s, as recorded) against the VBOX speed within +-15 s."""
    ref = al.vbox["v_speed_kmh"].to_numpy(float) / 3.6
    lag, corr = sync.xcorr_lag(ref, al.phone["gps_speed_ms"].to_numpy(float), 150)
    return corr, lag * sync.DT


def analyse_trip(trip: io.Trip) -> dict:
    """Everything that does not need the other trips: raw facts, wall-clock alignment, yaw lag, GPS consistency."""
    s, v = io.read_csv_pair(trip)
    rec: dict = {"trip_id": trip.trip_id, "category": trip.category, "driver": trip.driver,
                 "session": f"{trip.category}-{int(s['wall_day'].dropna().iloc[0])}"}
    rec.update(_raw_stats(trip, s, v))
    m = min(len(s), len(v))
    naive = sync.Aligned(t=np.arange(m) * sync.DT, phone=s.iloc[:m][sync.IMU_COLS + sync.HELD_COLS].reset_index(drop=True),
                         vbox=v.iloc[:m].reset_index(drop=True), info={"mode": "row"})
    yaw_row = np.deg2rad(naive.vbox["v_yaw_dps"].to_numpy(float))
    rec["row_pairing_yaw"] = dict(zip(("lag", "corr"), sync.xcorr_lag(yaw_row, naive.phone[sync.YAW_GYRO_COL].to_numpy(float), 150)))
    rec["row_pairing_speed_corr"], rec["row_pairing_speed_lag_s"] = _speed_consistency(naive)
    al = sync.align_to_vbox(s, v)
    rec["sync"] = dict(al.info)
    rec["yaw_lag"] = sync.yaw_lag_record(al)
    yaw = np.deg2rad(al.vbox["v_yaw_dps"].to_numpy(float))
    rec["yaw_col_corr"] = {c: round(sync.xcorr_lag(yaw, al.phone[c].to_numpy(float), 60)[1], 3)
                           for c in ("gyro_yaw_col", "gyro_pitch_col", "gyro_roll_col")}
    rec["gps_speed_corr"], rec["gps_speed_lag_s"] = _speed_consistency(al)
    gps = al.phone["gps_speed_ms"].to_numpy(float)
    vb = al.vbox["v_speed_kmh"].to_numpy(float) / 3.6
    mv = np.isfinite(gps) & (vb > 3)
    rec["gps_speed_over_vbox_ms"] = round(float(np.median(gps[mv] / vb[mv])), 3) if mv.sum() > 20 else None
    rec.update(_speed_stats(vb))
    rec["_aligned"] = al
    return rec


def prepare_trip(rec: dict, lag: int, lag_source: str) -> dict:
    """Apply the clock lag, build the validity mask and the mount-yaw sufficient statistics of one trip."""
    al = sync.shift_phone(rec.pop("_aligned"), lag)
    rec["lag_used_samples"], rec["lag_source"] = int(lag), lag_source
    ph, vb = al.phone, al.vbox
    speed = np.clip(vb["v_speed_kmh"].to_numpy(float) / 3.6, 0.0, SPEED_CLIP)
    finite = np.isfinite(ph[sync.IMU_COLS].to_numpy(float)).all(axis=1) & np.isfinite(vb[KEY_VBOX].to_numpy(float)).all(axis=1)
    jump = np.r_[False, np.abs(np.diff(np.nan_to_num(speed))) > SPEED_JUMP_MS]
    valid = finite & ~jump
    a_long, a_lat = sync.vbox_truth_accels(speed, vb["v_yaw_dps"].to_numpy(float))
    moving = valid & (speed > 2.0)
    rec["_mount_stats"] = sync.mount_stats(np.where(moving, ph["acc_x"], np.nan), np.where(moving, ph["acc_y"], np.nan),
                                           a_long, a_lat)
    rec["_prep"] = {"al": al, "speed": speed, "valid": valid}
    return rec


def _gps_age(lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
    """Seconds since the phone GPS position last changed (i.e. since the last fix) on the VBOX grid."""
    changed = np.r_[True, (np.diff(lat) != 0) | (np.diff(lon) != 0)] | ~np.isfinite(lat)
    last = np.maximum.accumulate(np.where(changed, np.arange(len(lat)), 0))
    return (np.arange(len(lat)) - last) * sync.DT


def finish_trip(rec: dict, session_stats: dict) -> dict:
    """Choose theta (own > session > unverified), remap to the vehicle frame, clean, gate. `_frame` is None when the
    trip is excluded."""
    prep = rec.pop("_prep")
    al, speed, valid = prep["al"], prep["speed"], prep["valid"]
    ph, vb = al.phone, al.vbox
    own_theta, own_rho, own_z = sync.mount_from_stats(rec.pop("_mount_stats"))
    ses_theta, ses_rho, ses_z = sync.mount_from_stats(session_stats)
    if own_z >= THETA_MIN_Z:
        theta, mount_src = own_theta, "own"
    elif ses_z >= THETA_MIN_Z:
        theta, mount_src = ses_theta, "session"
    else:
        theta, mount_src = 0.0, "unverified"
    rec["mount"] = {"source": mount_src, "theta_deg_used": round(float(np.degrees(theta)), 1),
                    "own": {"theta_deg": round(float(np.degrees(own_theta)), 1), "rho": round(own_rho, 3), "z": round(own_z, 1)},
                    "session": {"theta_deg": round(float(np.degrees(ses_theta)), 1), "rho": round(ses_rho, 3), "z": round(ses_z, 1)}}
    veh = sync.phone_to_vehicle(*(ph[c].to_numpy(float) for c in ("acc_x", "acc_y", "acc_z", "gyro_yaw_col",
                                                                  "gyro_pitch_col", "gyro_roll_col")), theta=theta)
    first = int(np.flatnonzero(valid)[0]) if valid.any() else 0
    east, north = io.local_xy(vb["v_lat"].to_numpy(float), vb["v_lon"].to_numpy(float),
                              float(vb["v_lat"].iloc[first]), float(vb["v_lon"].iloc[first]))
    frame = pd.DataFrame({
        "trip_id": rec["trip_id"], "t": al.t, **veh, "speed_ms": speed,
        "gps_speed_ms": ph["gps_speed_ms"].to_numpy(float),
        "gps_age_s": _gps_age(ph["gps_lat"].to_numpy(float), ph["gps_lon"].to_numpy(float)),
        "heading_deg": vb["v_heading"].to_numpy(float), "yaw_dps": vb["v_yaw_dps"].to_numpy(float),
        "east_m": east, "north_m": north})
    seg_id = np.full(len(frame), -1, np.int32)
    for k, (a, b) in enumerate(sync.valid_segments(valid, sync.MIN_SEG)):
        seg_id[a:b] = k
    frame["seg_id"] = seg_id
    frame = frame[frame.seg_id >= 0].reset_index(drop=True)
    rec["valid_samples"] = int(len(frame))
    stationary = rec["max_kmh"] / 3.6 < STATIONARY_MAX_MS
    gps_ok = rec["gps_speed_corr"] is not None and rec["gps_speed_corr"] >= SAME_DRIVE_SPEED_CORR
    reasons = []
    if len(frame) < MIN_SAMPLES:
        reasons.append("fewer than 30 s of valid synchronised samples")
    if not stationary and rec["lag_source"] == "unverified":
        reasons.append("phone clock offset could not be verified from the yaw rate (own or recording session)")
    if not stationary and rec["lag_source"] != "own" and not gps_ok:
        reasons.append(f"not shown to be the same drive: yaw rate unverified and phone GPS speed corr "
                       f"{rec['gps_speed_corr']:.2f} < {SAME_DRIVE_SPEED_CORR}")
    if not stationary and mount_src == "unverified":
        reasons.append("phone mount yaw could not be estimated (forward axis unknown)")
    rec["stationary"] = bool(stationary)
    rec["included"] = not reasons
    rec["eval_eligible"] = bool(rec["included"] and not stationary and rec["lag_source"] == "own")
    rec["exclusion_reasons"] = reasons
    return {**rec, "_frame": None if reasons else _clean(frame)}


def _clean(frame: pd.DataFrame) -> pd.DataFrame:
    """3-tap median + physical clipping per segment (v2 cleaning recipe)."""
    out = frame.copy()
    for _, idx in out.groupby("seg_id").indices.items():
        for c in CLEAN_COLS:
            out.iloc[idx, out.columns.get_loc(c)] = medfilt(out[c].to_numpy()[idx], 3)
    for c in ("ax", "ay", "az"):
        out[c] = out[c].clip(-ACC_CLIP, ACC_CLIP)
    for c in ("gx", "gy", "gz"):
        out[c] = out[c].clip(-GYRO_CLIP, GYRO_CLIP)
    return out


def build_synced_dataset(raw_root: Path, progress=print) -> tuple[pd.DataFrame, list[dict]]:
    """All trips -> (cleaned table of the included trips, per-trip records of every trip)."""
    trips = io.discover_trips(raw_root)
    recs = []
    for i, trip in enumerate(trips, 1):
        recs.append(analyse_trip(trip))
        if progress and i % 24 == 0:
            progress(f"  analysed {i}/{len(trips)} trips")
    lags = sync.choose_lags([{"trip_id": r["trip_id"], "session": r["session"], **r["yaw_lag"]} for r in recs])
    recs = [prepare_trip(r, *lags[r["trip_id"]]) for r in recs]
    pooled = {s: sync.pool_mount_stats([r["_mount_stats"] for r in recs if r["session"] == s])
              for s in {r["session"] for r in recs}}
    finished = [finish_trip(r, pooled[r["session"]]) for r in recs]
    frames = [r["_frame"] for r in finished if r["_frame"] is not None]
    for r in finished:
        r.pop("_frame")
    table = pd.concat(frames, ignore_index=True)
    meta = {r["trip_id"]: (r["category"], r["driver"]) for r in finished}
    table["category"] = table.trip_id.map(lambda k: meta[k][0]).astype("category")
    table["driver"] = table.trip_id.map(lambda k: meta[k][1]).astype("category")
    return table, finished
