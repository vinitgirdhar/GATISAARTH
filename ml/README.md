# ml/

The speed model's data and training.

| Path | What it is |
|---|---|
| `src/dataset/` | IO-VNBD download (`fetch_iovnbd.py`), parsing (`iovnbd.py`), clock and mount sync (`sync.py`), the 13-channel features and leak-free trip-level splits and windows (`windows.py`), the build that writes `data/processed/` (`build.py`), and the converter to app drive logs (`iovnbd_to_drive_log.py`). |
| `src/training/train_speed_v4.py` | The shipped speed model: a dilated causal temporal-convolution network trained from scratch, exported straight to TFLite (built-in ops only) with a parity check. |
| `src/evaluation/iovnbd_eval.py` | Position drift on held-out IO-VNBD trips. |
| `src/export/ai_replay_log.py` | Attaches a model's held-out predictions to a drive log for `frontend/test/nav/real_ai_ablation_test.dart`. |
| `models/speed_estimator_v4/` | The trained model, its TFLite export and `report.json` (held-out metrics). |
| `tests/` | pytest for the data pipeline. |

## Train and deploy

```bash
# TensorFlow lives in its own environment
ml/.venv-export/Scripts/python.exe ml/src/training/train_speed_v4.py --out ml/models/speed_estimator_v4
cp ml/models/speed_estimator_v4/speed_estimator.tflite frontend/assets/models/
```

Then update `frontend/assets/models/model_metadata.json` from `report.json`.

## Contract with the app

Input `[1, 20, 13]`: 20 samples at 10 Hz of `ax ay az gx gy gz |a| |g| dax day daz pitch roll` in the levelled vehicle frame (accelerometer includes gravity), standardised with the scaler in `model_metadata.json`. Output `[1, 2]`: speed (m/s, >= 0) and its log-variance.

## Honest numbers (held-out trips M, Vtb01-03, Vtb05, Y1)

v4: speed MAE 3.33 m/s, RMSE 4.61 m/s, R² 0.58; 61 % of errors inside 1-sigma, 87.5 % inside 2-sigma. The app only lets it into the filter after it agrees with GNSS Doppler speed on the same drive (RMS <= 1 m/s); on these trips it does not, so it stays advisory.
