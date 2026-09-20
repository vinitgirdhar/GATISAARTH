"""ONNX -> TensorFlow Lite conversion for the on-device speed estimator.

The network is rebuilt in plain TensorFlow ops from the ONNX weights rather than
converted op-by-op: onnx2tf mis-handles both the leading channels-first
Transpose and the bidirectional GRU of this graph. Architecture (read off the
ONNX): Conv1d 13->32, residual block 32->64, max-pool 2, two bidirectional GRU
layers (hidden 32, linear_before_reset), mean over time, two dense layers and a
softplus speed head plus a log-variance head.

The app feeds one [1, 20, 13] window and reads one [1, 2] tensor
(speed m/s, log-variance).

The output is float32 on purpose: the network is ~65k parameters (~0.25 MB),
and full-integer GRUs lose accuracy that no calibration set in this repo could
measure. Only built-in TFLite ops are emitted (no Flex/select-TF ops), because
the Flutter runtime does not ship them.

Needs onnx, tensorflow and onnxruntime:

    python onnx_to_tflite.py speed_estimator.onnx speed_estimator.tflite
"""

import sys
from pathlib import Path

WINDOW, FEATURES, HIDDEN = 20, 13, 32


def _initializers(onnx_path):
    """params(node, *slots) -> the initializer arrays wired into those inputs."""
    import onnx
    from onnx import numpy_helper

    graph = onnx.load(str(onnx_path)).graph
    values = {i.name: numpy_helper.to_array(i) for i in graph.initializer}
    nodes = {n.name: n for n in graph.node}
    return lambda node, *slots: [values[nodes[node].input[s]] for s in slots]


def _network(params):
    import tensorflow as tf

    def leaky(x):
        return tf.nn.leaky_relu(x, alpha=0.1)

    def conv(x, node):  # ONNX weight (out, in, k) -> TF (k, in, out); pads k//2
        w, b = params(node, 1, 2)
        return tf.nn.conv1d(x, w.transpose(2, 1, 0), 1, "SAME") + b

    def dense(x, node):  # ONNX Gemm with transB: y = x @ w.T + b
        w, b = params(node, 1, 2)
        return tf.matmul(x, w.T) + b

    def gru(x, node):
        # ONNX gate order is (update z, reset r, new n); one weight set per
        # direction; the backward pass runs over reversed time, outputs stay in
        # time order. Initial state is zero.
        w, r, b = params(node, 1, 2, 3)  # [2, 3H, in], [2, 3H, H], [2, 6H]
        steps, h3 = x.shape[1], 3 * HIDDEN
        outputs = []
        for d in range(2):
            projected = tf.tensordot(x, w[d].T, 1) + b[d, :h3]  # [1, T, 3H]
            h = tf.zeros([1, HIDDEN])
            seq = [None] * steps
            for t in range(steps) if d == 0 else reversed(range(steps)):
                xz, xr, xn = tf.split(projected[:, t], 3, axis=-1)
                hz, hr, hn = tf.split(tf.matmul(h, r[d].T) + b[d, h3:], 3, axis=-1)
                z = tf.sigmoid(xz + hz)
                n = tf.tanh(xn + tf.sigmoid(xr + hr) * hn)
                h = (1.0 - z) * n + z * h
                seq[t] = h
            outputs.append(tf.stack(seq, axis=1))
        return tf.concat(outputs, axis=-1)

    def net(x):  # [1, 20, 13]
        x = leaky(conv(x, "/conv1/conv1.0/Conv"))
        skip = conv(x, "/res_skip/Conv")
        y = leaky(conv(x, "/res_conv1/Conv"))
        x = leaky(conv(y, "/res_conv2/Conv") + skip)
        x = tf.nn.max_pool1d(x, 2, 2, "VALID")  # [1, 10, 64]
        x = gru(gru(x, "/gru/GRU"), "/gru/GRU_1")
        x = tf.reduce_mean(x, axis=1)
        x = leaky(dense(x, "/fc_shared/fc_shared.0/Gemm"))
        x = leaky(dense(x, "/fc_shared/fc_shared.3/Gemm"))
        raw = dense(x, "/speed_head/speed_head.0/Gemm")
        # softplus spelled out: tf.math.softplus has no built-in TFLite op.
        speed = tf.maximum(raw, 0.0) + tf.math.log(1.0 + tf.exp(-tf.abs(raw)))
        return tf.concat([speed, dense(x, "/uncert_head/Gemm")], axis=1)

    return net


def convertToTFLite(onnx_path, output_path):
    import tensorflow as tf

    net = tf.function(
        _network(_initializers(onnx_path)),
        input_signature=[tf.TensorSpec([1, WINDOW, FEATURES], tf.float32)],
    )
    converter = tf.lite.TFLiteConverter.from_concrete_functions(
        [net.get_concrete_function()])
    Path(output_path).write_bytes(converter.convert())


def maxAbsDifference(onnx_path, tflite_path, samples: int = 256, seed: int = 0):
    """Worst |ONNX - TFLite| over random and smoothly-varying windows.

    Both are float32 graphs of the same network, so this should sit near 1e-5;
    anything near 1e-2 means an op was rebuilt wrongly.
    """
    import numpy as np
    import onnxruntime as ort
    import tensorflow as tf

    rng = np.random.default_rng(seed)
    noise = rng.normal(size=(samples, WINDOW, FEATURES))
    smooth = np.cumsum(rng.normal(size=(samples, WINDOW, FEATURES)), axis=1) * 0.3
    windows = np.concatenate([noise, smooth]).astype(np.float32)

    session = ort.InferenceSession(str(onnx_path))
    speed, log_var = session.run(None, {session.get_inputs()[0].name: windows})
    expected = np.concatenate([speed, log_var], axis=1)

    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()
    src = interpreter.get_input_details()[0]["index"]
    dst = interpreter.get_output_details()[0]["index"]
    actual = np.empty_like(expected)
    for i, window in enumerate(windows):
        interpreter.set_tensor(src, window[None])
        interpreter.invoke()
        actual[i] = interpreter.get_tensor(dst)[0]
    return float(np.abs(actual - expected).max())


if __name__ == "__main__":
    source, target = sys.argv[1:3]
    convertToTFLite(source, target)
    print(f"max |onnx - tflite| = {maxAbsDifference(source, target):.2e}")
