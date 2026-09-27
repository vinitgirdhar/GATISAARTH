"""Original score + sound design for the GatiSaarth launch film.

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
DUR = 60.0
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
D_F = [42, 57, 62, 64, 66]

PROG = [(G_MAJ9, 43), (D_MAJ9, 38), (A_ADD9, 45), (B_M7, 47)]  # groove loop (chord, bass root)


def build():
    pad, arp, bass, drums, fx, fx_verb = buf(), buf(), buf(), buf(), buf(), buf()
    kick_times = []

    # ---- Act I: 0 - 7.2 -------------------------------------------------
    chord_pad(pad, D_MAJ9, 0.0, 4.8, 0.55, a=1.6, r=1.2)
    chord_pad(pad, B_M11, 4.8, 2.4, 0.5, a=0.25, r=0.5)
    # airy top: slow shimmer an octave up
    for i, m in enumerate([78, 81, 85]):
        place(pad, pad_note(m, 4.6, a=2.0, r=1.0, detunes=(-4, 4)), 0.2 + i * 0.3, 0.12)
    # satellite locks, one per beat
    for i, (t, m) in enumerate(zip([1.2, 1.8, 2.4, 3.0, 3.6], [81, 83, 86, 88, 90])):
        place(fx_verb, bell(m, 2.0, tau=0.6, index=0.9), t, 0.20, pan=-0.6 + 0.3 * i)
    # satellite snaps, descending ticks on 8ths
    for i, (t, m) in enumerate(zip([5.4, 5.7, 6.0, 6.3, 6.6], [90, 88, 86, 83, 81])):
        place(fx, blip(m, 0.09, 0.22), t, 1.0, pan=0.6 - 0.3 * i)
        place(fx, tick(0.18, f=3000 - 300 * i), t, 1.0, pan=0.6 - 0.3 * i)
    # riser into the tunnel mouth
    place(fx, noise_sweep(2.3, 500, 5000, q=1.4, shape="rise", gain=0.22), 4.9, 1.0)
    # camera push whoosh
    place(fx, noise_sweep(1.2, 2500, 300, q=0.8, shape="hump", gain=0.25), 6.0, 1.0)

    # ---- Act II: tunnel 7.2 - 14.4 ---------------------------------------
    place(fx_verb, boom(0.95, 2.6), 7.2, 1.0)
    # dark drone
    chord_pad(pad, [35, 42, 47, 54], 7.2, 7.2, 0.30, a=0.05, r=0.4, bright=1.0)
    chord_pad(pad, [59, 62, 66], 7.4, 2.2, 0.20, a=0.8, r=0.6)
    # tunnel rumble
    rum = filt(np.cumsum(rng.standard_normal(int(7.6 * SR))) * 0.002, "lp", 140)
    rum = rum / (np.abs(rum).max() + 1e-9) * env_adsr(len(rum), 0.3, 5, 1, 0.5, hold=7.0)
    place(fx, rum, 7.2, 0.16)
    # "GNSS lost." — descending two-tone
    place(fx_verb, glide(1318, 659, 0.32, 0.16), 7.8, 1.0, pan=0.1)
    place(fx_verb, glide(880, 440, 0.4, 0.13), 8.1, 1.0, pan=-0.1)
    # tunnel lights passing: one soft whoosh per beat
    for k, t in enumerate(np.arange(7.8, 14.3, BEAT)):
        place(fx, noise_sweep(0.42, 2600, 700, q=1.0, shape="hump", gain=0.15), t - 0.12, 1.0,
              pan=(0.55 if k % 2 else -0.55))
    # heartbeat under "GNSS lost."
    for t in (7.8, 8.4, 9.0):
        place(drums, kick(0.2), t)
        place(drums, kick(0.12), t + 0.2)
    # the drop — "Navigation continues." at 9.6
    place(fx_verb, noise_sweep(0.6, 300, 6000, shape="rise", gain=0.18), 9.0, 1.0)
    for bar_i, (ch, root) in enumerate([(B_M7, 35), (G_MAJ9, 31)]):
        t0 = 9.6 + bar_i * BAR
        chord_pad(pad, [m + 12 for m in ch[1:]], t0, BAR, 0.28, a=0.02, r=0.3)
        for b in range(8):
            place(bass, bass_note(root if b % 4 != 3 else root + 12, 0.24), t0 + b * 0.3, 0.55)
    # G -> A turn at 13.2
    for b in range(4):
        place(bass, bass_note(33, 0.24), 13.2 + b * 0.3, 0.55)
    for t in np.arange(9.6, 14.4 - 1e-6, BEAT):
        place(drums, kick(0.85), t)
        kick_times.append(t)
        place(drums, hat(gain=0.5), t + 0.3, pan=0.2)
    for t in np.arange(10.2, 14.4, 1.2):
        place(drums, snap(0.45), t, pan=-0.1)

    # ---- Exit + recovery 14.4 - 19.2 ------------------------------------
    place(fx_verb, noise_sweep(1.6, 400, 12000, q=0.6, shape="decay", gain=0.30), 14.4, 1.0)
    place(fx, noise_sweep(0.5, 800, 9000, q=0.7, shape="rise", gain=0.18), 13.95, 1.0)
    chord_pad(pad, D_MAJ9, 14.4, 2.4, 0.55, a=0.03, r=0.8)
    chord_pad(pad, A_ADD9, 16.8, 2.4, 0.5, a=0.1, r=0.8)
    for i, (t, m) in enumerate(zip([15.0, 15.3, 15.6, 15.9, 16.2], [81, 83, 86, 88, 90])):
        place(fx_verb, bell(m, 1.8, tau=0.55, index=0.8), t, 0.18, pan=-0.6 + 0.3 * i)
    for bar_i, root in enumerate([38, 33]):
        t0 = 14.4 + bar_i * BAR
        for b in range(8):
            place(bass, bass_note(root if b % 2 == 0 else root + 12, 0.24), t0 + b * 0.3, 0.5)
    for t in np.arange(14.4, 19.2 - 1e-6, BEAT):
        place(drums, kick(0.8), t)
        kick_times.append(t)
        place(drums, hat(gain=0.55), t + 0.3, pan=0.2)
        place(drums, hat(gain=0.25), t + 0.15, pan=-0.2)
    for t in np.arange(15.0, 19.2, 1.2):
        place(drums, snap(0.5), t)

    # ---- Brand 19.2 - 24.0 -----------------------------------------------
    place(fx_verb, boom(0.8, 2.8), 19.2, 1.0)
    place(fx_verb, noise_sweep(2.2, 9000, 600, q=0.5, shape="decay", gain=0.18), 19.2, 1.0)
    chord_pad(pad, G_MAJ9, 19.2, 2.4, 0.6, a=0.02, r=1.2)
    chord_pad(pad, D_F, 21.6, 2.4, 0.55, a=0.3, r=1.0)
    for i, m in enumerate([74, 78, 81, 86]):
        place(fx_verb, bell(m, 2.4, tau=0.9, index=0.6), 19.2 + i * 0.15, 0.14, pan=-0.3 + 0.2 * i)
    place(bass, bass_note(31, 2.2, 0.8), 19.2, 0.6)
    place(bass, bass_note(30, 1.0, 0.8), 21.6, 0.55)
    for t in np.arange(22.8, 24.0 - 1e-6, BEAT):
        place(drums, kick(0.75), t)
        kick_times.append(t)
    place(fx, noise_sweep(1.2, 600, 7000, shape="rise", gain=0.14), 22.8, 1.0)

    # ---- Features groove 24.0 - 52.8 (12 bars) --------------------------
    arp_pattern = [0, 2, 3, 4, 3, 2, 1, 2]
    for bar in range(12):
        t0 = 24.0 + bar * BAR
        ch, root = PROG[bar % 4]
        chord_pad(pad, ch, t0, BAR, 0.36, a=0.08, r=0.6)
        bright = 0.18 + 0.12 * (bar / 11)
        for s16 in range(16):
            m = ch[arp_pattern[s16 % 8]] + 12 + (12 if s16 % 8 == 3 else 0)
            place(arp, fm_pluck(m, 0.35, index=1.4 + bar * 0.06, tau=0.12), t0 + s16 * 0.15,
                  bright * (1.0 if s16 % 4 == 0 else 0.62), pan=(-0.35 if s16 % 2 else 0.35))
        for b in range(8):
            m = root if b not in (3, 7) else root + 12
            place(bass, bass_note(m, 0.24), t0 + b * 0.3, 0.55)
        for b in range(4):
            place(drums, kick(0.82), t0 + b * BEAT)
            kick_times.append(t0 + b * BEAT)
            place(drums, hat(gain=0.5), t0 + b * BEAT + 0.3, pan=0.25)
            place(drums, hat(gain=0.22), t0 + b * BEAT + 0.15, pan=-0.25)
            place(drums, hat(gain=0.22), t0 + b * BEAT + 0.45, pan=-0.25)
        for b in (1, 3):
            place(drums, snap(0.5), t0 + b * BEAT)
        if bar % 4 == 3:
            place(drums, hat(open_=True, gain=0.35), t0 + 7 * 0.3)

    # scene accents inside the groove
    for i, t in enumerate([25.2, 25.8, 26.4]):            # sensor rows
        place(fx, tick(0.32, f=2200 + 200 * i), t, 1.0, pan=-0.3)
        place(fx_verb, fm_pluck(86 + 2 * i, 0.4, index=0.8, tau=0.1), t, 0.10, pan=-0.3)
    for i, (t, m) in enumerate(zip([29.4, 30.0, 30.6, 31.2, 31.8], [83, 86, 88, 90, 93])):
        place(fx_verb, blip(m, 0.2, 0.2), t, 1.0, pan=-0.5 + 0.25 * i)   # state columns
    place(fx, noise_sweep(0.62, 600, 8000, shape="rise", gain=0.16), 31.8, 1.0)  # converge
    place(fx_verb, bell(93, 1.2, tau=0.4, index=0.6), 33.0, 0.16)       # dot lands
    for i, t in enumerate([34.8, 35.7, 36.6]):            # physics chips
        place(fx, tick(0.3, f=2000 + 250 * i), t, 1.0, pan=0.3)
    for i, t in enumerate(np.arange(38.7, 40.3, 0.26)):   # typing
        place(fx, tick(0.12, f=3200 + 150 * (i % 3)), t, 1.0, pan=0.25)
    place(fx, tick(0.3, f=2300), 41.4, 1.0, pan=0.3)       # route stats lift
    place(fx_verb, fm_pluck(90, 0.5, index=0.7, tau=0.14), 41.4, 0.1)
    for i, t in enumerate([44.4, 45.0, 45.6]):            # trust cards
        place(fx, tick(0.3, f=2100 + 250 * i), t, 1.0, pan=0.35)
    for i, t in enumerate([48.6, 49.2, 49.8]):            # tested cards
        place(fx, noise_sweep(0.45, 3500, 900, q=0.9, shape="hump", gain=0.13), t - 0.1, 1.0,
              pan=-0.4 + 0.4 * i)
    place(fx, noise_sweep(2.4, 400, 9000, q=1.1, shape="rise", gain=0.2), 50.4, 1.0)  # build

    # ---- Outro 52.8 - 60 -------------------------------------------------
    chord_pad(pad, B_M7, 52.8, 1.2, 0.4, a=0.02, r=0.3)
    chord_pad(pad, A_ADD9, 54.0, 1.2, 0.4, a=0.02, r=0.3)
    for b in range(8):
        place(bass, bass_note(35 if b < 4 else 33, 0.24), 52.8 + b * 0.3, 0.55)
    for t in np.arange(52.8, 55.2 - 1e-6, BEAT):
        place(drums, kick(0.82), t)
        kick_times.append(t)
        place(drums, hat(gain=0.5), t + 0.3)
    for t in (53.4, 54.6):
        place(drums, snap(0.5), t)
    for i, t in enumerate(np.arange(54.6, 55.2, 0.15)):
        place(drums, snap(0.18 + 0.08 * i), t)
    # lockup — final chord blooms and rings
    place(fx_verb, boom(0.85, 3.2), 55.2, 1.0)
    place(fx_verb, noise_sweep(3.0, 10000, 500, q=0.5, shape="decay", gain=0.18), 55.2, 1.0)
    chord_pad(pad, D_MAJ9 + [69, 73], 55.2, 3.6, 0.62, a=0.01, r=1.6)
    place(bass, bass_note(26, 3.4, 0.9), 55.2, 0.55)
    for i, m in enumerate([74, 78, 81, 85, 88, 90]):
        place(fx_verb, bell(m, 3.0, tau=1.1, index=0.5), 55.2 + i * 0.18, 0.12, pan=-0.5 + 0.2 * i)
    return pad, arp, bass, drums, fx, fx_verb, kick_times


def master(x):
    x = filt(filt(x, "hp", 38), "hp", 38)
    x = filt(x, "lowshelf", 80, gain_db=-3.0)
    x = filt(x, "highshelf", 9000, gain_db=-3.0)
    peak = np.abs(x).max()
    x = x / peak * 1.25
    x = np.tanh(x) / np.tanh(1.25)  # gentle saturation
    # final fades
    x *= curve([(0, 0.0), (0.35, 1.0), (59.3, 1.0), (60.0, 0.0)])
    return x / np.abs(x).max() * 0.89


def write(path, x):
    wavfile.write(path, SR, (np.clip(x.T, -1, 1) * 32767).astype(np.int16))


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    pad, arp, bass, drums, fx, fx_verb, kicks = build()
    duck = sidechain(kicks)
    # pad filter: bright intro, closes into the tunnel, opens on the exit
    pad_fc = curve_exp([(0, 700), (2.4, 2600), (4.8, 3200), (7.0, 500), (9.4, 600), (9.7, 1800),
                        (14.2, 2200), (14.5, 4200), (19.2, 5200), (24, 3600), (52.8, 5200),
                        (55.2, 7000), (60, 4000)])
    pad_f = filt_sweep(pad, "lp", pad_fc, q=0.8)
    pad_f = filt(pad_f, "hp", 140)
    music = pad_f * duck * 1.25 + arp * duck * 1.7 + bass * duck * 0.62 + drums * 0.62
    music += reverb(pad_f * 0.5 + arp * 0.6 + drums * 0.12, wet=0.32)
    music += pingpong(arp, wet=0.3)
    sfx = fx + fx_verb + reverb(fx_verb, wet=0.55)
    write(os.path.join(out, "music.wav"), master(music.copy()))
    mix = music + sfx * 0.9
    write(os.path.join(out, "mix.wav"), master(mix))
    # stats
    m = master(mix)
    rms = np.sqrt(np.mean(m ** 2))
    print(f"peak {np.abs(m).max():.3f} rms {20 * np.log10(rms):.1f} dBFS")
    for sec in range(0, 60, 4):
        seg = m[:, sec * SR:(sec + 4) * SR]
        print(f"{sec:2d}-{sec + 4:2d}s rms {20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-9):6.1f} dB")


main()
