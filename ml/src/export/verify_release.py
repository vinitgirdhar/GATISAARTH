"""Verify deployed TFLite against ONNX on held-out real IO-VNBD windows.

Use the TensorFlow export environment. Fails closed on parity, shape or finite
output errors; writes machine-readable evidence and device-test fixtures.
"""
from pathlib import Path
import hashlib
import json
import time

import numpy as np
import onnxruntime as ort
import tensorflow as tf

ROOT = Path(__file__).resolve().parents[3]


def main():
    directory = ROOT / 'ml/models/speed_estimator/exported'
    data = np.load(ROOT / 'ml/data/processed/windows/test_windows.npz', allow_pickle=False)
    x = data['X'][np.linspace(0, len(data['X']) - 1, 512, dtype=int)].astype(np.float32)
    session = ort.InferenceSession(str(directory / 'speed_estimator.onnx'), providers=['CPUExecutionProvider'])
    expected = np.concatenate(session.run(None, {session.get_inputs()[0].name: x}), axis=1)
    lite = tf.lite.Interpreter(model_path=str(directory / 'speed_estimator.tflite'), num_threads=2)
    lite.allocate_tensors()
    src, dst = lite.get_input_details()[0], lite.get_output_details()[0]
    assert list(src['shape']) == [1, 20, 13]
    assert list(dst['shape']) == [1, 2]
    actual, latencies = [], []
    for window in x:
        start = time.perf_counter()
        lite.set_tensor(src['index'], window[None])
        lite.invoke()
        actual.append(lite.get_tensor(dst['index'])[0])
        latencies.append((time.perf_counter() - start) * 1000)
    actual = np.asarray(actual)
    difference = float(np.max(np.abs(actual - expected)))
    assert np.isfinite(actual).all() and difference < 0.001, difference
    report = {'windows': len(x), 'source': 'held-out IO-VNBD test windows',
              'onnx_tflite_max_absolute_difference': difference,
              'cpu_latency_median_ms': float(np.median(latencies)),
              'cpu_latency_p95_ms': float(np.percentile(latencies, 95)),
              'sha256': hashlib.sha256((directory / 'speed_estimator.tflite').read_bytes()).hexdigest(),
              'passed': True}
    (ROOT / 'docs/evidence/codex_model_parity.json').write_text(json.dumps(report, indent=2))
    fixtures = [{'input': w.tolist(), 'output': y.tolist()} for w, y in zip(x[:3], actual[:3])]
    (ROOT / 'frontend/assets/models/parity_fixtures.json').write_text(json.dumps(fixtures))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
