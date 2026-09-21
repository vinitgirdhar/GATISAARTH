"""13-channel features, leak-free trip-level splits and sliding windows for the IO-VNBD speed model.

Model contract (unchanged since v2, shared with the Dart app): one feature vector per 10 Hz sample, a window is
20 consecutive samples (2 s), the network maps [B, 20, 13] -> (speed m/s, log-variance).
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from numpy.lib.stride_tricks import sliding_window_view

WIN_LEN = 20
DT = 0.1
G_NOMINAL = 9.81
FEATURE_NAMES = ["ax", "ay", "az", "gx", "gy", "gz", "norm_a", "norm_g", "dax", "day", "daz", "pitch", "roll"]


def compute_13_channel_features(ax, ay, az, gx, gy, gz, dt: float = DT) -> np.ndarray:
    """(n, 13) features from vehicle-frame channels (accelerometer includes gravity). Causal: the jerk channels
    are backward differences (a[t]-a[t-1])/dt, the first sample of a run has jerk 0."""
    ax, ay, az, gx, gy, gz = (np.asarray(c, np.float64) for c in (ax, ay, az, gx, gy, gz))
    d = lambda a: np.r_[0.0, np.diff(a)] / dt
    norm_a = np.sqrt(ax ** 2 + ay ** 2 + az ** 2)
    norm_g = np.sqrt(gx ** 2 + gy ** 2 + gz ** 2)
    pitch = np.arctan2(ax, np.sqrt(ay ** 2 + az ** 2))
    roll = np.arctan2(ay, az)
    return np.column_stack([ax, ay, az, gx, gy, gz, norm_a, norm_g, d(ax), d(ay), d(az), pitch, roll])


def assign_splits(trips: list[dict], test_drivers=("B", "D"), test_categories=("Vtb",),
                  val_fraction: float = 0.12) -> tuple[dict[str, str], dict]:
    """Trip-level split. `trips`: dicts with trip_id, category, driver, valid_samples, included, eval_eligible.
    Rule (deterministic, no RNG):
      test  = every eval-eligible trip of the held-out drivers and of the held-out categories (whole groups are held
              out; an included but not eval-eligible trip of a held-out group is dropped, never trained on);
      val   = per remaining category with >= 2 trips, the eval-eligible trip whose length is closest to `val_fraction`
              of the category's samples (never the whole category);
      train = every other included trip.  Excluded trips get no split."""
    inc = [t for t in trips if t["included"]]
    held = lambda t: t["driver"] in test_drivers or t["category"] in test_categories
    split, dropped = {}, []
    for t in inc:
        if held(t):
            if t["eval_eligible"]:
                split[t["trip_id"]] = "test"
            else:
                dropped.append(t["trip_id"])
        else:
            split[t["trip_id"]] = "train"
    for cat in sorted({t["category"] for t in inc if not held(t)}):
        pool = [t for t in inc if t["category"] == cat and not held(t)]
        cand = [t for t in pool if t["eval_eligible"]]
        if len(pool) < 2 or not cand:
            continue
        target = val_fraction * sum(t["valid_samples"] for t in pool)
        pick = min(cand, key=lambda t: (abs(t["valid_samples"] - target), t["trip_id"]))
        split[pick["trip_id"]] = "val"
    rules = {"test_drivers": list(test_drivers), "test_categories": list(test_categories),
             "val_rule": (f"per remaining category with >= 2 trips: the eval-eligible trip whose length is closest to "
                          f"{val_fraction:.0%} of the category's samples"),
             "unit": "whole trips; a window never crosses a trip or a gap segment",
             "eval_eligible": "validation/test trips must have their phone clock verified by their own yaw rate",
             "held_out_group_trips_dropped_unverified": sorted(dropped)}
    return split, rules


def make_windows(table: pd.DataFrame, stride: int = 2, win: int = WIN_LEN):
    """Windows inside each (trip_id, seg_id) run of a table with vehicle-frame channels + speed_ms.
    Returns X [N, win, 13] float32 (raw units), y speed_ms [N] float32 (speed at the last sample), and a meta
    DataFrame (start/stop row positions in `table`, trip_id, seg_id, vib = vibration proxy in 0..1)."""
    xs, ys, metas = [], [], []
    for (trip, seg), idx in table.groupby(["trip_id", "seg_id"], sort=False).indices.items():
        if len(idx) < win:
            continue
        g = table.iloc[idx]
        f = compute_13_channel_features(*(g[c].to_numpy() for c in FEATURE_NAMES[:6]))
        view = sliding_window_view(f, win, axis=0)[::stride]              # (n, 13, win)
        starts = np.arange(0, len(f) - win + 1, stride)
        xs.append(np.ascontiguousarray(view.transpose(0, 2, 1), dtype=np.float32))
        ys.append(g["speed_ms"].to_numpy(np.float32)[starts + win - 1])
        vib = np.abs(f[:, 6] - G_NOMINAL)
        vib_w = sliding_window_view(vib, win)[::stride].mean(axis=1)
        metas.append(pd.DataFrame({"start": idx[starts], "stop": idx[starts] + win, "trip_id": trip, "seg_id": seg,
                                   "vib": np.clip(vib_w / 3.0, 0.0, 1.0).astype(np.float32)}))
    if not xs:
        return np.zeros((0, win, 13), np.float32), np.zeros(0, np.float32), pd.DataFrame(
            columns=["start", "stop", "trip_id", "seg_id", "vib"])
    return np.concatenate(xs), np.concatenate(ys), pd.concat(metas, ignore_index=True)
