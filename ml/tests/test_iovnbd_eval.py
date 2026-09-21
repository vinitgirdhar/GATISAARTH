"""Tests for the held-out evaluation helpers: metrics, baselines on windows, dead-reckoning drift."""
import numpy as np
import pandas as pd
import pytest

from ml.src.evaluation import iovnbd_eval as ev


def test_speed_metrics_known_values():
    y = np.array([0.0, 10.0, 20.0])
    p = np.array([1.0, 10.0, 17.0])
    m = ev.speed_metrics(y, p)
    assert m["mae_m_s"] == pytest.approx(4 / 3) and m["rmse_m_s"] == pytest.approx(np.sqrt(10 / 3))
    assert m["mae_km_h"] == pytest.approx(4 / 3 * 3.6) and m["bias_m_s"] == pytest.approx(-2 / 3)
    assert m["r2"] == pytest.approx(1 - 10 / 200)


def test_band_table_partitions_by_true_speed():
    y = np.array([1.0, 2.0, 12.0, 30.0])           # m/s -> 3.6, 7.2, 43, 108 km/h
    p = y + 1.0
    rows = ev.band_table(y, p, edges_kmh=(0, 30, 60, 200))
    assert [r["n"] for r in rows] == [2, 1, 1] and all(r["mae_m_s"] == pytest.approx(1.0) for r in rows)


def test_calibration_perfect_sigma():
    rng = np.random.default_rng(0)
    sigma = rng.uniform(0.5, 4.0, 20000)
    err = rng.normal(size=20000) * sigma
    c = ev.calibration(np.zeros_like(err), err, sigma)
    assert c["spearman_abs_err_vs_sigma"] > 0.4
    assert 0.66 < c["coverage_1_sigma"] < 0.70 and 0.94 < c["coverage_2_sigma"] < 0.97
    assert 0.97 < c["z_std"] < 1.03


def make_segment(n=1200, v=10.0, vibration=True):
    az = 9.81 + (np.where(np.arange(n) % 2 == 0, 1.0, -1.0) if vibration else 0.0)
    return pd.DataFrame({
        "trip_id": "T", "seg_id": 0, "t": np.arange(n) * 0.1, "ax": np.zeros(n), "az": az, "gz": np.zeros(n),
        "speed_ms": np.full(n, v), "gps_speed_ms": np.full(n, v), "gps_age_s": np.zeros(n),
        "heading_deg": np.full(n, 90.0), "east_m": np.arange(n) * 0.1 * v, "north_m": np.zeros(n)})


def test_block_baselines_anchor_at_block_start():
    t = make_segment()
    t.loc[:, "gps_speed_ms"] = np.r_[np.full(300, 8.0), np.full(900, 12.0)]     # GPS speed jumps at the second block
    starts = np.array([0, 290, 400, 700])                                       # window ends 19, 309, 419, 719
    meta = pd.DataFrame({"start": starts, "stop": starts + 20, "trip_id": "T", "seg_id": 0})
    hold = ev.baseline_hold_gps(t, meta, block_s=30)
    assert list(hold) == [8.0, 12.0, 12.0, 12.0]                                # anchor = GPS speed at the block start
    dr = ev.baseline_classical_dr(t, meta, block_s=30)
    assert np.allclose(dr, hold)                                                # ax = 0: integration adds nothing


def test_classical_dr_integrates_forward_acceleration_and_zupt_stops():
    n = 600
    t = make_segment(n, v=5.0)
    t["ax"] = 0.5 + 0.0 * t["ax"]                                               # steady 0.5 m/s^2 with noise-free cruise
    t["ax"] += np.where(np.arange(n) % 2 == 0, 3.0, -3.0)                       # vibration, so ZUPT never fires
    meta = pd.DataFrame({"start": [0, 200], "stop": [20, 220], "trip_id": "T", "seg_id": 0})
    dr = ev.baseline_classical_dr(t, meta, block_s=30)
    assert dr[1] == pytest.approx(5.0 + 0.5 * 0.1 * 219, abs=0.5)               # v0 + sum(ax) dt (alternating noise cancels)
    q = make_segment(n, v=1.0, vibration=False)                                 # quiet phone at low speed: ZUPT -> zero speed
    assert ev.baseline_classical_dr(q, meta, block_s=30)[1] == 0.0
    fast = make_segment(n, v=8.0, vibration=False)                              # quiet but fast: a smooth cruise is not a stop
    assert ev.baseline_classical_dr(fast, meta, block_s=30)[1] == pytest.approx(8.0)


def test_dr_drift_zero_for_perfect_speed_and_heading():
    t = make_segment(1200, v=10.0)
    speed = t["speed_ms"].to_numpy().copy()
    out = ev.drift_over_windows(t, speed_pred={"perfect": speed}, horizons_s=(30,), stride_s=10, min_mean_speed=3.0)
    d = out["perfect"]["vbox_heading"]["30s"]
    assert d["n_windows"] >= 8 and d["median_pct"] == pytest.approx(0.0, abs=1e-6)


def test_dr_drift_scale_error_and_heading_bias():
    t = make_segment(1200, v=10.0)
    speed = t["speed_ms"].to_numpy() * 1.1                                      # 10 % too fast -> 10 % drift
    out = ev.drift_over_windows(t, {"fast": speed}, horizons_s=(30,), stride_s=10, min_mean_speed=3.0)
    assert out["fast"]["vbox_heading"]["30s"]["median_pct"] == pytest.approx(10.0, abs=0.01)
    t["gz"] = -0.02                                                             # gyro bias: heading grows 1.15 deg/s
    perfect = t["speed_ms"].to_numpy()
    out = ev.drift_over_windows(t, {"perfect": perfect}, horizons_s=(30,), stride_s=10, min_mean_speed=3.0)
    assert out["perfect"]["phone_heading"]["30s"]["median_pct"] > 5.0           # the gyro bias adds drift
    assert out["perfect"]["vbox_heading"]["30s"]["median_pct"] == pytest.approx(0.0, abs=1e-6)


def test_dr_one_km_window_uses_true_distance():
    t = make_segment(3000, v=10.0)                                              # 3 km in 300 s
    out = ev.drift_over_windows(t, {"perfect": t["speed_ms"].to_numpy()}, horizons_s=(), stride_s=10, min_mean_speed=3.0,
                                distance_windows_m=(1000.0,))
    d = out["perfect"]["vbox_heading"]["1000m"]
    assert d["n_windows"] > 10 and d["median_pct"] == pytest.approx(0.0, abs=1e-6)
    assert d["median_duration_s"] == pytest.approx(100.0, abs=0.2)
