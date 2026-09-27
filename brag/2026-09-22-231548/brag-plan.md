# Brag Plan: GatiSaarth (v3.1.0, current UI)

## What is this app?
GatiSaarth is an Android navigator that keeps a vehicle on the map when GNSS drops, using only the phone's own sensors, offline vector maps and a 15-state error-state EKF, all on the device.

## The angle
A 30-second feature tour of the app **as it looks today**, built from screenshots of the current release build on the Pixel emulator (captured 2026-09-22 from `app-release.apk` 3.1.0). Nothing is recycled from earlier brag videos. The spine is the app's own tunnel test: GNSS goes dark → the marker stays on real streets ("Estimated road corridor") while the error margin grows honestly → the voice speaks up → a trusted portal marker corrects the filter → GNSS returns and is validated before it's trusted. The tour then covers the vehicle modes, offline maps and privacy.

Honesty rules: every UI string is verbatim from the app. The only numbers are the app's own on-screen values from the simulated tunnel test (±7 m → ±25 m), labelled "Tunnel test · simulated outage". No field-accuracy or drift-reduction claims. The portal pack is the demo pack, and its label stays verbatim ("SIH demo tunnel portal A").

## Hook (first 2-3 seconds)
Near-black frame with faint street lines. Three places stack in, one per beat: **Tunnels. Underpasses. Urban canyons.** Then the line lands in red: **"Your GPS gives up."**

## Key moments (the middle)
- Real Home screen: "GatiSaarth / Intelligent Navigation Beyond GNSS", Synced capsule, 97 % Confidence ring.
- Real Sensor Status list, "8/8 Online": accelerometer, gyroscope, magnetometer, barometer, mount alignment, fused by one filter.
- Real map frames from the tunnel test: the red dead-reckoning puck follows the drawn streets, header "Estimated road corridor · DEAD RECKONING", accuracy ±7 → ±13 → ±19 → ±25 m, then "GNSS restored · validating the returned fix".
- Safe outage voice ("Outage mission · 000°" banner) plus the GNSS Integrity Lab sky plot ("Few visible satellites are contributing to the fix").
- Trusted Portal Scanner: marker in the viewfinder, then a green "SIH demo tunnel portal A accepted · EKF corrected".
- Vehicle Configuration: Car → Walk → Two-wheeler, "Automatic activity mode", Offline Maps "Delhi NCR · Maharashtra · 171 MB on this phone".

## Outro / punchline
Wordmark (dark variant) + "Intelligent Navigation Beyond GNSS" + the app's own privacy line: "100% on-device pure Dart dead reckoning". Bell on the downbeat.

## User flow worth showing
1. Entry: Home. Synced, GNSS locked, Confidence 97 %.
2. Key action: Map → Tunnel test → dead reckoning on the road corridor, margin grows, outage voice banner.
3. Result: portal marker scan corrects the EKF → Reset GNSS → "GNSS restored · validating the returned fix" → "GNSS locked".

## Tone
- Preset: polished (with app-store feature-card structure)
- Creative direction: confident night-drive product tour, precise and a little proud
- Interpretation: Dark, spacious frames, big Inter headlines on the left, the real phone on the right. One feature per scene with smooth slides and wipes. Energy comes from motion and the beat, not from shouting.

## Format: landscape — 1920x1080
## Duration: 30.5 seconds (user asked for about 30 s covering every feature)

## Visual identity (from the project)
- Background: #000000 in the app (`AppColors.darkBackground`); video uses #05070B, blue-tinted per house style
- Surface: #1C1C1E / #2C2C2E, border #38383A
- Accent: #0A84FF (`AppColors.cyan`); status: #34C759 locked, #FF3B30 dead reckoning, #FF9500 degraded, #AF52DE reacquiring
- Text: #FFFFFF / #98989F
- Display + body font: Inter Variable (the app's own `assets/fonts/Inter-Variable.ttf`)
- Strongest visual element: the red dead-reckoning puck riding the vector streets with the growing accuracy value

## Share copy (draft)
GPS dies in tunnels. GatiSaarth doesn't: phone sensors, offline maps and a 15-state EKF keep you on the road, and it's 100 % on-device.

## Audio direction
- Role: warm, steady bed with motion-matched accents
- Music: happy-beats-business-moves-vol-12 (steady, clean, 109.96 BPM)
- Music treatment: starts at 0, volume ~0.34, fades out over the last 1.5 s. A bell rings over the fade at the wordmark
- Music cue guidance: preset `assets/music/cues/happy-beats-business-moves-vol-12-by-ende-dot-app.music-cues.json`. Strong cues to lock: 9.29 s (road-DR scene), 19.66 s (portal accepted) and 26.20 s (wordmark; extrapolated on the 8-beat grid 8.74 → 13.11 → 17.47 → 21.84 → 26.20). Beat grid 0.5457 s
- Audio-reactive treatment: subtle; music RMS/bass breathes the blue ambient glow behind the phone and the street-line layer. No visualizer graphics
- SFX posture: moderate, low-HF picks, at 0.55-0.8
- Audio-coupled moments: hook words stack (soft drops), hook line (soft impact), screenshot changes (card slide), tunnel tap (click), portal accept (glass/bell), mode switches (switch), wordmark (bell)
- Restraint rule: no SFX on every counter tick, no alarm-like sounds for the outage

## Storyboard

### Scene 1 — Hook — 0.00-3.27 s
"Tunnels." "Underpasses." "Urban canyons." stack on the left, one per beat, and hold. "Your GPS gives up." lands below in red and holds ≥1.2 s.
Sequential/interaction: yes, 3 labels on every other beat (≈1.09 s apart), all held
Audio intent: quiet tension, soft drops per word, soft thud on the red line
Transition mood: clean wipe → Scene 2

### Scene 2 — Reveal — 3.27-6.56 s
Logo tile + dark wordmark + "Intelligent Navigation Beyond GNSS" on the left; the phone rises on the right showing the real Home screen (Synced · Nominal GNSS lock · 97 % Confidence). Line: "Your phone keeps navigating."
Audio intent: warm lift, bong on the wordmark
Transition mood: slide → Scene 3

### Scene 3 — Sensor fusion — 6.56-9.29 s
Phone shows the real Sensor Status list (8/8 Online). Headline: "Eight sensors. One filter." Sub: "15-state error-state EKF, running on the phone."
Audio intent: card slide as the list arrives
Transition mood: slide → Scene 4

### Scene 4 — Road-locked dead reckoning — 9.29-14.73 s
Eyebrow "Tunnel test". Headline: "Loses GPS. Keeps the road." The phone cycles the real map frames (tun2 → tun7 → tun14 → tun24 → rst1). A big margin counter follows the app's own values, ±7 → ±25 m, captioned "Error margin, shown honestly". Fine print: "Tunnel test · simulated outage".
Sequential/interaction: tap on "Tunnel test" at the scene start, then 4 map states
Audio intent: tap click, card slides on the frame changes
Transition mood: wipe → Scene 5

### Scene 5 — Voice + integrity — 14.73-18.02 s
Two feature cards: the voice banner "Outage mission · 000°" with "Safe outage voice / Speaks only on GNSS loss, unsafe ambiguity, and recovery", and a crop of the real GNSS Integrity Lab sky plot. Headline: "Speaks when it matters. Checks every fix."
Sequential/interaction: two cards, ~0.55 s apart, held
Audio intent: two drops
Transition mood: slide → Scene 6

### Scene 6 — Trusted portal anchor — 18.02-22.37 s
A phone recreating the Trusted portal anchor screen: privacy line, viewfinder with a marker, scan line sweeps, green result "SIH demo tunnel portal A accepted · EKF corrected". Headline: "Scan the tunnel portal." Sub: "A trusted anchor corrects the filter. Frames never leave the phone."
Sequential/interaction: scan sweep, then accept
Audio intent: click at scan, glass + soft bell on accept
Transition mood: wipe → Scene 7

### Scene 7 — Modes + offline — 22.37-26.20 s
Big recreation of the Vehicle Configuration segmented control: highlight moves Car → Walk → Two-wheeler with the matching dynamics line. Chips: "Automatic activity mode" and "Offline Maps · Delhi NCR · Maharashtra · 171 MB on this phone". Headline: "Car, bike or on foot. Signal or not."
Sequential/interaction: 2 switches ~1 s apart
Audio intent: switch clicks
Transition mood: soft crossfade → Scene 8

### Scene 8 — Outro — 26.20-30.50 s
Centered logo tile, wordmark, tagline, then "100% on-device pure Dart dead reckoning". Long hold.
Audio intent: bell on the wordmark, music fades
Transition mood: end hold

**Music mood for this video:** steady, clean, confident
**Audio summary:** a warm steady bed; soft drops and thuds set up the problem, card slides and clicks narrate the real UI, a glass/bell accent marks the portal correction, and a bell rings over the fade on the wordmark.

## Revision 2 (2026-09-23): 41.4 s cut
- iPhone 15 Pro-style device frame (titanium rim, Dynamic Island, iOS status bar, home indicator).
- New Scene 4b, Urban canyon (14.73-20.2 s): tap "Urban canyon" → "GNSS degraded", ±75 m halo, marker holds the street at 30 km/h; Home card "Urban canyon · weak GNSS / Fusing IMU + NavIC", Confidence 50 %. Labelled "Urban canyon test · simulated weak, multipath GNSS".
- New Scene 4c, Edge AI & Telemetry (20.2-25.6 s): real Home Edge AI section; 1 ms latency, 98 % AI conf, IMU temperature · bias 25.0 °C, road vibration, road anomalies; shows the app's own advisory line. The Sensors tab's "TFLite Int8 model active" string is deliberately not quoted (the shipped speed model is float32).
- Later scenes shifted +10.87 s.
- Music: the stock bed is replaced by an original score (`score/make_score.py`, deterministic numpy synthesis, D minor, 120 BPM) that follows the edit: muffled during the tunnel, opens on GNSS restore, stutters in the urban canyon, brightens for Edge AI, and ends on a big chord on the outro.
