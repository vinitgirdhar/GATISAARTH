"""Export the existing notebook's trained architectures without retraining.

Run with the training Python: python ml/src/export/release_models.py
Then run onnx_to_tflite.py with the isolated TensorFlow environment.
Only class definitions are extracted; notebook training cells are not executed.
"""
from pathlib import Path
import ast
import json

import torch
from torch import nn
from torch.nn import functional as F

ROOT = Path(__file__).resolve().parents[3]


def load_models():
    notebook = json.loads((ROOT / 'ml/notebooks/gati_ai_dead_reckoning_master_pipeline.ipynb').read_text(encoding='utf-8'))
    names = {'SpeedEstimatorNet', 'VibrationClassifierNet', 'MotionQualityNet'}
    namespace = {'torch': torch, 'nn': nn, 'F': F}
    for cell in notebook['cells']:
        if cell['cell_type'] != 'code':
            continue
        for node in ast.parse(''.join(cell['source'])).body:
            if isinstance(node, ast.ClassDef) and node.name in names:
                exec(compile(ast.Module(body=[node], type_ignores=[]), '<notebook architecture>', 'exec'), namespace)
    specs = [
        ('speed_estimator', 'SpeedEstimatorNet', 'speed_model_best.pth', ['speed_ms', 'log_variance']),
        ('vibration_classifier', 'VibrationClassifierNet', 'vibration_model_best.pth', ['vibration_logits', 'vibration_score']),
        ('motion_quality', 'MotionQualityNet', 'motion_quality_best.pth', ['motion_quality_score']),
    ]
    for directory, name, checkpoint, outputs in specs:
        model = namespace[name]()
        model.load_state_dict(torch.load(ROOT / 'ml/models' / directory / 'checkpoints' / checkpoint, map_location='cpu', weights_only=True))
        yield directory, model.eval(), outputs


def main():
    torch.set_num_threads(2)
    for directory, model, outputs in load_models():
        target = ROOT / 'ml/models' / directory / 'exported' / f'{directory}.onnx'
        torch.onnx.export(model, torch.zeros(1, 20, 13), str(target), dynamo=False,
                          input_names=['imu_window_13ch'], output_names=outputs,
                          dynamic_axes={'imu_window_13ch': {0: 'batch_size'}}, opset_version=14)
        print(f'Exported {target} ({target.stat().st_size} bytes)')


if __name__ == '__main__':
    main()
