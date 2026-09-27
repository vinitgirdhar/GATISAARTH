# Hyperframes Composition Brief: GatiSaarth — "Navigation beyond GNSS"

## Objective
A 60-second flagship launch film for GatiSaarth in the style of an Apple product reveal. The film is bright, precise and cinematic. Every piece of UI in it is real footage from the app.

## Output
- Composition directory: `brag/2026-09-27-132145/composition/` (user asked for a single `brag/` folder at repo root instead of `brag-output-*`)
- Rendered video: `brag/2026-09-27-132145/brag.mp4`
- Format: landscape, 1920x1080, 30 fps
- Duration: 60 s. This is the user's request and overrides /brag's 15-25 s rule.

## Source Material
- Project root: `D:/gathisarthi`
- Primary files read: `CLAUDE.md`, `README.md`, `frontend/lib/core/theme/app_theme.dart`, `features/navigation_ui/.../map_tab.dart`, `features/about/presentation/engine_spec_screen.dart`, `core/nav/map/tunnel_lookahead.dart`, `core/nav/guidance/mission_guidance.dart`, `features/navigation_ui/.../live_session_controller.dart`, the offline-maps skill notes, `frontend/assets/icons/*`, `frontend/assets/fonts/Inter-Variable.ttf`
- Footage: recorded on 2026-09-27 on the Pixel_9 emulator from the installed v5.2.1 (build 52) release, full resolution 1280x2856, via `adb emu screenrecord`, with airplane mode on and a clean status bar (SystemUI demo mode, 9:41). The drive is a real Mumbai route planned in the app (Marine Drive → Mumbai Coastal Road tunnel → Worli Seaface), fed to the emulator's GNSS at 4 Hz with matching virtual magnetometer, gyro and accelerometer values. The outage is the app's Simulation Lab → Tunnel test, started at the real portal.
- Product name: GatiSaarth
- Tagline / strongest claim: "Navigation beyond GNSS" (README: "Intelligent Navigation Beyond GNSS"); the app's own engine copy: "Offline-first navigation that keeps going when GNSS stops."
- Key UI moments (all real): "Tunnel … ahead · GNSS loss preparation"; "Dead reckoning" + "GPS lost · following the saved route"; "Syncing · Re-syncing position" → "GNSS locked" + "GNSS restored · validating the returned fix"; route card with "TUNNELS 1 · Saved for offline use"; the sensor rows (Accelerometer, Gyroscope, Magnetometer at 50 Hz, Live); GNSS HEALTH NORMAL "Receiver evidence is internally consistent"; AI speed estimator "TFLite FP32 model active · Loaded"; Navigation Hardware Check PASS; Car / Four-Wheeler Dynamics "Non-holonomic constraint (NHC) zero-lateral slip active"; Simulation Lab; Fault Injection Lab; Navigation engine "How it works".
- Copy that must appear verbatim (film typography, not app UI): "Guided by satellites." · "Until the signal disappears." · "GNSS lost." · "Navigation continues." · "Signal returns." · "Verified before it's trusted." · "GatiSaarth" · "Navigation beyond GNSS." · "Powered by the sensors already in your phone." · "One filter. Fifteen states." · "Error-state Kalman filter · predicts up to 100 Hz" · "Grounded in physics." · "Stops mean zero." / "No sideways slip." / "Held to the road." · "Offline maps. Offline routes." · "Recorded in airplane mode" · "It knows what to trust." · "On-device AI, advisory by design" · "Tested against every outage we could build." · "Navigation that keeps moving." · "Offline-first · On-device · Android"

## Creative Direction
- Tone preset: cinematic, held back with polished restraint
- Creative direction: Apple-style flagship product film; bright, precise, confident
- Interpretation: one continuous 3D world. A single hero phone (a CSS 3D slab with a 7-slice metal edge, black glass front and a moving glare) is driven by a camera rig (`#world`). The type is large, quiet Inter Display with masked word rises. Only the tunnel act is dark.
- Angle: see `brag-plan.md`. It is one real drive through the Mumbai Coastal Road tunnel, the dark act inside the tunnel, the light returning with the signal, then the technology, each beat shown through real UI lifted out of the phone.
- Hook: the phone rises into white space while five GNSS satellites (GPS, Galileo, GLONASS, BeiDou, NavIC) lock onto it one per beat.
- Outro / punchline: "Navigation that keeps moving." → app icon + GatiSaarth + "Navigation beyond GNSS."
- Avoid: fake UI, other navigation apps' UI, accuracy or drift numbers, a dark "cyberpunk" look, random particles, gradient text, paragraphs.

## Visual Identity
- Background: #F5F5F7 with a white key light (radial). The tunnel act uses graphite #0A0B0E with a #1C2029 radial and warm tunnel ceiling-light streaks.
- Text: #1D1D1F, secondary #86868B / #6E6E73; #F5F5F7 on dark
- Accent: #007AFF (#2997FF on dark); app status colours #FF3B30 / #34C759
- Display font: Inter 4 variable (the app's own file), optical size 32 (Inter Display), weight 600, -0.034em tracking. SF Pro is not licensed for non-Apple-platform work, so it is not used.
- Body/labels: Inter 500/600; JetBrains Mono (bundled) only for satellite IDs
- Visual references from the project: the app icon (`logo_mark.png`), the real screens, and the app's status colours

## Storyboard (summary; full contract in brag-plan.md)
1. Satellites — 0.0–4.8 — the phone rises, 5 satellites lock (beat grid 1.2–3.6), "Guided by satellites."
2. Into the tunnel — 4.8–7.2 — push into the screen, lines snap (5.4–6.6), the world dims, "Until the signal disappears."
3. Dead reckoning — 7.2–14.4 — dark theme DR, tunnel lights, "GNSS lost." / "Navigation continues.", lifted badges
4. Recovery — 14.4–19.2 — exit flash, real re-sync sequence, satellites reconnect, "Signal returns." / "Verified before it's trusted."
5. Brand — 19.2–24.0 — "GatiSaarth" / "Navigation beyond GNSS."
6. Sensors — 24.0–28.8 — gimbal rings, lifted sensor rows
7. Filter — 28.8–33.6 — 15-state grid → one dot → the phone (Live navigation)
8. Physics — 33.6–38.4 — ZUPT / NHC / map-lock chips + the real NHC card
9. Offline — 38.4–43.2 — plan a journey offline, TUNNELS 1 lifted
10. Trust — 43.2–48.0 — GNSS health, AI estimator, hardware check lifted
11. Tested — 48.0–52.8 — three phones: Simulation Lab / Fault Injection Lab / How it works
12. Outro — 52.8–60.0 — "Navigation that keeps moving." → lockup

## Audio
- Audio role: cinematic support; the score is original and written to picture
- Audio arc: air → descent → near-silence under "GNSS lost" → drop on "Navigation continues" (9.6 s) → lift at the exit (14.4 s) → bloom on the brand (19.2 s) → light groove (G–D–A–Bm) under the features → riser → final chord on the lockup (55.2 s)
- Music: `assets/audio/mix.wav`, synthesized in `brag/2026-09-27-132145/score/score.py` (numpy/scipy, 100 BPM, bar = 2.4 s). It is a pre-mixed stem of music plus sound design, so every SFX lands on its frame. The bundled "Happy Beats" tracks were not used because the user explicitly rejected generic corporate music.
- Music treatment: 0.35 s fade-in, peak normalised to -1 dBFS with soft saturation; the final chord rings out with a 0.7 s fade at the end. The spectral balance was checked per octave (warm and smooth; the sub and hiss were tamed after a first pass).
- Music cue guidance: the score *is* the cue grid. Strong cues: 7.2, 9.6, 14.4, 19.2 and 55.2 s. Every sequential reveal sits on the 0.6 s beat grid (text reveals hold at least 0.9 s).
- Audio-reactive treatment: subtle. The music RMS (extracted with the hyperframes-creative helper → `assets/audio/rms.js`) drives the white key light and the tunnel road glow through a `--rms` CSS variable. There are no visualizer graphics.
- Audio-coupled moments: satellite locks (chimes), snaps (descending ticks), tunnel whoomp, "GNSS lost" two-tone, light-pass whooshes per beat, exit swell, re-lock chimes, brand bloom, sensor-row ticks, state blips, converge riser, typing ticks, card ticks, tested whooshes, build riser, lockup chord.
- SFX: synthesized in the same palette (no Kenney casino or card sounds), mixed into `mix.wav`.
