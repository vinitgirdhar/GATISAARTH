# Brag Plan: GatiSaarth — "Navigation beyond GNSS" (launch film, v5.2.1)

## What is this app?
GatiSaarth is an offline-first Android navigator that keeps guiding the vehicle when GNSS disappears (tunnels, underpasses, urban canyons). It fuses the phone's own accelerometer, gyroscope, magnetometer and barometer in a 15-state error-state Kalman filter, holds the estimate to offline vector maps and planned routes, watches GNSS health, and validates the fix when the signal comes back. It runs entirely on the phone.

## The angle
A flagship product film in the style of an Apple product reveal, not a demo. One hero object, the phone, moves through a single continuous world. The spine is one real drive, recorded on the Pixel 9 emulator on 2026-09-27 in **airplane mode**. It starts on Marine Drive in Mumbai, enters the real Mumbai Coastal Road tunnel (3.24 km in the app's road data, "TUNNELS 1" on the planned route), keeps navigating on dead reckoning inside, and comes out to a validated fix. The world is bright. It turns graphite only while we are inside the tunnel, and the light returns when the signal does. The app's own light and dark themes carry that: light footage outside, dark footage inside.

Every pixel inside the phone and every floating UI card is real app footage or a real frame from it, captured from `app-release` v5.2.1 (build 52). Nothing is redesigned, nothing is borrowed from other navigation apps. The GNSS outage is the app's own **Simulation Lab → Tunnel test**, started at the real tunnel portal while the fed GNSS kept arriving (the app withholds it). This is honest, and scene 11 says so by showing the Simulation Lab.

Honesty rules (from `CLAUDE.md`):
- No accuracy, drift or benchmark numbers anywhere. Uncertainty is shown only as the app draws it.
- The edge-AI speed model is presented as on-device and advisory, which is what the app itself says. There is no claim that it reduces drift.
- No lane-level claims.
- "Recorded in airplane mode" is literally true for all driving and planning footage.

## Hook (first 2-3 seconds)
White studio. A phone rises into frame in 3D, already navigating along the curve of Marine Drive: GNSS locked, "Tunnel 1.2 km ahead · GNSS loss preparation". Five satellites (GPS G05, Galileo E24, GLONASS R12, BeiDou C19, NavIC I03) lock onto it one per beat, drawn as hairlines. Headline: **"Guided by satellites."**

## Key moments (the middle)
- The satellite lines snap one by one as the phone flies into the tunnel mouth. The world dims to graphite and the screen turns dark: **"Until the signal disappears."**
- Real dead reckoning in the dark theme: red puck, dashed red trail, "Dead reckoning", "GPS lost · following the saved route". The badges lift out of the screen. **"GNSS lost." / "Navigation continues."**
- The exit bursts to white. The real recovery plays: Reacquiring GNSS → "Syncing · Re-syncing position" → Synced → GNSS locked, "GNSS restored · validating the returned fix". The satellites reconnect. **"Signal returns." / "Verified before it's trusted."**
- The real sensor rows (Accelerometer / Gyroscope / Magnetometer, 50 Hz, Live) float out while thin x/y/z axes, a gyro arc and a compass needle draw around the phone. **"Powered by the sensors already in your phone."**
- 15 state dots (Position, Velocity, Attitude, Accel bias, Gyro bias, 3 each) light column by column, then collapse into one blue dot. The Live navigation screen shows the IMU stream counting. **"One filter. Fifteen states."**

## Outro / punchline
**"Navigation that keeps moving."** Then the lockup: the app icon, "GatiSaarth", "Navigation beyond GNSS.", and a small line "Offline-first · On-device · Android". It ends on white, held.

## User flow worth showing
1. Entry: Plan a journey, typed "Worli", offline results, "Reading roads", then the route card showing 12 km · 11 min · 7 turns · **TUNNELS 1** · "Saved for offline use" → Start.
2. Key action: drive; "Tunnel ahead · GNSS loss preparation"; GNSS lost in the tunnel; dead reckoning keeps the marker on the saved route.
3. Result: exit, re-sync, "GNSS restored · validating the returned fix", GNSS locked again.

## Tone
- Preset: cinematic (with polished restraint)
- Creative direction: Apple-style flagship product film, bright, precise and confident
- Interpretation: one continuous 3D world with a single hero phone. The camera moves with purpose, the type is large and quiet, and no more than one idea is on screen at a time. The energy comes from the camera and the score, never from clutter. The dark act is the only drama.

## Format: landscape — 1920x1080, 30 fps
## Duration: 60 s (the user asked for about one minute; this overrides /brag's 15-25 s default)

## Visual identity (from the project)
- Background: light #F5F5F7, close to the app's `lightBackground` #F2F2F7, with a white key light. The tunnel act uses graphite #0B0C0F → #1A1D23, never pure black.
- Text: #1D1D1F primary and #6E6E73 secondary on light; #F5F5F7 on dark.
- Accent: the app's blue #007AFF (#2997FF on dark). Status colours from the app: dead reckoning #FF3B30, GNSS locked #34C759, reacquiring #AF52DE, warning #FF9500.
- Display and body font: **Inter 4 variable**, the app's own `assets/fonts/Inter-Variable.ttf`, at optical size 32 (Inter Display). SF Pro's licence only covers mock-ups for Apple platforms, so it cannot be used for an Android product film. Inter Display is the closest licensed equivalent and it is the brand's own face. Weights 600 (headlines), 500 (labels), 400 (secondary), with -0.03em tracking on display sizes. JetBrains Mono (bundled) is used only for the tiny satellite IDs and state labels.
- Strongest visual element: the real map with the red dead-reckoning puck and dashed trail riding the tunnel road.

## Share copy (draft)
GNSS disappears in tunnels. GatiSaarth doesn't: the phone's own sensors, a 15-state Kalman filter and offline maps keep you navigating, all on-device.

## Audio direction
- Role: cinematic support. An original minimal-electronic score composed to picture for this film (no stock track; the bundled "Happy Beats" tracks are corporate, and the user banned that).
- Music: synthesized in Python/numpy at 100 BPM (bar = 2.4 s). Airy Dmaj9 pad intro; Bm filtered descent into the tunnel; near-silence with a sub pulse at "GNSS lost"; the beat drops on "Navigation continues" (9.6 s); a major lift at the tunnel exit (14.4 s); a bloom on the brand (19.2 s); a light groove (G–D–A–Bm) under the features; a riser into the outro; a final chord on the lockup (55.2 s) that rings out.
- Music treatment: starts at 0, fades in over ~1 s; full-scale mix normalised with headroom. The final chord rings to 60 s with a short fade in the last 0.6 s.
- Music cue guidance: the score is written to the picture grid, so every major moment sits exactly on a downbeat. Strong cues: 7.2 s (tunnel entry), 9.6 s (drop), 14.4 s (exit), 19.2 s (brand), 55.2 s (lockup). Beat grid: 0.6 s. Sequential reveals snap to beats and hold at least 0.9 s.
- Audio-reactive treatment: subtle. Music RMS breathes the white key light and the screen glow. No visualizer graphics.
- SFX posture: sparse and motion-matched, synthesized in the same palette: satellite-lock chimes, soft line snaps, a tunnel whoomp, tunnel light-pass whooshes, a light-burst swell, soft UI ticks for floating cards, and a camera whoosh on big moves.
- Audio-coupled moments: satellite locks (5 chimes), satellite snaps (5 descending ticks), tunnel entry (whoomp plus rumble), drop, exit swell, re-lock chimes, card arrivals (ticks), state dots (soft blips), converge (rise), lockup chord.
- Restraint rule: no alarm sounds for the outage, no beeps on every counter, and nothing louder than the music peaks.

## Storyboard (100 BPM grid, bar = 2.4 s)

### Scene 1 — Satellites — 0.0–4.8 s
Phone rises in 3D (light). Screen: L_1 drive on Marine Drive with the "Tunnel … ahead · GNSS loss preparation" card. Five satellites lock on, one per beat (1.2 → 3.6 s), as hairlines to the puck. Text: "Guided by / satellites."
Sequential/interaction: yes, 5 satellites lock one per beat (non-text accents).
Audio intent: air and anticipation. Audio-coupled idea: one chime per lock. Music: pad swell.
Transition mood: dramatic push → Scene 2

### Scene 2 — Into the tunnel — 4.8–7.2 s
Camera pushes into a tunnel portal. Satellite lines snap one by one (5.4 → 6.6 s). The world dims to graphite and the text flips from dark to light. Screen: the tunnel-ahead countdown. Text: "Until the signal / disappears."
Sequential/interaction: yes, 5 line snaps on 8ths. Audio-coupled idea: descending ticks, a filter sweep, and a whoomp at 7.2 s.
Transition mood: dark cut on the downbeat → Scene 3

### Scene 3 — Dead reckoning — 7.2–14.4 s
Graphite world with tunnel light streaks passing. Screen: D_1, the dark-theme dead reckoning. The "Dead reckoning" badge and the "GPS lost · following the saved route" card lift out of the screen. Text: "GNSS lost." (7.8 s) / "Navigation continues." (9.6 s, blue).
Sequential/interaction: 2 isolated UI lifts (10.8 s, 12.0 s).
Audio intent: loss, then resolve. Audio-coupled idea: sub pulse under "GNSS lost", then the beat drops at 9.6 s.
Transition mood: light burst → Scene 4

### Scene 4 — Recovery — 14.4–19.2 s
The exit burst turns the world white. Screen: L_2 recovery (Reacquiring → Syncing → Synced → GNSS locked, "GNSS restored · validating the returned fix"). The satellites reconnect. Text: "Signal returns." / "Verified before it's trusted."
Audio-coupled idea: lift chord plus re-lock chimes.
Transition mood: bloom → Scene 5

### Scene 5 — Brand — 19.2–24.0 s
The phone drops away. "GatiSaarth" (Inter Display 600, very large) with "Navigation beyond GNSS." Audio: bloom impact on 19.2 s.
Transition mood: rise → Scene 6

### Scene 6 — Sensors — 24.0–28.8 s
The phone returns showing the real Sensors tab. Axes, a gyro arc and a compass draw around it. The real Accelerometer, Gyroscope and Magnetometer rows float out one per beat (25.2 / 25.8 / 26.4 s) and hold. Text: "Powered by the sensors / already in your phone."
Audio-coupled idea: a soft tick per row.

### Scene 7 — Filter — 28.8–33.6 s
The rows stream into a 3×5 grid of state dots. Columns light up per beat, with labels Position · Velocity · Attitude · Accel bias · Gyro bias. They collapse into one blue dot that lands on the phone showing Live navigation (the IMU packet counter running). Text: "One filter. / Fifteen states." plus a small line "Error-state Kalman filter · predicts up to 100 Hz".
Audio-coupled idea: blips per column and a rise on the collapse.

### Scene 8 — Physics — 33.6–38.4 s
Screen: light dead reckoning holding the road. Three plain-language chips arrive about 0.9 s apart and hold: "Stops mean zero." (ZUPT) · "No sideways slip." (NHC) · "Held to the road." (MAP LOCK). The real "Car / Four-Wheeler Dynamics Active · Non-holonomic constraint (NHC) zero-lateral slip active" card floats beside them. Text: "Grounded in physics."

### Scene 9 — Offline — 38.4–43.2 s
Screen: Plan a journey, typed "Worli", then the route card. The real stats row with TUNNELS 1 and "Saved for offline use" lifts out. Text: "Offline maps. / Offline routes." Caption: "Recorded in airplane mode."

### Scene 10 — Trust — 43.2–48.0 s
Real "System health · Everything is ready", then isolated real cards arriving one per beat: GNSS HEALTH NORMAL "Receiver evidence is internally consistent"; AI speed estimator "TFLite FP32 model active · Loaded"; Navigation Hardware Check PASS. Text: "It knows what to trust." Caption: "On-device AI, advisory by design."

### Scene 11 — Tested — 48.0–52.8 s
A 3D fan of real screens: Simulation Lab (Tunnel test / Urban canyon test / Timed GPS loss test), the Fault Injection Lab fault list, and the Navigation engine "How it works". Text: "Tested against every outage / we could build." Audio: riser.

### Scene 12 — Outro — 52.8–60.0 s
The phone is centred, driving through the Haji Ali interchange with GNSS locked. "Navigation that keeps moving." (53.1 s). At 55.2 s the lockup: app icon + "GatiSaarth" + "Navigation beyond GNSS." + "Offline-first · On-device · Android". Held on white to 60 s.

**Music mood for this video:** cinematic minimal electronic
**Audio summary:** an airy pad drops into a near-silent tunnel, the beat kicks in on "Navigation continues" and lifts at the exit, a light groove carries the technology, and a final chord rings under the lockup.
