"""Teaser score (10 s) for GatiSaarth, same palette as the launch film.

Minimal electronic, 100 BPM (beat 0.6 s, bar 2.4 s), D major / B minor.
Everything is synthesized here (no samples), written to the picture grid of
brag-plan.md so every major moment lands on a downbeat.

usage: python score.py OUT_DIR
writes music.wav (score only, for audio-reactive data) and mix.wav
(score + sound design, what the film plays). 48 kHz, 16-bit stereo.
"""
import os
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 48000
DUR = 10.0
N = int(SR * DUR)
BEAT = 0.6
BAR = 2.4
rng = np.random.default_rng(20260927)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def t_axis(n):
    return np.arange(n) / SR


def buf():
    return np.zeros((2, N))


def place(dst, src, t0, gain=1.0, pan=0.0):
    """Adds mono or stereo src into dst at t0 seconds (equal-power pan)."""
    i0 = int(round(t0 * SR))
    if src.ndim == 1:
        a = (pan + 1) * np.pi / 4
        src = np.vstack([src * np.cos(a), src * np.sin(a)]) * np.sqrt(2)
    n = src.shape[1]
    if i0 < 0:
        src = src[:, -i0:]
        n = src.shape[1]
        i0 = 0
    n = min(n, N - i0)
    if n > 0:
        dst[:, i0:i0 + n] += src[:, :n] * gain


def env_adsr(n, a, d, s, r, hold=None):
    """Linear-attack, exponential decay/release envelope of n samples."""
    t = t_axis(n)
    hold = (n / SR - r) if hold is None else hold
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    rel = t > hold
    e[rel] = e[rel] * np.exp(-(t[rel] - hold) / max(r, 1e-6))
    return e


def polyblep_saw(freq, n, phase0=0.0):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    dt = f / SR
    ph = (phase0 + np.cumsum(dt)) % 1.0
    saw = 2 * ph - 1
    # PolyBLEP correction at the wrap.
    m1 = ph < dt
    x = ph[m1] / dt[m1]
    saw[m1] -= x + x - x * x - 1
    m2 = ph > 1 - dt
    x = (ph[m2] - 1) / dt[m2]
    saw[m2] -= x * x + x + x + 1
    return saw


def biquad(kind, fc, q=0.707, gain_db=0.0):
    w = 2 * np.pi * min(fc, SR * 0.45) / SR
    cw, sw = np.cos(w), np.sin(w)
    al = sw / (2 * q)
    A = 10 ** (gain_db / 40)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + al, -2 * cw, 1 - al]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + al, -2 * cw, 1 - al]
    elif kind == "bp":
        b = [al, 0, -al]
        a = [1 + al, -2 * cw, 1 - al]
    elif kind == "lowshelf":
        sq = 2 * np.sqrt(A) * al
        b = [A * ((A + 1) - (A - 1) * cw + sq), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - sq)]
        a = [(A + 1) + (A - 1) * cw + sq, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sq]
    elif kind == "highshelf":
        sq = 2 * np.sqrt(A) * al
        b = [A * ((A + 1) + (A - 1) * cw + sq), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sq)]
        a = [(A + 1) - (A - 1) * cw + sq, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sq]
    else:
        raise ValueError(kind)
    b, a = np.array(b), np.array(a)
    return b / a[0], a / a[0]


def filt(x, kind, fc, q=0.707, gain_db=0.0):
    b, a = biquad(kind, fc, q, gain_db)
    return signal.lfilter(b, a, x, axis=-1)


def filt_sweep(x, kind, fc_curve, q=0.707, block=256):
    """Time-varying biquad; fc_curve is a per-sample cutoff array."""
    y = np.zeros_like(x)
    zi = None
    for i in range(0, x.shape[-1], block):
        seg = x[..., i:i + block]
        b, a = biquad(kind, float(fc_curve[min(i + block // 2, len(fc_curve) - 1)]), q)
        if zi is None:
            zi = np.zeros(x.shape[:-1] + (2,))
        y[..., i:i + block], zi = signal.lfilter(b, a, seg, axis=-1, zi=zi)
    return y


def curve(points, n=N):
    """Piecewise-linear curve through (t, v) points over n samples."""
    ts = np.array([p[0] for p in points]) * SR
    vs = np.array([p[1] for p in points])
    return np.interp(np.arange(n), ts, vs)


def curve_exp(points, n=N):
    """Like curve() but interpolates in log space (for frequencies)."""
    return np.exp(curve([(t, np.log(v)) for t, v in points], n))


# --------------------------------------------------------------------------
# Instruments
# --------------------------------------------------------------------------

def pad_note(m, dur, a=1.2, r=1.8, detunes=(-11, -5, 0, 5, 11), bright=1.0):
    n = int((dur + r) * SR)
    out = np.zeros((2, n))
    f0 = midi(m)
    for i, c in enumerate(detunes):
        f = f0 * 2 ** (c / 1200)
        # Slow vibrato-free drift for width.
        drift = 1 + 0.0015 * np.sin(2 * np.pi * (0.13 + 0.05 * i) * t_axis(n) + i)
        s = polyblep_saw(f * drift, n, phase0=rng.random())
        ch = i % 2 if c != 0 else None
        if ch is None:
            out += s * 0.7
        else:
            out[ch] += s
            out[1 - ch] += s * 0.35
    sub = np.sin(2 * np.pi * f0 / 2 * t_axis(n)) * 0.25 * bright
    out += sub
    e = env_adsr(n, a, 3.0, 0.85, r, hold=dur)
    return out * e / len(detunes)


def chord_pad(dst, notes, t0, dur, gain, **kw):
    for m in notes:
        place(dst, pad_note(m, dur, **kw), t0, gain)


def fm_pluck(m, dur=0.5, ratio=2.0, index=2.2, tau=0.22, click=0.0):
    n = int(dur * SR)
    t = t_axis(n)
    f = midi(m)
    idx = index * np.exp(-t / 0.09)
    s = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * ratio * t))
    s *= np.exp(-t / tau) * np.minimum(1, t / 0.003)
    if click:
        s += click * rng.standard_normal(n) * np.exp(-t / 0.002)
    return s


def bell(m, dur=2.4, tau=0.9, index=1.4):
    n = int(dur * SR)
    t = t_axis(n)
    f = midi(m)
    idx = index * np.exp(-t / 0.35)
    s = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * 3.5 * t))
    s += 0.25 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t / (tau * 0.5))
    return s * np.exp(-t / tau) * np.minimum(1, t / 0.004)


def bass_note(m, dur, gain=1.0):
    n = int((dur + 0.08) * SR)
    t = t_axis(n)
    f = midi(m)
    s = 0.7 * np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * 2 * f * t)
    saw = filt(polyblep_saw(f, n), "lp", 650)
    s = np.tanh(1.6 * (s * 0.8 + saw * 0.5)) * 0.8
    e = env_adsr(n, 0.006, 0.25, 0.55, 0.06, hold=dur)
    return s * e * gain


def kick(gain=1.0):
    n = int(0.55 * SR)
    t = t_axis(n)
    f = 54 + 110 * np.exp(-t / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * np.exp(-t / 0.19)
    click = filt(rng.standard_normal(n), "bp", 3200, q=0.7) * np.exp(-t / 0.003) * 0.35
    return np.tanh(1.4 * (s + click)) * gain


def snap(gain=1.0):
    n = int(0.35 * SR)
    t = t_axis(n)
    noise = filt(rng.standard_normal(n), "bp", 1900, q=0.9)
    e = np.zeros(n)
    for k, off in enumerate((0.0, 0.009, 0.018)):
        i = int(off * SR)
        e[i:] += np.exp(-(t[i:] - off) / (0.009 if k < 2 else 0.09)) * (0.6 if k < 2 else 1.0)
    return noise * e * gain * 0.6


def hat(open_=False, gain=1.0):
    n = int((0.25 if open_ else 0.08) * SR)
    t = t_axis(n)
    s = filt(filt(rng.standard_normal(n), "hp", 6500), "lp", 11000)
    return s * np.exp(-t / (0.09 if open_ else 0.022)) * gain * 0.38


def noise_sweep(dur, f_from, f_to, q=1.2, shape="hump", gain=1.0):
    n = int(dur * SR)
    fc = np.exp(np.linspace(np.log(f_from), np.log(f_to), n))
    s = filt_sweep(rng.standard_normal(n), "bp", fc, q=q)
    t = np.linspace(0, 1, n)
    if shape == "hump":
        e = np.sin(np.pi * t) ** 1.5
    elif shape == "rise":
        e = t ** 2.2
    else:
        e = (1 - t) ** 2
    return s * e * gain


def boom(gain=1.0, dur=2.2):
    n = int(dur * SR)
    t = t_axis(n)
    f = 38 + 60 * np.exp(-t / 0.09)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * np.exp(-t / 0.7)
    s += filt(rng.standard_normal(n), "lp", 700) * np.exp(-t / 0.12) * 0.35
    return np.tanh(1.2 * s) * gain


def tick(gain=1.0, f=2400):
    n = int(0.05 * SR)
    t = t_axis(n)
    s = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.006)
    s += filt(rng.standard_normal(n), "hp", 4000) * np.exp(-t / 0.0015) * 0.3
    return s * gain


def blip(m, dur=0.16, gain=1.0):
    n = int(dur * SR)
    t = t_axis(n)
    s = np.sin(2 * np.pi * midi(m) * t) * np.exp(-t / 0.05) * np.minimum(1, t / 0.002)
    return s * gain


def glide(f0, f1, dur, gain=1.0):
    n = int(dur * SR)
    t = t_axis(n)
    f = np.exp(np.linspace(np.log(f0), np.log(f1), n))
    s = np.sin(2 * np.pi * np.cumsum(f) / SR)
    return s * np.exp(-t / (dur * 0.45)) * np.minimum(1, t / 0.004) * gain


# --------------------------------------------------------------------------
# Effects
# --------------------------------------------------------------------------

def reverb_ir(seconds=2.8, predelay=0.012):
    n = int(seconds * SR)
    t = t_axis(n)
    ir = np.zeros((2, n + int(predelay * SR)))
    for ch in range(2):
        noise = rng.standard_normal(n)
        bright = filt(noise, "hp", 400) * np.exp(-t / 0.35)
        dark = filt(noise, "lp", 3200) * np.exp(-t / 0.95)
        ir[ch, int(predelay * SR):] = bright * 0.18 + dark
    ir /= np.sqrt(np.sum(ir ** 2) / 2)
    return ir


IR = reverb_ir()


def reverb(x, wet=0.3):
    y = np.vstack([signal.fftconvolve(x[c], IR[c])[:N] for c in range(2)])
    y = filt(y, "hp", 180)
    return y * wet


def pingpong(x, delay=0.45, fb=0.38, wet=0.35, lp=4200):
    d = int(delay * SR)
    y = np.zeros_like(x)
    mono = x.mean(axis=0)
    tap = filt(mono, "lp", lp)
    g = 1.0
    for k in range(1, 7):
        g *= fb
        ch = k % 2
        seg = tap[: N - k * d] * g
        y[ch, k * d:] += seg
        tap = filt(tap, "lp", lp * 0.9)
    return y * wet


def sidechain(kicks_times, depth_db=3.0, release=0.2):
    g = np.ones(N)
    t = t_axis(int(0.6 * SR))
    dip = 1 - (1 - 10 ** (-depth_db / 20)) * np.exp(-t / release) * np.minimum(1, t / 0.004 + 0.6)
    for kt in kicks_times:
        i0 = int(kt * SR)
        n = min(len(dip), N - i0)
        if n > 0:
            g[i0:i0 + n] = np.minimum(g[i0:i0 + n], dip[:n])
    return g


# --------------------------------------------------------------------------
# Arrangement (times from brag-plan.md)
# --------------------------------------------------------------------------

D_MAJ9 = [50, 57, 61, 64, 66]
B_M11 = [47, 54, 57, 62, 64]
G_MAJ9 = [43, 50, 54, 57, 59]
A_ADD9 = [45, 52, 57, 59, 61]
B_M7 = [47, 54, 57, 62, 66]


def build():
    pad, arp, bass, drums, fx, fx_verb = buf(), buf(), buf(), buf(), buf(), buf()
    kicks = []
    # ---- 0 - 2.4: air, satellites lock (8ths from 0.6)
    chord_pad(pad, D_MAJ9, 0.0, 2.4, 0.42, a=0.9, r=0.6)
    for i, m in enumerate([78, 81, 85]):
        place(pad, pad_note(m, 2.3, a=1.0, r=0.6, detunes=(-4, 4)), 0.1 + i * 0.2, 0.12)
    for i, (t, m) in enumerate(zip([0.6, 0.9, 1.2, 1.5], [81, 83, 86, 90])):
        place(fx_verb, bell(m, 1.8, tau=0.55, index=0.9), t, 0.2, pan=-0.45 + 0.3 * i)
    place(fx, noise_sweep(1.1, 500, 5000, q=1.3, shape="rise", gain=0.2), 1.3, 1.0)
    # ---- 2.4 - 4.8: lines snap, into the dark
    for i, (t, m) in enumerate(zip([2.4, 2.55, 2.7, 2.85], [90, 86, 83, 81])):
        place(fx, blip(m, 0.09, 0.22), t, 1.0, pan=0.45 - 0.3 * i)
        place(fx, tick(0.18, f=3000 - 300 * i), t, 1.0, pan=0.45 - 0.3 * i)
    place(fx_verb, boom(0.9, 2.4), 3.0, 1.0)
    chord_pad(pad, [35, 42, 47, 54], 3.0, 1.8, 0.32, a=0.05, r=0.3)
    chord_pad(pad, [59, 62, 66], 3.1, 1.6, 0.2, a=0.5, r=0.4)
    rum = filt(np.cumsum(rng.standard_normal(int(2.0 * SR))) * 0.002, "lp", 140)
    rum = rum / (np.abs(rum).max() + 1e-9) * env_adsr(len(rum), 0.2, 5, 1, 0.3, hold=1.8)
    place(fx, rum, 3.0, 0.16)
    for k, t in enumerate(np.arange(3.3, 7.2, 0.3)):
        place(fx, noise_sweep(0.38, 2600, 700, q=1.0, shape="hump", gain=0.12), t - 0.1, 1.0,
              pan=(0.55 if k % 2 else -0.55))
    for t in (3.6, 4.2):
        place(drums, kick(0.2), t)
        place(drums, kick(0.12), t + 0.2)
    place(fx_verb, noise_sweep(0.6, 300, 6000, shape="rise", gain=0.18), 4.2, 1.0)
    # ---- 4.8 - 7.2: the drop, something keeps moving
    for bar_i, (ch, root) in enumerate([(B_M7, 35)]):
        t0 = 4.8
        chord_pad(pad, [m + 12 for m in ch[1:]], t0, 2.4, 0.45, a=0.02, r=0.3)
        for b in range(8):
            place(bass, bass_note(root if b % 4 != 3 else root + 12, 0.24), t0 + b * 0.3, 0.8)
    for t in np.arange(4.8, 7.2 - 1e-6, 0.6):
        place(drums, kick(1.1), t)
        kicks.append(t)
        place(drums, hat(gain=0.5), t + 0.3, pan=0.2)
        place(drums, hat(gain=0.22), t + 0.15, pan=-0.2)
    for t in (5.4, 6.6):
        place(drums, snap(0.45), t)
    for i, t in enumerate(np.arange(6.6, 7.2, 0.15)):
        place(drums, snap(0.16 + 0.08 * i), t)
    for s16 in range(16):
        m = B_M7[[0, 2, 3, 4, 3, 2, 1, 2][s16 % 8]] + 12
        place(arp, fm_pluck(m, 0.3, index=1.6, tau=0.1), 4.8 + s16 * 0.15, 0.3 if s16 % 4 == 0 else 0.2,
              pan=(-0.35 if s16 % 2 else 0.35))
    place(fx, noise_sweep(0.6, 800, 9000, q=0.7, shape="rise", gain=0.2), 6.6, 1.0)
    # ---- 7.2 - 10: light burst, name, final chord rings
    place(fx_verb, boom(0.85, 2.8), 7.2, 1.0)
    place(fx_verb, noise_sweep(2.4, 10000, 500, q=0.5, shape="decay", gain=0.2), 7.2, 1.0)
    chord_pad(pad, D_MAJ9 + [69, 73], 7.2, 2.2, 0.62, a=0.01, r=1.0)
    place(bass, bass_note(26, 2.6, 0.9), 7.2, 0.55)
    for i, m in enumerate([74, 78, 81, 85, 88, 90]):
        place(fx_verb, bell(m, 2.6, tau=0.9, index=0.5), 7.2 + i * 0.15, 0.12, pan=-0.5 + 0.2 * i)
    return pad, arp, bass, drums, fx, fx_verb, kicks


def master(x):
    x = filt(filt(x, "hp", 38), "hp", 38)
    x = filt(x, "lowshelf", 80, gain_db=-3.0)
    x = filt(x, "highshelf", 9000, gain_db=-3.0)
    x = x / np.abs(x).max() * 1.25
    x = np.tanh(x) / np.tanh(1.25)
    x *= curve([(0, 0.0), (0.25, 1.0), (9.4, 1.0), (10.0, 0.0)])
    return x / np.abs(x).max() * 0.89


def write(path, x):
    wavfile.write(path, SR, (np.clip(x.T, -1, 1) * 32767).astype(np.int16))


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    pad, arp, bass, drums, fx, fx_verb, kicks = build()
    duck = sidechain(kicks)
    pad_fc = curve_exp([(0, 900), (2.2, 3200), (2.9, 500), (4.7, 600), (4.9, 1900), (7.1, 2400),
                        (7.3, 6500), (10, 4000)])
    pad_f = filt(filt_sweep(pad, "lp", pad_fc, q=0.8), "hp", 140)
    music = pad_f * duck * 1.25 + arp * duck * 1.7 + bass * duck * 0.62 + drums * 0.62
    music += reverb(pad_f * 0.5 + arp * 0.6 + drums * 0.12, wet=0.32)
    music += pingpong(arp, wet=0.3)
    sfx = fx + fx_verb + reverb(fx_verb, wet=0.55)
    write(os.path.join(out, "music.wav"), master(music.copy()))
    m = master(music + sfx * 0.9)
    write(os.path.join(out, "mix.wav"), m)
    for sec in range(0, 10, 2):
        seg = m[:, sec * SR:(sec + 2) * SR]
        print(f"{sec}-{sec + 2}s rms {20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-9):6.1f} dB")


main()
