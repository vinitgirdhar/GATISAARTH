"""Attach held-out phone-model predictions to the vehicle-proxy replay.

This is an offline hybrid ablation, not a phone-only field test: phone inputs
use the dataset's offline clock/mount alignment. VBOX truth is never passed to
the model. Time-to-label agreement is checked before the log is emitted.
"""
from pathlib import Path
import json
import sys

import numpy as np
import pandas as pd
import torch

from release_models import ROOT, load_models


def main():
    trip = sys.argv[1] if len(sys.argv) > 1 else 'M'
    split = json.loads((ROOT / 'ml/data/processed/splits/dataset_splits.json').read_text())
    assert trip in split['test_tracks'], 'Only held-out trips may be used'
    table = pd.read_parquet(ROOT / 'ml/data/processed/cleaned/iovnbd_cleaned_10hz.parquet')
    # Build chronological windows directly from this held-out trip so row indices
    # cannot depend on the notebook's concatenation order.
    sys.path.insert(0, str(ROOT / 'ml/src'))
    from dataset.windows import make_windows
    table = table[table.trip_id == trip].reset_index(drop=True)
    x, labels, meta = make_windows(table, stride=1)
    scaler = json.loads((ROOT / 'ml/data/scalers/imu_feature_scaler.json').read_text())
    x = ((x - np.array(scaler['mean'])) / np.array(scaler['scale'])).astype(np.float32)
    _, model, _ = next(load_models())
    torch.set_num_threads(2)
    predictions = []
    with torch.no_grad():
        for start in range(0, len(x), 512):
            speed, logvar = model(torch.from_numpy(x[start:start+512]))
            predictions.extend(np.concatenate([speed.numpy(), logvar.numpy()], axis=1))
    times = table.t.to_numpy()[meta.stop.to_numpy() - 1]
    outputs = {}
    for i, (t, (speed, logvar)) in enumerate(zip(times, predictions)):
        us = 5000000 + round(float(t) * 1e6)
        outputs[us] = {'t': 'a', 'u': us, 'spd': float(speed),
                       'sig': float(np.exp(np.clip(logvar, -5, 5) / 2)),
                       'lms': 1, 'fz': float(np.abs(x[i]).max()), 'win': 20}
    import re
    log_trip = re.sub(r'0+(\d+)$', r'\1', trip)
    paths = list((ROOT / 'ml/data/processed/drive_logs_vehicle').glob(f'*__{log_trip}.jsonl'))
    assert len(paths) == 1
    source = [json.loads(line) for line in paths[0].read_text().splitlines()]
    truth = {r['u']: r['spd'] for r in source if r['t'] == 'r'}
    differences = [abs(truth[u] - float(y)) for u, y in zip(outputs, labels) if u in truth]
    assert len(differences) > 0.99 * len(labels)
    assert max(differences) < 0.02, max(differences)
    target = ROOT / 'ml/data/processed/drive_logs_ai' / f'{trip}.jsonl'
    target.parent.mkdir(exist_ok=True)
    with target.open('w') as f:
        for row in source:
            f.write(json.dumps(row, separators=(',', ':')) + '\n')
            if row['t'] == 'i' and row['u'] in outputs:
                f.write(json.dumps(outputs[row['u']], separators=(',', ':')) + '\n')
    print(f'{len(outputs)} held-out predictions -> {target}; max label/time error {max(differences):.6f} m/s')


if __name__ == '__main__':
    main()
