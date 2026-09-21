"""Real-data audit of the synchronised IO-VNBD set -> the dict written to `01_dataset_summary.json`."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd

from . import sync

BANDS_KMH = [(0, 1, "stationary (<1)"), (1, 30, "1-30"), (30, 60, "30-60"), (60, 90, "60-90"), (90, 999, ">=90")]


def jsonable(obj):
    """Recursively turn numpy scalars/arrays and NaN/inf into plain JSON types (NaN -> None)."""
    if isinstance(obj, dict):
        return {str(k): jsonable(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [jsonable(v) for v in obj]
    if isinstance(obj, np.ndarray):
        return jsonable(obj.tolist())
    if isinstance(obj, (np.floating, float)):
        return float(obj) if np.isfinite(obj) else None
    if isinstance(obj, (np.integer,)):
        return int(obj)
    if isinstance(obj, (np.bool_,)):
        return bool(obj)
    return obj


def _r(x, n=3):
    return None if x is None or (isinstance(x, float) and not np.isfinite(x)) else round(float(x), n)


def _group_table(recs: list[dict], key: str) -> dict:
    out = {}
    for k in sorted({r[key] for r in recs}):
        rs = [r for r in recs if r[key] == k]
        inc = [r for r in rs if r["included"]]
        out[k] = {"trips": len(rs), "csv_files": 2 * len(rs), "rows_vbox": sum(r["rows_vbox"] for r in rs),
                  "hours": _r(sum(r["rows_vbox"] for r in rs) / 36000.0, 2),
                  "km": _r(sum(r["distance_km"] for r in rs), 1),
                  "included_trips": len(inc), "included_hours": _r(sum(r["valid_samples"] for r in inc) / 36000.0, 2),
                  "included_km": _r(sum(r["distance_km"] for r in inc), 1)}
    return out


def _speed_distribution(table: pd.DataFrame) -> dict:
    kmh = table["speed_ms"].to_numpy() * 3.6
    pct = {f"p{p}": _r(np.percentile(kmh, p), 1) for p in (1, 5, 25, 50, 75, 95, 99)}
    return {"mean_kmh": _r(kmh.mean(), 2), "max_kmh": _r(kmh.max(), 1), **pct,
            "time_share_by_band_kmh": {lab: _r(((kmh >= lo) & (kmh < hi)).mean(), 4) for lo, hi, lab in BANDS_KMH}}


def _sampling(recs: list[dict]) -> dict:
    fix = np.array([r["gps_fix_interval_s_median"] for r in recs if r["gps_fix_interval_s_median"] is not None])
    hist = np.sum([r["phone_dt_hist_5ms"] for r in recs], axis=0)
    return {
        "phone_dt_ms_median_over_trips": _r(np.median([r["phone_dt_ms_median"] for r in recs]), 1),
        "phone_dt_ms_std_excluding_1pct_tails_median_over_trips": _r(np.median([r["phone_dt_ms_std_1_99pct"] for r in recs]), 2),
        "phone_rows_share_with_dt_in_95_105_ms": _r(hist[19:21].sum() / hist.sum(), 4),
        "phone_gaps_over_0p35s": int(sum(r["sync"]["phone_gaps"] for r in recs)),
        "phone_gaps_over_1s": int(sum(r["phone_gaps_over_1s"] for r in recs)),
        "phone_largest_gap_s": _r(max(r["sync"]["phone_max_gap_s"] or 0 for r in recs), 1),
        "phone_timestamp_column_backwards_jumps": int(sum(r["phone_timestamp_col_backwards_jumps"] for r in recs)),
        "vbox_irregular_timestamps": int(sum(r["vbox_dt_glitches"] for r in recs)),
        "phone_gps_fix_interval_s": {"median_over_trips": _r(np.median(fix), 1), "min": _r(fix.min(), 1), "max": _r(fix.max(), 1),
                                     "trips_with_1s_fixes": int(np.sum(fix <= 1.5)),
                                     "trips_with_9s_or_slower_fixes": int(np.sum(fix >= 8.5))},
    }


def _sync_section(recs: list[dict]) -> dict:
    equal = [r for r in recs if r["rows_equal"]]
    strong = [r for r in recs if r["lag_source"] == "own"]
    row_lag_s = np.array([abs(r["row_pairing_yaw"]["lag"]) * sync.DT for r in strong])
    resid_s = np.array([abs(r["lag_used_samples"]) * sync.DT for r in strong])
    offs = np.array([abs(r["sync"]["start_offset_s"]) for r in recs if r["sync"].get("start_offset_s") is not None])
    gps_lag = [r["gps_speed_lag_s"] for r in recs if r["gps_speed_corr"] > 0.8]
    ratio = [r["gps_speed_over_vbox_ms"] for r in recs if r["gps_speed_over_vbox_ms"] is not None]
    return {
        "meaning": ("'Synchronised' means the authors trimmed S and V by hand so that row i of S is roughly row i of V. It is "
                    "not a timestamp guarantee: row-index pairing leaves the phone up to several seconds off, the phone drops "
                    "rows, and its 'TIME SINCE START' column jumps backwards in some files. The pipeline re-pairs by wall-clock "
                    "time (phone DATE column vs VBOX GPS time of day, whole-hour timezone removed) and then measures the "
                    "remaining clock offset from the yaw rate."),
        "row_counts": {"trips_with_equal_rows": len(equal), "trips_with_different_rows": len(recs) - len(equal),
                       "largest_row_difference": int(max(abs(r["rows_phone"] - r["rows_vbox"]) for r in recs))},
        "phone_log_start_minus_vbox_start_s": {"median_abs": _r(np.median(offs), 2), "max_abs": _r(offs.max(), 1)},
        "trips_with_own_verified_clock_offset": len(strong),
        "yaw_rate_lag_when_pairing_by_row_index_s": {"median_abs": _r(np.median(row_lag_s), 2), "max_abs": _r(row_lag_s.max(), 2)},
        "yaw_rate_lag_after_wall_clock_pairing_s": {"median_abs": _r(np.median(resid_s), 2), "max_abs": _r(resid_s.max(), 2),
                                                    "note": "constant along each trip (no drift found); differs per recording session"},
        "row_index_fallback_trips": [r["trip_id"] for r in recs if r["sync"]["mode"] == "row"],
        "timezone_offsets_hours_seen": sorted({r["sync"]["tz_hours"] for r in recs if r["sync"]["tz_hours"] is not None}),
        "lag_sources": {k: sum(1 for r in recs if r["lag_source"] == k) for k in ("own", "session", "unverified")},
        "phone_gps_speed_vs_vbox_speed": {
            "units_finding": "column 'GPS SPEED (Kmh)' holds metres per second (median GPS/VBOX ratio in m/s = %s)" % _r(np.median(ratio), 3),
            "best_lag_s_median": _r(np.median(gps_lag), 1), "best_lag_s_range": [_r(min(gps_lag), 1), _r(max(gps_lag), 1)],
            "reading": "GPS speed is held between fixes (median fix interval 9 s), so its lag is hold delay, not a clock offset",
            "trips_with_corr_ge_0p8": sum(1 for r in recs if r["gps_speed_corr"] >= 0.8)},
    }


def _axes_section(recs: list[dict]) -> dict:
    strong = [r for r in recs if r["lag_source"] == "own" and not r["stationary"]]
    cols = {c: _r(np.mean([abs(r["yaw_col_corr"][c]) for r in strong]), 3) for c in
            ("gyro_yaw_col", "gyro_pitch_col", "gyro_roll_col")}
    th = [r["mount"]["own"]["theta_deg"] for r in recs if r["mount"]["source"] == "own"]
    return {
        "mean_abs_corr_of_phone_gyro_column_with_vbox_yaw_rate": cols,
        "yaw_axis_is_column_labelled": "Pitch (positive = counter-clockwise, same sign as VBOX yaw rate)",
        "phone_gravity_mean_all_trips": {"min": _r(min(min(r["phone_gravity_mean"]) for r in recs), 2),
                                          "max": _r(max(max(r["phone_gravity_mean"]) for r in recs), 2),
                                          "reading": "gravity is (0, 0, +9.81) in every trip: the phone lies flat, z is up"},
        "mount_yaw_deg_own_estimates": {"trips": len(th), "min": _r(min(th), 1), "median": _r(np.median(th), 1), "max": _r(max(th), 1),
                                        "reading": "the forward axis is at a per-trip angle to the phone x axis, so a yaw alignment is required"},
        "mount_source_counts": {k: sum(1 for r in recs if r["mount"]["source"] == k) for k in ("own", "session", "unverified")},
    }


def summarise(recs: list[dict], table: pd.DataFrame, split: dict[str, str], split_rules: dict,
              manifest_path: Path | None = None) -> dict:
    manifest = None
    if manifest_path and Path(manifest_path).exists():
        manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    splits = {}
    for name in ("train", "val", "test"):
        ids = sorted(k for k, v in split.items() if v == name)
        sub = table[table.trip_id.isin(ids)]
        splits[name] = {"trips": ids, "n_trips": len(ids), "hours": _r(len(sub) / 36000.0, 2),
                        "km": _r(float(sub.speed_ms.sum() * sync.DT / 1000.0), 1),
                        "drivers": sorted({r["driver"] for r in recs if r["trip_id"] in ids}),
                        "categories": sorted({r["category"] for r in recs if r["trip_id"] in ids})}
    per_trip = {}
    for r in recs:
        per_trip[r["trip_id"]] = {
            "category": r["category"], "driver": r["driver"], "session": r["session"], "rows_phone": r["rows_phone"],
            "rows_vbox": r["rows_vbox"], "distance_km": r["distance_km"], "mean_kmh": r["mean_kmh"], "max_kmh": r["max_kmh"],
            "included": r["included"], "eval_eligible": r["eval_eligible"], "split": split.get(r["trip_id"]),
            "wall_clock_mode": r["sync"]["mode"], "lag_samples": r["lag_used_samples"], "lag_source": r["lag_source"],
            "yaw_corr_at_lag": _r(r["yaw_lag"]["corr"], 2), "row_pairing_yaw_lag_s": _r(r["row_pairing_yaw"]["lag"] * sync.DT, 1),
            "gps_speed_corr": _r(r["gps_speed_corr"], 2), "mount": r["mount"], "valid_samples": r["valid_samples"]}
    return {
        "dataset": "IO-VNBD synchronised + categorised (real data; Git-LFS objects fetched and SHA-256 verified)",
        "integrity": {"files_in_manifest": len(manifest["files"]) if manifest else None,
                      "all_verified": bool(manifest and all(f["status"] in ("downloaded", "skipped") for f in manifest["files"])),
                      "bytes": int(sum(f["size"] for f in manifest["files"])) if manifest else None},
        "files": {"csv_files": 2 * len(recs), "trips": len(recs), "per_driver": _group_table(recs, "driver"),
                  "per_category": _group_table(recs, "category")},
        "totals_all_trips": {"rows_phone": sum(r["rows_phone"] for r in recs), "rows_vbox": sum(r["rows_vbox"] for r in recs),
                             "hours": _r(sum(r["rows_vbox"] for r in recs) / 36000.0, 2),
                             "km_from_vbox_speed": _r(sum(r["distance_km"] for r in recs), 1)},
        "totals_used": {"trips": int(table.trip_id.nunique()), "rows": int(len(table)), "hours": _r(len(table) / 36000.0, 2),
                        "km_from_vbox_speed": _r(float(table.speed_ms.sum() * sync.DT / 1000.0), 1),
                        "gap_free_segments": int(table.groupby(["trip_id", "seg_id"]).ngroups)},
        "speed_distribution_used": _speed_distribution(table),
        "sampling": _sampling(recs),
        "missing_values": {
            "raw_nan_phone_imu_cells": int(sum(r["nan_phone_imu"] for r in recs)),
            "raw_nan_vbox_key_cells": int(sum(r["nan_vbox_key"] for r in recs)),
            "vbox_samples_without_phone_data_after_alignment_pct": _r(100 * (1 - np.average(
                [r["sync"]["overlap"] for r in recs], weights=[r["rows_vbox"] for r in recs])), 2),
            "nan_in_used_table": int(table[["ax", "ay", "az", "gx", "gy", "gz", "speed_ms"]].isna().sum().sum())},
        "synchronisation": _sync_section(recs),
        "axes": _axes_section(recs),
        "quality_gate": {
            "rules": ["at least 30 s of valid synchronised samples (VBOX speed jumps > 30 m/s^2 and missing values removed)",
                      "phone clock offset verified from the yaw rate: own (z >= 3) or the median of the same recording session",
                      "same-drive check: excluded when the yaw rate is unverified AND the phone GPS speed does not follow the VBOX speed (corr < 0.8)",
                      "phone mount yaw must be estimable (own or pooled over the session, z >= 3)",
                      "stationary trips (max speed < 1 m/s) are kept for the zero-speed windows",
                      "validation/test additionally need the trip's OWN yaw rate to verify its clock (eval_eligible)"],
            "excluded_trips": [{"trip_id": r["trip_id"], "category": r["category"], "hours": _r(r["rows_vbox"] / 36000, 2),
                                "reasons": r["exclusion_reasons"]} for r in recs if not r["included"]]},
        "splits": {"rules": split_rules, **splits},
        "trips": per_trip,
    }
