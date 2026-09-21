#!/usr/bin/env python3
"""Identify the vehicle-proxy IMU error densities from a generic external-IMU CSV that carries
GNSS speed/course (used as the reference) - NOT from any position-outage score.

For windows of T seconds while moving (> 3 m/s) it compares the integral of the IMU with the
reference change: forward accel -> speed change, yaw rate -> heading change. The rms of the
difference over sqrt(T) is the random-walk density the filter should be told
(accelNoise [m/s^2/sqrt(Hz)], gyroNoise [rad/s/sqrt(Hz)]). Values that grow with T mean the
error is not white (scale error, bias): the preset then uses the larger, longer-window value.
"""
import sys
import numpy as np
import pandas as pd

df = pd.read_csv(sys.argv[1], comment="#")
t = df.t.to_numpy(); ax = df.ax.to_numpy(); gz = df.gz.to_numpy()
g = df.dropna(subset=["gnss_speed"])
speed = np.interp(t, g.t, g.gnss_speed)
course = np.unwrap(np.radians(g.gnss_course.to_numpy()))
heading = np.interp(t, g.t, course)
dt = float(np.median(np.diff(t)))
print(f"{sys.argv[1]}: {len(t)} rows, {t[-1]/60:.0f} min, dt {dt:.3f}s")
for T in (5, 10, 30):
    n = int(round(T / dt)); dv = []; dh = []
    for i in range(0, len(t) - n, n):
        if speed[i:i + n + 1].min() < 3.0: continue
        dv.append(np.sum(ax[i:i + n]) * dt - (speed[i + n] - speed[i]))
        dh.append(-np.sum(gz[i:i + n]) * dt - (heading[i + n] - heading[i]))
    dv, dh = np.array(dv), np.array(dh)
    print(f"T={T:2d}s windows={len(dv):4d}  speed-change error rms {np.sqrt(np.mean(dv**2)):.2f} m/s -> accelNoise {np.sqrt(np.mean(dv**2))/np.sqrt(T):.3f} m/s2/sqrtHz"
          f" | heading-change error rms {np.degrees(np.sqrt(np.mean(dh**2))):.2f} deg -> gyroNoise {np.sqrt(np.mean(dh**2))/np.sqrt(T):.4f} rad/s/sqrtHz")
