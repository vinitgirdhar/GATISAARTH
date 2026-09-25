"""Speed model v4: a dilated causal temporal-convolution network trained from scratch on the IO-VNBD windows.

Written independently of every earlier notebook. It keeps only the app's input/output contract, which is ours
(ml/src/dataset/windows.py and frontend ImuFeatureWindow):

    input  [1, 20, 13]  standardised 10 Hz features (the scaler in frontend/assets/models/model_metadata.json)
    output [1, 2]       (speed m/s >= 0, log-variance of that speed)

Architecture: three residual causal Conv1D blocks with dilations 1, 2, 4 (receptive field covers the whole 2 s
window), then the mean over time and the newest time step side by side, a small dense layer and two heads. Loss:
beta-NLL (Seitzer et al., 2022, beta = 0.5), which fits the variance without letting it swallow the mean.
Only TFLite built-in ops are used, so the phone needs no Flex delegate.

Usage (the TensorFlow environment is ml/.venv-export):

    ml/.venv-export/Scripts/python.exe -m ml.src.training.train_speed_v4 --out ml/models/speed_estimator_v4
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import time
from pathlib import Path

import numpy as np
import tensorflow as tf

WINDOWS = Path("ml/data/processed/windows")
WIN, FEATS = 20, 13
# Squashed (not clipped) so the variance head never loses its gradient at a bound.
LOGVAR_MIN, LOGVAR_MAX = -4.0, 5.0


def load(split: str):
    d = np.load(WINDOWS / f"{split}_windows.npz")
    return d["X"].astype(np.float32), d["y_speed"].astype(np.float32), d["trip_id"]


def softplus(x):
    # max(x, 0) + log(1 + exp(-|x|)): the stable form, built from TFLite built-in ops only.
    return tf.maximum(x, 0.0) + tf.math.log(1.0 + tf.exp(-tf.abs(x)))


def build(width: int = 48, seed: int = 7) -> tf.keras.Model:
    tf.keras.utils.set_random_seed(seed)
    x_in = tf.keras.Input((WIN, FEATS), name="features")
    h = tf.keras.layers.Conv1D(width, 1, name="project")(x_in)
    for dilation in (1, 2, 4):
        r = tf.keras.layers.Conv1D(width, 3, padding="causal", dilation_rate=dilation, activation="relu",
                                   name=f"tcn{dilation}a")(h)
        r = tf.keras.layers.Conv1D(width, 3, padding="causal", dilation_rate=dilation, name=f"tcn{dilation}b")(r)
        h = tf.keras.layers.ReLU()(tf.keras.layers.Add()([h, r]))
    mean = tf.keras.layers.GlobalAveragePooling1D()(h)
    last = tf.keras.layers.Lambda(lambda t: t[:, -1, :], name="newest")(h)
    z = tf.keras.layers.Dense(64, activation="relu")(tf.keras.layers.Concatenate()([mean, last]))
    raw = tf.keras.layers.Dense(2, name="heads")(z)
    speed = tf.keras.layers.Lambda(lambda t: softplus(t[:, :1]), name="speed")(raw)
    logvar = tf.keras.layers.Lambda(
        lambda t: LOGVAR_MIN + (LOGVAR_MAX - LOGVAR_MIN) * tf.sigmoid(t[:, 1:]), name="logvar")(raw)
    return tf.keras.Model(x_in, tf.keras.layers.Concatenate(name="speed_logvar")([speed, logvar]))


def beta_nll(y_true, y_pred, beta: float = 0.5):
    mu, logvar = y_pred[:, 0], y_pred[:, 1]
    var = tf.exp(logvar)
    nll = 0.5 * (logvar + tf.square(y_true[:, 0] - mu) / var)
    return tf.reduce_mean(nll * tf.stop_gradient(tf.pow(var, beta)))


def speed_mae(y_true, y_pred):
    return tf.reduce_mean(tf.abs(y_true[:, 0] - y_pred[:, 0]))


def evaluate(model, X, y) -> dict:
    p = model.predict(X, batch_size=4096, verbose=0)
    err = p[:, 0] - y
    sigma = np.sqrt(np.exp(p[:, 1]))
    return {
        "windows": int(len(y)),
        "speed_mae_m_s": round(float(np.mean(np.abs(err))), 3),
        "speed_rmse_m_s": round(float(np.sqrt(np.mean(err ** 2))), 3),
        "speed_r2": round(float(1 - np.sum(err ** 2) / np.sum((y - y.mean()) ** 2)), 4),
        "bias_m_s": round(float(np.mean(err)), 3),
        # Share of windows whose truth falls inside k sigma; a calibrated Gaussian gives 68.3 / 95.4 / 99.7 %.
        "coverage_1sigma_pct": round(100 * float(np.mean(np.abs(err) <= sigma)), 1),
        "coverage_2sigma_pct": round(100 * float(np.mean(np.abs(err) <= 2 * sigma)), 1),
        "coverage_3sigma_pct": round(100 * float(np.mean(np.abs(err) <= 3 * sigma)), 1),
    }


def export_tflite(model, path: Path) -> bytes:
    fn = tf.function(lambda x: model(x, training=False),
                     input_signature=[tf.TensorSpec([1, WIN, FEATS], tf.float32, name="features")])
    # No trackable object: the weights are frozen into constants (a phone has no variables to read).
    conv = tf.lite.TFLiteConverter.from_concrete_functions([fn.get_concrete_function()])
    conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    blob = conv.convert()
    path.write_bytes(blob)
    return blob


def parity(model, blob: bytes, X: np.ndarray) -> float:
    it = tf.lite.Interpreter(model_content=blob)
    it.allocate_tensors()
    i, o = it.get_input_details()[0]["index"], it.get_output_details()[0]["index"]
    worst = 0.0
    ref = model.predict(X, verbose=0)
    for k in range(len(X)):
        it.set_tensor(i, X[k:k + 1])
        it.invoke()
        worst = max(worst, float(np.max(np.abs(it.get_tensor(o)[0] - ref[k]))))
    return worst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="ml/models/speed_estimator_v4")
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--batch", type=int, default=512)
    ap.add_argument("--width", type=int, default=48)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    Xtr, ytr, _ = load("train")
    Xva, yva, _ = load("val")
    Xte, yte, trips = load("test")
    model = build(args.width)
    steps = math.ceil(len(ytr) / args.batch) * args.epochs
    model.compile(optimizer=tf.keras.optimizers.Adam(tf.keras.optimizers.schedules.CosineDecay(2e-3, steps)),
                  loss=beta_nll, metrics=[speed_mae])
    t0 = time.time()
    hist = model.fit(Xtr, ytr[:, None], validation_data=(Xva, yva[:, None]), epochs=args.epochs,
                     batch_size=args.batch, verbose=2,
                     callbacks=[tf.keras.callbacks.EarlyStopping("val_speed_mae", patience=6,
                                                                 restore_best_weights=True, mode="min")])
    train_s = time.time() - t0
    model.save(out / "speed_v4.keras")

    blob = export_tflite(model, out / "speed_estimator.tflite")
    worst = parity(model, blob, Xte[:: max(1, len(Xte) // 2000)])
    report = {
        "model_version": "v4.0.0",
        "architecture": "residual dilated causal TCN (1/2/4) + mean/newest pooling, beta-NLL; trained from scratch",
        "script": "ml/src/training/train_speed_v4.py",
        "params": int(model.count_params()),
        "epochs_run": len(hist.history["loss"]),
        "train_seconds": round(train_s),
        "train_windows": int(len(ytr)),
        "val": evaluate(model, Xva, yva),
        "held_out_test": evaluate(model, Xte, yte),
        "held_out_test_trips": sorted({str(t) for t in trips}),
        "tflite_bytes": len(blob),
        "tflite_sha256": hashlib.sha256(blob).hexdigest(),
        "tflite_parity_max_abs": worst,
        "quantization": "FP32",
    }
    (out / "report.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
