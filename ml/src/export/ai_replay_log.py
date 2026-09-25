"""Attach a speed model's held-out predictions to an IO-VNBD vehicle-proxy drive log, for the Dart AI ablation.

Offline hybrid ablation, not a phone field test: VBOX truth is never passed to the model, and the time-to-label
agreement is checked before the log is written. Works with any TFLite speed model that honours the app contract
([1, 20, 13] standardised features -> [speed, log-variance]).

Two steps, because the TensorFlow environment (ml/.venv-export) has no pandas and the data environment no TF:

    python ml/src/export/ai_replay_log.py windows M                       # -> scratch/M_windows.npz
    ml/.venv-export/Scripts/python.exe ml/src/export/ai_replay_log.py predict M frontend/assets/models/speed_estimator.tflite
    python ml/src/export/ai_replay_log.py log M                           # -> drive_logs_ai/M.jsonl

then in frontend/:  AI_DRIVE_LOG=../ml/data/processed/drive_logs_ai/M.jsonl flutter test test/nav/real_ai_ablation_test.dart
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
SCRATCH = ROOT / "ml/data/processed/ai_replay_scratch"


def windows(trip: str) -> None:
    import pandas as pd

    split = json.loads((ROOT / "ml/data/processed/splits/dataset_splits.json").read_text())
    assert trip in split["test_tracks"], "Only held-out trips may be used"
    sys.path.insert(0, str(ROOT / "ml/src"))
    from dataset.windows import make_windows

    table = pd.read_parquet(ROOT / "ml/data/processed/cleaned/iovnbd_cleaned_10hz.parquet")
    table = table[table.trip_id == trip].reset_index(drop=True)
    x, labels, meta = make_windows(table, stride=1)
    scaler = json.loads((ROOT / "ml/data/scalers/imu_feature_scaler.json").read_text())
    x = ((x - np.array(scaler["mean"])) / np.array(scaler["scale"])).astype(np.float32)
    times = table.t.to_numpy()[meta.stop.to_numpy() - 1]
    SCRATCH.mkdir(parents=True, exist_ok=True)
    np.savez(SCRATCH / f"{trip}_windows.npz", x=x, labels=np.asarray(labels, np.float32), times=times)
    print(f"{len(x)} windows -> {SCRATCH / f'{trip}_windows.npz'}")


def predict(trip: str, model_path: str) -> None:
    import tensorflow as tf

    d = np.load(SCRATCH / f"{trip}_windows.npz")
    if model_path.endswith(".keras"):
        # Batched Keras inference (the exported TFLite matches it to ~1e-5).
        sys.path.insert(0, str(ROOT / "ml/src/training"))
        import train_speed_v4

        model = train_speed_v4.build(int(sys.argv[4]) if len(sys.argv) > 4 else 48)
        model.load_weights(model_path)
        np.save(SCRATCH / f"{trip}_pred.npy", model.predict(d["x"], batch_size=4096, verbose=0))
        print(f"{len(d['x'])} predictions from {model_path}")
        return
    it = tf.lite.Interpreter(model_path=model_path)
    it.allocate_tensors()
    i, o = it.get_input_details()[0]["index"], it.get_output_details()[0]["index"]
    out = np.zeros((len(d["x"]), 2), np.float32)
    for k in range(len(out)):
        it.set_tensor(i, d["x"][k:k + 1])
        it.invoke()
        out[k] = it.get_tensor(o)[0]
    np.save(SCRATCH / f"{trip}_pred.npy", out)
    print(f"{len(out)} predictions from {model_path}")


def log(trip: str, tag: str = "") -> None:
    npz = np.load(SCRATCH / f"{trip}_windows.npz")
    d = {k: npz[k] for k in npz.files}  # an NpzFile decompresses on every access
    pred = np.load(SCRATCH / f"{trip}_pred.npy")
    zmax = np.abs(d["x"]).max(axis=(1, 2))
    outputs = {}
    for k, (t, (speed, logvar)) in enumerate(zip(d["times"], pred)):
        us = 5000000 + round(float(t) * 1e6)
        outputs[us] = {"t": "a", "u": us, "spd": float(speed), "sig": float(np.exp(np.clip(logvar, -5, 5) / 2)),
                       "lms": 1, "fz": float(zmax[k]), "win": 20}
    log_trip = re.sub(r"0+(\d+)$", r"\1", trip)
    paths = list((ROOT / "ml/data/processed/drive_logs_vehicle").glob(f"*__{log_trip}.jsonl"))
    assert len(paths) == 1, paths
    source = [json.loads(line) for line in paths[0].read_text().splitlines()]
    truth = {r["u"]: r["spd"] for r in source if r["t"] == "r"}
    diffs = [abs(truth[u] - float(y)) for u, y in zip(outputs, d["labels"]) if u in truth]
    assert len(diffs) > 0.99 * len(d["labels"]) and max(diffs) < 0.02, "prediction times do not match the log"
    target = ROOT / "ml/data/processed/drive_logs_ai" / f"{trip}{tag}.jsonl"
    target.parent.mkdir(exist_ok=True)
    with target.open("w") as f:
        for row in source:
            f.write(json.dumps(row, separators=(",", ":")) + "\n")
            if row["t"] == "i" and row["u"] in outputs:
                f.write(json.dumps(outputs[row["u"]], separators=(",", ":")) + "\n")
    print(f"{len(outputs)} held-out predictions -> {target}")


if __name__ == "__main__":
    step, trip = sys.argv[1], sys.argv[2]
    {"windows": lambda: windows(trip), "predict": lambda: predict(trip, sys.argv[3]), "log": lambda: log(trip, sys.argv[3] if len(sys.argv) > 3 else "")}[step]()
