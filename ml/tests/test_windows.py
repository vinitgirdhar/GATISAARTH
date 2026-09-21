"""Tests for the 13-channel features, trip-level splits and leak-free windowing (synthetic tables)."""
import numpy as np
import pandas as pd
import pytest

from ml.src.dataset import windows as w


def toy_table(seg_lengths=((40, 60), (25,)), speeds=None):
    """Two trips 'A' (two segments) and 'B' (one), rows contiguous within a segment."""
    rows = []
    for trip, segs in zip(("A", "B"), seg_lengths):
        for sid, n in enumerate(segs):
            k = np.arange(n)
            rows.append(pd.DataFrame({
                "trip_id": trip, "seg_id": sid, "ax": np.sin(k / 5.0), "ay": 0.1 * k, "az": 9.8 + 0.01 * k,
                "gx": 0.0 * k, "gy": 0.0 * k, "gz": 0.01 * k, "speed_ms": 1.0 * k + 100 * sid + (1000 if trip == "B" else 0)}))
    return pd.concat(rows, ignore_index=True)


def test_features_shape_and_order():
    n = 30
    f = w.compute_13_channel_features(*(np.random.default_rng(0).normal(size=(6, n))))
    assert f.shape == (n, 13) and len(w.FEATURE_NAMES) == 13
    assert w.FEATURE_NAMES[:6] == ["ax", "ay", "az", "gx", "gy", "gz"]


def test_features_are_causal():
    rng = np.random.default_rng(1)
    ch = rng.normal(size=(6, 40))
    a = w.compute_13_channel_features(*ch)
    ch2 = ch.copy()
    ch2[:, 25:] += 5.0  # change the future
    b = w.compute_13_channel_features(*ch2)
    assert np.allclose(a[:25], b[:25])


def test_jerk_is_backward_difference_over_dt():
    ax = np.array([0.0, 1.0, 3.0, 3.0])
    f = w.compute_13_channel_features(ax, ax * 0, ax * 0 + 9.8, ax * 0, ax * 0, ax * 0)
    assert np.allclose(f[:, 8], [0.0, 10.0, 20.0, 0.0])  # (a[t]-a[t-1])/0.1, first sample has no predecessor


def test_windows_never_straddle_segments_or_trips():
    t = toy_table()
    X, y, meta = w.make_windows(t, stride=1)
    assert X.shape[1:] == (20, 13) and len(X) == len(y) == len(meta)
    # (40-19) + (60-19) + (25-19) windows
    assert len(X) == 21 + 41 + 6
    for start, stop, trip, seg in zip(meta["start"], meta["stop"], meta["trip_id"], meta["seg_id"]):
        rows = t.iloc[start:stop]
        assert stop - start == 20 and (rows.trip_id == trip).all() and (rows.seg_id == seg).all()


def test_window_label_is_speed_of_last_sample():
    t = toy_table()
    X, y, meta = w.make_windows(t, stride=2)
    for start, stop, yy in zip(meta["start"], meta["stop"], y):
        assert yy == t.speed_ms.iloc[stop - 1]


def trips(spec):
    return [dict(trip_id=k, category=c, driver=d, valid_samples=n, included=inc, eval_eligible=inc and ev)
            for k, c, d, n, inc, ev in spec]


def test_split_holds_out_drivers_and_categories_and_is_disjoint():
    spec = [("M", "M", "B", 1000, True, True), ("Y1", "Y", "D", 800, True, True),
            ("S1", "S", "A", 500, True, True), ("S2", "S", "A", 900, True, True), ("S3", "S", "A", 130, True, True),
            ("S4", "S", "A", 470, True, False),
            ("Vtb1", "Vtb", "E", 300, True, True), ("Vtb2", "Vtb", "E", 200, True, False),
            ("Vw1", "Vw", "E", 700, True, True), ("Vw2", "Vw", "E", 100, True, False), ("Vx", "Vw", "E", 50, False, False)]
    split, rules = w.assign_splits(trips(spec), test_drivers=("B", "D"), test_categories=("Vtb",), val_fraction=0.12)
    assert {split[k] for k in ("M", "Y1", "Vtb1")} == {"test"}
    assert "Vtb2" not in split and rules["held_out_group_trips_dropped_unverified"] == ["Vtb2"]
    assert "Vx" not in split                                # excluded trips get no split
    assert split["S3"] == "val"                             # 130/2000 is the eval-eligible S trip closest to 12 %
    assert split["S4"] == "train" and split["Vw2"] == "train"
    assert set(split.values()) == {"train", "val", "test"}
    assert rules["test_drivers"] == ["B", "D"]


def test_split_never_puts_all_trips_of_a_category_in_val():
    spec = [("S1", "S", "A", 100, True, True), ("S2", "S", "A", 100, True, True)]
    split, _ = w.assign_splits(trips(spec), test_drivers=(), test_categories=(), val_fraction=0.9)
    assert sorted(split.values()) == ["train", "val"]


def test_split_needs_an_eval_eligible_trip_for_val():
    spec = [("S1", "S", "A", 100, True, False), ("S2", "S", "A", 100, True, False)]
    split, _ = w.assign_splits(trips(spec), test_drivers=(), test_categories=())
    assert set(split.values()) == {"train"}
