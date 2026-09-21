"""Gate + remap logic of ml/src/dataset/build.py on a synthetic trip with a known clock lag and mount yaw."""
import numpy as np
import pandas as pd
import pytest

from ml.src.dataset import build, sync


def synthetic_trip(n=6000, theta_deg=-40.0, lag=3, gps_ok=True, seed=0):
    rng = np.random.default_rng(seed)
    t = np.arange(n) * 0.1
    speed = 12 + 5 * np.sin(t / 13) + 3 * np.sin(t / 5.3 + 1)                    # m/s
    yaw_dps = 9 * np.sin(t / 7) + 4 * np.sin(t / 2.9)
    a_long, a_lat = sync.vbox_truth_accels(speed, yaw_dps)
    th = np.radians(theta_deg)
    c, s = np.cos(th), np.sin(th)
    px, py = c * a_long - s * a_lat, s * a_long + c * a_lat                     # phone horizontal frame (inverse of the remap)
    noise = lambda: 0.3 * rng.normal(size=n)
    late = lambda x: np.roll(x, lag)                                             # phone stream late by `lag` samples
    phone = pd.DataFrame({
        "acc_x": late(px + noise()), "acc_y": late(py + noise()), "acc_z": late(9.8 + 0.2 * rng.normal(size=n)),
        "gyro_yaw_col": late(0.02 * rng.normal(size=n)), "gyro_pitch_col": late(np.radians(yaw_dps) + 0.02 * rng.normal(size=n)),
        "gyro_roll_col": late(0.02 * rng.normal(size=n)),
        "gps_speed_ms": speed if gps_ok else rng.uniform(0, 30, n), "gps_acc_m": 4.0,
        "gps_lat": 52.0 + 1e-5 * np.floor(t), "gps_lon": -1.5 + 0 * t})
    vbox = pd.DataFrame({"v_time_s": 30000 + t, "v_speed_kmh": speed * 3.6, "v_lat": 52.0 + 1e-6 * np.cumsum(speed) * 0.1,
                         "v_lon": -1.5 + 1e-6 * np.cumsum(speed) * 0.1, "v_heading": 90.0 + 0 * t, "v_yaw_dps": yaw_dps})
    al = sync.Aligned(t=t, phone=phone, vbox=vbox, info={"mode": "wall", "overlap": 1.0})
    rec = {"trip_id": "T", "category": "X", "driver": "Z", "session": "X-1", "max_kmh": float(speed.max() * 3.6),
           "gps_speed_corr": 0.98 if gps_ok else 0.05, "_aligned": al}
    return rec, theta_deg, speed, a_long


def run(rec, lag, source):
    prepared = build.prepare_trip(rec, lag, source)
    return build.finish_trip(prepared, sync.pool_mount_stats([prepared["_mount_stats"]]))


def test_verified_trip_is_included_remapped_and_eval_eligible():
    rec, theta, speed, a_long = synthetic_trip()
    out = run(rec, 3, "own")
    assert out["included"] and out["eval_eligible"] and out["exclusion_reasons"] == []
    assert out["mount"]["source"] == "own" and abs(out["mount"]["theta_deg_used"] - theta) < 3.0
    frame = out["_frame"]
    assert frame is not None and {"ax", "ay", "az", "gz", "speed_ms", "seg_id", "east_m", "north_m"} <= set(frame.columns)
    keep = frame.index[frame.seg_id >= 0]
    assert np.corrcoef(frame.ax.to_numpy(), a_long[:len(frame)][:len(keep)])[0, 1] > 0.5   # forward channel follows the true forward acceleration
    assert abs(frame.az.mean() - 9.8) < 0.1
    assert frame.speed_ms.between(0, 55).all()


def test_wrong_lag_is_visible_in_the_correlation_used_by_the_lag_estimator():
    rec, *_ = synthetic_trip(lag=7)
    al = rec["_aligned"]
    got = sync.yaw_lag_record(al)
    assert got["lag"] == 7 and got["z"] > sync.OWN_LAG_Z


def test_unverified_clock_and_uncorrelated_gps_exclude_the_trip():
    rec, *_ = synthetic_trip(gps_ok=False)
    out = run(rec, 0, "session")
    assert not out["included"] and any("same drive" in r for r in out["exclusion_reasons"])
    assert out["_frame"] is None
    rec, *_ = synthetic_trip()
    out = run(rec, 0, "unverified")
    assert not out["included"] and any("clock offset" in r for r in out["exclusion_reasons"])


def test_session_lag_trip_can_train_but_not_validate_or_test():
    rec, *_ = synthetic_trip()
    out = run(rec, 3, "session")
    assert out["included"] and not out["eval_eligible"]


def test_short_trip_is_excluded():
    rec, *_ = synthetic_trip(n=200)
    out = run(rec, 3, "own")
    assert not out["included"] and any("30 s" in r for r in out["exclusion_reasons"])


def test_gps_age_counts_seconds_since_last_fix():
    lat = np.r_[np.full(10, 52.0), np.full(10, 52.1)]
    age = build._gps_age(lat, np.zeros(20))
    assert age[0] == 0 and age[9] == pytest.approx(0.9) and age[10] == 0 and age[19] == pytest.approx(0.9)
