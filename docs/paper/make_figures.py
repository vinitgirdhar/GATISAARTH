"""Builds the paper's figures from the benchmark outputs.

    python docs/paper/make_figures.py <iovnbd_outage_benchmark.json> <synthetic_scores.json>

fig_drift.pdf  - median drift vs blackout length, core vs hold-last-velocity,
                 (a) real IO-VNBD trips, (b) synthetic Mumbai drives.
fig_arch.pdf   - block diagram of the on-phone pipeline.
"""
import json
import statistics
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

OUT = Path(__file__).parent
CORE = "#2a78d6"  # categorical slot 1
HOLD = "#eb6834"  # categorical slot 2
INK = "#0b0b0b"
MUTED = "#52514e"
GRID = "#e4e3df"
WINDOWS = [10, 30, 60, 120]

plt.rcParams.update({
    "font.family": "serif",
    "font.size": 8,
    "axes.edgecolor": MUTED,
    "axes.labelcolor": INK,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "axes.spines.top": False,
    "axes.spines.right": False,
})


def iovnbd_series(path):
    d = json.loads(Path(path).read_text())
    core, hold, trips = [], [], []
    for w in WINDOWS:
        s = d[f"median_over_trips_{w}s"]
        core.append(s["core_drift_pct"])
        hold.append(s["hold_velocity_drift_pct"])
        trips.append(s["trips"])
    return core, hold, trips


def synthetic_series(path, mode="nomap"):
    rows = [r for r in json.loads(Path(path).read_text())
            if "SYNTHETIC" in r["drive"] and r["map"] == mode]
    core, hold, n = [], [], []
    for w in WINDOWS:
        cells = [r[f"{w}s"] for r in rows if f"{w}s" in r]
        core.append(statistics.median(c["core_pct"] for c in cells))
        hold.append(statistics.median(c["hold_pct"] for c in cells))
        n.append(sum(c["n"] for c in cells))
    return core, hold, n


def panel(ax, core, hold, title, note):
    ax.plot(WINDOWS, core, color=CORE, lw=2, marker="o", ms=4,
            label="Navigation core")
    ax.plot(WINDOWS, hold, color=HOLD, lw=2, ls="--", marker="s", ms=4,
            label="Hold last velocity")
    ax.axhline(10, color=MUTED, lw=0.8, ls=":")
    ax.set_xticks(WINDOWS)
    ax.set_xlabel("GNSS blackout (s)")
    ax.set_title(title, fontsize=8, color=INK, loc="left")
    ax.grid(axis="y", color=GRID, lw=0.6)
    ax.set_ylim(0, 100)
    ax.text(0.02, 0.97, note, transform=ax.transAxes, va="top",
            fontsize=6.5, color=MUTED)
    # Direct labels at the right end, so identity is not colour-only.
    ax.annotate("core", (WINDOWS[-1], core[-1]), xytext=(4, 0),
                textcoords="offset points", color=INK, fontsize=7,
                va="center")
    ax.annotate("hold", (WINDOWS[-1], hold[-1]), xytext=(4, 0),
                textcoords="offset points", color=INK, fontsize=7,
                va="center")


def drift_figure(iovnbd_json, synthetic_json):
    ic, ih, it = iovnbd_series(iovnbd_json)
    sc, sh, sn = synthetic_series(synthetic_json)
    fig, (a, b) = plt.subplots(1, 2, figsize=(3.5, 2.1), sharey=True)
    panel(a, ic, ih, "(a) Real IO-VNBD trips",
          f"{min(it)}-{max(it)} trips per point")
    panel(b, sc, sh, "(b) Synthetic Mumbai",
          f"{min(sn)}-{max(sn)} windows per point")
    a.set_ylabel("Median drift (%)")
    b.text(118, 12, "10 % target", ha="right", va="bottom", color=MUTED,
           fontsize=6.5)
    a.legend(loc="upper center", bbox_to_anchor=(1.05, -0.32), ncol=2,
             frameon=False, fontsize=7)
    fig.subplots_adjust(left=0.13, right=0.9, top=0.9, bottom=0.32,
                        wspace=0.22)
    fig.savefig(OUT / "fig_drift.pdf")
    fig.savefig(OUT / "fig_drift.png", dpi=200)


def box(ax, x, y, w, h, text, fill="#ffffff"):
    ax.add_patch(FancyBboxPatch((x, y), w, h,
                                boxstyle="round,pad=0.02,rounding_size=0.08",
                                fc=fill, ec=MUTED, lw=0.8))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center",
            fontsize=6.3, color=INK, linespacing=1.15)


def arrow(ax, p, q):
    ax.add_patch(FancyArrowPatch(p, q, arrowstyle="-|>", mutation_scale=7,
                                 lw=0.8, color=MUTED))


def arch_figure():
    # Full-width (two-column) figure.
    fig, ax = plt.subplots(figsize=(7.0, 2.1))
    ax.set_xlim(-0.1, 20.2)
    ax.set_ylim(-0.1, 6)
    ax.axis("off")
    tint = "#eef4fc"
    # Inputs
    box(ax, 0.0, 4.3, 3.2, 1.3, "IMU: accel, gyro,\nmag, 50-100 Hz")
    box(ax, 0.0, 2.35, 3.2, 1.3, "GNSS: 1 Hz fix,\nDoppler speed,\nbearing")
    box(ax, 0.0, 0.4, 3.2, 1.3, "Offline vector map\n(PMTiles) -> road\ngraph on phone")
    # Core
    box(ax, 4.2, 4.3, 3.8, 1.3, "Online mount alignment\n(phone -> vehicle)", tint)
    box(ax, 4.2, 2.35, 3.8, 1.3, "15-state error-state EKF\nNHC, ZUPT,\nNIS-gated GNSS", tint)
    box(ax, 4.2, 0.4, 3.8, 1.3, "HMM map matcher\n(heading only) + road-\nlocked DR in outage", tint)
    box(ax, 9.0, 4.3, 3.6, 1.3, "Learned speed (TCN)\nused only after it\nagrees with GNSS", tint)
    box(ax, 9.0, 1.6, 3.6, 2.05,
        "Integrity-gated hand-over:\nmount aligned, integrity OK,\nbeats hold-velocity\nwhile GNSS is live")
    box(ax, 9.0, 0.0, 3.6, 1.1, "Heuristic pipeline\n(fallback)")
    box(ax, 13.6, 1.6, 3.0, 2.05, "Output: position,\nspeed, heading,\nuncertainty")
    box(ax, 17.4, 1.6, 2.6, 2.05, "Outage benchmark:\nbit-exact replay,\nGNSS withheld")
    arrow(ax, (3.2, 4.95), (4.2, 4.95))
    arrow(ax, (3.2, 3.0), (4.2, 3.0))
    arrow(ax, (3.2, 1.05), (4.2, 1.05))
    arrow(ax, (6.1, 4.3), (6.1, 3.65))
    arrow(ax, (6.1, 1.7), (6.1, 2.35))
    arrow(ax, (9.0, 4.6), (8.0, 3.3))
    arrow(ax, (8.0, 2.9), (9.0, 2.9))
    arrow(ax, (10.8, 1.1), (10.8, 1.6))
    arrow(ax, (12.6, 2.6), (13.6, 2.6))
    arrow(ax, (16.6, 2.6), (17.4, 2.6))
    fig.subplots_adjust(left=0.005, right=0.995, top=0.99, bottom=0.01)
    fig.savefig(OUT / "fig_arch.pdf")
    fig.savefig(OUT / "fig_arch.png", dpi=200)


if __name__ == "__main__":
    drift_figure(sys.argv[1], sys.argv[2])
    arch_figure()
