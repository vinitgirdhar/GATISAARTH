"""Original score for the GatiSaarth brag video (41.4 s, D minor, 120 BPM).

Arrangement follows the edit:
  0.00  hook      drone, wind, heartbeat thumps, riser, boom on "Your GPS gives up."
  3.27  reveal    pad bloom, bass, soft arp
  6.56  sensors   kick enters
  9.29  tunnel    whole mix muffled (low-pass ~450 Hz) + sonar pings
 13.64  restored  filter sweeps open, shimmer
 14.73  urban     stuttering delayed arp, hats (multipath feel)
 20.20  edge AI   bright 16th arp, claps
 25.60  features  full groove
 37.08  outro     drums stop, big chord + boom, long tail

Deterministic: fixed RNG seed. Writes score.wav (44.1 kHz stereo, 16-bit).
"""
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
DUR = 41.4
N = int(SR * DUR)
T0 = 3.27          # beat grid origin
BEAT = 0.5         # 120 BPM
rng = np.random.default_rng(20260922)
t = np.arange(N) / SR


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def env_ar(n, a, r):
    e = np.ones(n)
    na = max(1, int(a * SR))
    e[:na] = np.linspace(0, 1, na)
    nr = max(1, int(r * SR))
    if nr < n:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def saw(f, n, phase=0.0):
    x = (np.arange(n) / SR * f + phase) % 1.0
    return 2 * x - 1


def place(buf, sig, start):
    i = int(start * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i]


def blockwise_lowpass(x, cutoff_fn, block=1024, order=2):
    y = np.zeros_like(x)
    zi = None
    for s in range(0, len(x), block):
        c = float(np.clip(cutoff_fn((s + block / 2) / SR), 60, 18000))
        b, a = signal.butter(order, c / (SR / 2), "low")
        if zi is None:
            zi = signal.lfilter_zi(b, a) * 0
        y[s:s + block], zi = signal.lfilter(b, a, x[s:s + block], zi=zi)
    return y


def interp(pts):
    xs, ys = zip(*pts)
    return lambda tt: float(np.interp(tt, xs, ys))


# chord progression, 2 bars (4 s) each, from the reveal
CHORDS = [  # root, pad notes
    (38, [50, 53, 57, 62]),   # Dm
    (34, [50, 53, 58, 62]),   # Bb
    (41, [48, 53, 57, 60]),   # F
    (36, [48, 52, 55, 60]),   # C
]


def chord_at(tt):
    k = int(max(0, tt - T0) // 4.0) % len(CHORDS)
    return CHORDS[k]


# ---------------------------------------------------------------- layers
pad = np.zeros(N)
bass = np.zeros(N)
arp = np.zeros(N)
drums = np.zeros(N)
fx = np.zeros(N)

# drone + wind under the hook
drone_n = int(3.6 * SR)
dr = sum(np.sin(2 * np.pi * midi(m) * t[:drone_n] + p) for m, p in [(38, 0), (45, 1.0), (50, 2.0)]) / 3
dr *= env_ar(drone_n, 0.8, 0.8) * 0.5
place(fx, dr, 0.0)
wind = rng.standard_normal(int(3.6 * SR))
b, a = signal.butter(2, [300 / (SR / 2), 1400 / (SR / 2)], "band")
wind = signal.lfilter(b, a, wind) * env_ar(len(wind), 1.0, 0.6) * 0.12
place(fx, wind, 0.0)

# heartbeat thumps on the three hook words, boom on the red line
def thump(f0=70, f1=38, d=0.45, amp=0.8):
    n = int(d * SR)
    tt = np.arange(n) / SR
    freq = f1 + (f0 - f1) * np.exp(-tt * 18)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(ph) * np.exp(-tt * (7 / d)) * amp


for s in (0.52, 1.05, 1.60):
    place(fx, thump(amp=0.55), s)


def boom(d=2.4, amp=1.0):
    n = int(d * SR)
    tt = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(34 + 50 * np.exp(-tt * 9)) / SR) * np.exp(-tt * 1.6)
    nz = rng.standard_normal(n)
    bb, aa = signal.butter(2, 900 / (SR / 2), "low")
    nz = signal.lfilter(bb, aa, nz) * np.exp(-tt * 6) * 0.5
    return (body + nz) * amp


place(fx, boom(1.6, 0.8), 2.14)


def riser(d, amp=0.35):
    n = int(d * SR)
    tt = np.arange(n) / SR
    nz = rng.standard_normal(n)
    out = np.zeros(n)
    blk = 1024
    zi = None
    for s in range(0, n, blk):
        c = 400 + 7000 * (s / n) ** 2
        bb, aa = signal.butter(2, c / (SR / 2), "low")
        if zi is None:
            zi = np.zeros(max(len(aa), len(bb)) - 1)
        out[s:s + blk], zi = signal.lfilter(bb, aa, nz[s:s + blk], zi=zi)
    tone = np.sin(2 * np.pi * np.cumsum(200 + 700 * (tt / d) ** 2) / SR) * 0.25
    return (out + tone) * (tt / d) ** 2 * amp


place(fx, riser(1.3), 3.27 - 1.3)
place(fx, riser(1.6, 0.4), 37.08 - 1.6)
place(fx, riser(0.9, 0.22), 25.6 - 0.9)

# pad: detuned saws per chord, 4-s blocks from the reveal, fades through the outro
for k in range(9):
    s0 = T0 + k * 4.0
    if s0 >= 37.08:
        break
    d = min(4.0, 37.08 - s0) + 0.4
    n = int(d * SR)
    _, notes = CHORDS[k % 4]
    sig = np.zeros(n)
    for m in notes:
        for det in (-0.08, 0.0, 0.08):
            sig += saw(midi(m + det), n, phase=rng.random())
    sig *= env_ar(n, 0.35 if k == 0 else 0.08, 0.4) / (len(notes) * 3)
    place(pad, sig * 0.55, s0)
# outro chord: Dm(add9) wide, long
n = int(4.4 * SR)
sig = np.zeros(n)
for m in [38, 50, 57, 62, 64, 65, 69]:
    for det in (-0.1, 0.0, 0.1):
        sig += saw(midi(m + det), n, phase=rng.random())
sig *= env_ar(n, 0.02, 3.2) / 21
place(pad, sig * 0.8, 37.08)

# bass: root, 8th-note pulse from 6.56, sustained before
for k in range(int((37.08 - T0) / (BEAT / 2))):
    st = T0 + k * BEAT / 2
    root, _ = chord_at(st)
    d = BEAT / 2 * 0.9
    nn = int(d * SR)
    tt = np.arange(nn) / SR
    sq = np.sign(np.sin(2 * np.pi * midi(root) * tt)) * 0.35 + np.sin(2 * np.pi * midi(root) * tt)
    amp = 0.18 if st < 6.56 else 0.32
    place(bass, sq * np.exp(-tt * 6) * amp, st)

# arp: chord tones, 8ths (16ths in the AI + features sections), from the reveal
pat = [0, 2, 1, 3, 2, 1, 3, 0]
k = 0
st = T0
while st < 37.0:
    sixteenth = 20.2 <= st < 37.08
    step = BEAT / 4 if sixteenth else BEAT / 2
    _, notes = chord_at(st)
    m = notes[pat[k % 8]] + 12
    d = 0.22
    nn = int(d * SR)
    tt = np.arange(nn) / SR
    v = (saw(midi(m), nn) * 0.6 + np.sign(np.sin(2 * np.pi * midi(m) * tt)) * 0.4) * np.exp(-tt * 14)
    amp = 0.10 if st < 6.56 else 0.16
    if 14.73 <= st < 20.2 and k % 4 == 3:
        # multipath stutter: repeat the note as quick echoes
        for e in range(3):
            place(arp, v * amp * 0.5 * (0.6 ** e), st + 0.06 * (e + 1))
    place(arp, v * amp, st)
    st += step
    k += 1


# drums: kick on quarters from 6.56, hats from 14.73, claps from 20.2
def kick():
    return thump(150, 45, 0.32, 0.9)


def hat(d=0.04, amp=0.12):
    n = int(d * SR)
    nz = rng.standard_normal(n)
    bb, aa = signal.butter(2, 7000 / (SR / 2), "high")
    return signal.lfilter(bb, aa, nz) * np.exp(-np.arange(n) / SR * 90) * amp


def clap(amp=0.22):
    n = int(0.18 * SR)
    nz = rng.standard_normal(n)
    bb, aa = signal.butter(2, [900 / (SR / 2), 4000 / (SR / 2)], "band")
    nz = signal.lfilter(bb, aa, nz)
    tt = np.arange(n) / SR
    e = np.exp(-tt * 22) + 0.6 * np.exp(-np.maximum(tt - 0.012, 0) * 30) * (tt > 0.012)
    return nz * e * amp


beat_i = 0
bt = T0
while bt < 37.08:
    if bt >= 6.5:
        place(drums, kick() * (0.55 if 9.29 <= bt < 13.64 else 1.0), bt)
    if bt >= 14.7:
        place(drums, hat(amp=0.09), bt + BEAT / 2)
        if bt >= 20.2:
            place(drums, hat(amp=0.05), bt + BEAT / 4)
            place(drums, hat(amp=0.05), bt + 3 * BEAT / 4)
    if bt >= 20.2 and beat_i % 2 == 1:
        place(drums, clap(), bt)
    bt += BEAT
    beat_i += 1

# sonar pings in the tunnel, shimmer on GNSS restore, booms on major cuts
for s in (9.29, 11.29):
    n = int(1.6 * SR)
    tt = np.arange(n) / SR
    ping = np.sin(2 * np.pi * 1318.5 * tt) * np.exp(-tt * 5)
    for e in range(4):
        place(fx, ping * 0.16 * (0.45 ** e), s + e * 0.3)
n = int(2.2 * SR)
tt = np.arange(n) / SR
shimmer = sum(np.sin(2 * np.pi * midi(m) * tt) for m in (74, 77, 81, 86)) * np.exp(-tt * 1.8) * 0.06
place(fx, shimmer, 13.64)
for s, amp in ((3.27, 0.55), (9.29, 0.6), (20.2, 0.45), (37.08, 1.0)):
    place(fx, boom(2.4 if s == 37.08 else 1.4, amp), s)

# ---------------------------------------------------------------- mix
# music bus: muffled through the tunnel, opens on restore
cut = interp([(0, 1800), (3.27, 1800), (6.5, 3200), (9.2, 3200), (9.45, 450), (13.5, 450),
              (14.2, 5000), (20.1, 5000), (20.4, 9000), (37.0, 9000), (41.4, 6000)])
music = pad * 1.15 + bass * 0.55 + arp * 1.35 + drums * 0.8
music = blockwise_lowpass(music, cut)
mix = music + fx * 0.8
hb, ha = signal.butter(2, 38 / (SR / 2), 'high')
mix = signal.lfilter(hb, ha, mix)
# gentle low-shelf cut: subtract part of the <120 Hz band
lb, la = signal.butter(2, 120 / (SR / 2), 'low')
mix = mix - 0.35 * signal.lfilter(lb, la, mix)

# stereo: slight width from a short delay on the pad/arp, plus a synthetic reverb
L = mix.copy()
R = mix.copy()
wide = blockwise_lowpass(pad + arp, cut)
d = int(0.012 * SR)
R[d:] += wide[:-d] * 0.35
L += wide * 0.1
ir_n = int(2.2 * SR)
irt = np.arange(ir_n) / SR
irL = rng.standard_normal(ir_n) * np.exp(-irt * 2.8)
irR = rng.standard_normal(ir_n) * np.exp(-irt * 2.8)
send = blockwise_lowpass(pad + arp + fx * 0.6, lambda _: 5000)
revL = signal.fftconvolve(send, irL)[:N]
revR = signal.fftconvolve(send, irR)[:N]
revL /= np.max(np.abs(revL)) + 1e-9
revR /= np.max(np.abs(revR)) + 1e-9
L += revL * 0.18 * np.max(np.abs(mix))
R += revR * 0.18 * np.max(np.abs(mix))

st = np.stack([L, R], axis=1)
# fade in/out and soft clip
fade = np.ones(N)
fi = int(0.25 * SR)
fade[:fi] = np.linspace(0, 1, fi)
fo = int(1.2 * SR)
fade[-fo:] = np.linspace(1, 0, fo) ** 1.5
st *= fade[:, None]
st /= np.max(np.abs(st)) + 1e-9
st = np.tanh(st * 1.4) / np.tanh(1.4)
st *= 10 ** (-1.0 / 20)
wavfile.write("score.wav", SR, (st * 32767).astype(np.int16))
print("wrote score.wav", N / SR, "s")
