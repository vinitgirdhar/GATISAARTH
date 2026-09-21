"""Tests for the phone<->VBOX alignment helpers (synthetic signals, no dataset needed)."""
import numpy as np
import pandas as pd
import pytest

from ml.src.dataset import sync


def smooth_random(n, seed=0, corr=4):
    rng = np.random.default_rng(seed)
    x = rng.normal(size=n + 6 * corr)
    k = np.exp(-np.arange(-3 * corr, 3 * corr + 1) ** 2 / (2 * corr ** 2))
    return np.convolve(x, k / k.sum(), mode="same")[3 * corr: 3 * corr + n]


@pytest.mark.parametrize("shift", [0, 7, -12])
def test_xcorr_lag_recovers_shift(shift):
    ref = smooth_random(3000)
    sig = np.roll(ref, shift) * 0.9 + 0.05 * smooth_random(3000, seed=3, corr=2)  # sig[t + shift] = ref[t]
    lag, corr = sync.xcorr_lag(ref, sig, max_lag=40)
    assert lag == shift and corr > 0.9


def test_xcorr_lag_ignores_nans():
    ref = smooth_random(2000)
    sig = np.roll(ref, 5).copy()
    sig[100:180] = np.nan
    lag, corr = sync.xcorr_lag(ref, sig, max_lag=20)
    assert lag == 5 and corr > 0.9


def make_streams(n=600, tz_h=1, gap=None, phone_offset_s=0.0, rows_only=False):
    tv = 30000.0 + 0.1 * np.arange(n)
    v = pd.DataFrame({"v_time_s": tv, "v_speed_kmh": np.full(n, 36.0), "v_lat": 52.0 + 1e-6 * np.arange(n),
                      "v_lon": -1.5 + 0 * tv, "v_yaw_dps": 0 * tv, "v_heading": 0 * tv})
    rng = np.random.default_rng(1)
    tp = tv + 3600 * tz_h + phone_offset_s + rng.uniform(-0.002, 0.002, n)
    if rows_only:
        tp = tp + 5000.0
    sig = np.sin(tv / 3.0)
    s = pd.DataFrame({"wall_s": tp, "wall_day": 20190907.0, "acc_x": sig, "acc_y": 0 * sig, "acc_z": 9.8 + 0 * sig,
                      "gyro_yaw_col": 0 * sig, "gyro_pitch_col": 0 * sig, "gyro_roll_col": 0 * sig,
                      "gps_speed_ms": np.full(n, 10.0), "gps_acc_m": 4.0, "gps_lat": 52.0, "gps_lon": -1.5})
    if gap:
        s = s.drop(index=range(*gap)).reset_index(drop=True)
    return s, v, sig


def test_align_wallclock_interpolates_and_masks_gaps():
    s, v, sig = make_streams(gap=(200, 260))
    al = sync.align_to_vbox(s, v)
    assert al.info["mode"] == "wall" and al.info["tz_hours"] == 1
    ok = np.isfinite(al.phone["acc_x"].to_numpy())
    assert not ok[205:255].any() and ok[:190].all() and ok[270:].all()
    assert np.allclose(al.phone["acc_x"].to_numpy()[:190], sig[:190], atol=2e-3)
    assert al.info["phone_gaps"] == 1


def test_align_uses_wall_clock_offset_not_row_index():
    # the phone started 3.0 s after the VBOX: phone row 0 is VBOX row 30
    s, v, sig = make_streams(phone_offset_s=3.0)
    al = sync.align_to_vbox(s, v)
    x = al.phone["acc_x"].to_numpy()
    assert np.isnan(x[:29]).all() or np.isnan(x[:29]).mean() > 0.9  # no data before the phone started
    assert np.allclose(x[40:100], sig[10:70], atol=2e-3)


def test_align_falls_back_to_row_index_when_clocks_do_not_overlap():
    s, v, sig = make_streams(rows_only=True)
    s = s.assign(wall_s=s.wall_s + 20000.0)  # 5.5 h away: wall clocks can never be reconciled
    al = sync.align_to_vbox(s, v)
    assert al.info["mode"] == "row"
    assert np.allclose(al.phone["acc_x"].to_numpy(), sig)


def test_choose_lags_own_session_unverified():
    rec = [dict(trip_id="a", session="s1", lag=-3, corr=0.9, n=50000),
           dict(trip_id="b", session="s1", lag=-2, corr=0.4, n=20000),
           dict(trip_id="c", session="s1", lag=40, corr=0.05, n=800),     # weak -> session lag
           dict(trip_id="d", session="s2", lag=9, corr=0.02, n=800)]      # nothing to lean on
    out = sync.choose_lags(rec)
    assert out["a"] == (-3, "own") and out["b"] == (-2, "own")
    assert out["c"][1] == "session" and out["c"][0] in (-3, -2)
    assert out["d"] == (0, "unverified")


def test_estimate_mount_yaw_recovers_angle():
    rng = np.random.default_rng(0)
    a_long, a_lat = smooth_random(6000, 1), smooth_random(6000, 2)
    theta = np.radians(-37.0)
    c, s_ = np.cos(theta), np.sin(theta)
    # phone = R(theta)^T * vehicle:   a_long = c*px + s*py,  a_lat = -s*px + c*py
    px = c * a_long - s_ * a_lat
    py = s_ * a_long + c * a_lat
    px, py = px + 0.5 * rng.normal(size=6000), py + 0.5 * rng.normal(size=6000)
    est, rho = sync.estimate_mount_yaw(px, py, a_long, a_lat)
    assert abs(np.degrees(est) - (-37.0)) < 2.0 and rho > 0.15


def test_phone_to_vehicle_is_identity_at_theta_zero_and_rotates_accel():
    ax, ay, az = np.array([1.0]), np.array([0.0]), np.array([9.8])
    g = np.array([0.1]), np.array([0.2]), np.array([0.3])  # yaw_col, pitch_col, roll_col
    f0 = sync.phone_to_vehicle(ax, ay, az, *g, theta=0.0)
    assert (f0["ax"][0], f0["ay"][0], f0["az"][0]) == (1.0, 0.0, 9.8)
    assert f0["gz"][0] == 0.2  # the column labelled "Pitch" carries the yaw rate
    f = sync.phone_to_vehicle(ax, ay, az, *g, theta=np.pi / 2)  # forward axis is the phone's +y
    assert abs(f["ax"][0]) < 1e-12 and abs(f["ay"][0] + 1.0) < 1e-12


def test_mount_stats_pool_equals_joint_fit():
    rng = np.random.default_rng(3)
    a_long, a_lat = smooth_random(4000, 5), smooth_random(4000, 6)
    th = np.radians(25.0)
    c, s_ = np.cos(th), np.sin(th)
    px = c * a_long - s_ * a_lat + 0.4 * rng.normal(size=4000)
    py = s_ * a_long + c * a_lat + 0.4 * rng.normal(size=4000)
    half = lambda sl: sync.mount_stats(px[sl], py[sl], a_long[sl], a_lat[sl])
    pooled = sync.pool_mount_stats([half(slice(0, 2000)), half(slice(2000, 4000))])
    theta, rho, z = sync.mount_from_stats(pooled)
    assert abs(np.degrees(theta) - 25.0) < 2.0 and z > 3
    assert sync.mount_from_stats({"a": 0, "b": 0, "ee": 0, "pp": 0, "n": 3}) == (0.0, 0.0, 0.0)
