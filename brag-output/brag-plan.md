# Brag Plan: GatiSaarth

## What is this app?
GatiSaarth ("Intelligent Navigation Beyond GNSS") is a Flutter Android prototype that keeps a phone's position estimate alive when GNSS drops, using only the phone's own sensors, and shows the driver an honest, growing error margin instead of a fake-confident dot.

## The angle
Every navigation app is confident right up until the tunnel, then the blue dot freezes or lies. GatiSaarth's brag is the opposite: **it tells you how lost it is.** The video runs the app's own tunnel scenario and lets the *modelled* drift margin climb (±3 m → ±45 m over a 60 s blackout at 40 km/h) while the confidence ring drains green → amber → red, then recovers when GNSS returns. No inflated accuracy claim anywhere: the honesty is the flex. The closer borrows the app's own footer, "Not the final product — new features are still being added."

Honesty rules for this video (project owner's standing rule: no fabricated UI data, never claim AI drift reduction):
- Every number on screen is computed with the app's real `UncertaintyModel` (margin = 3 m + 0.05 × distance + 0.15 × seconds; confidence = 1 − margin/150, clamped 0.30–0.99). Labelled "Modelled drift margin", exactly as the app labels it.
- No 6.46 m / 4.39 ms / 15-state UKF / "AI reduces drift" claims. The README figures are not wired into the shipped app.
- UI strings are verbatim from the Flutter source, except the tunnel status subtitle drops the app's "AI dead reckoning · " prefix.

## Hook (first 2-3 seconds)
Light iOS-grey frame. Line 1 lands: **"Your GPS just died."** while the app's own status pill flips from green "GNSS locked" to red "Dead reckoning · inertial". On the strong beat at 1.60 s, line 2 slams in in iOS blue: **"Your phone didn't."**

## Key moments (the middle)
- The reveal: the phone rises with the real dashboard header, **GatiSaarth**, the verbatim tagline **"Intelligent Navigation Beyond GNSS"**, and the confidence ring filling to 98% at ±3 m, green "GNSS locked".
- The tap: the backdrop dims to the theme's own dark (#000000). A cursor taps **Tunnel test** in the Scenarios card, the red snackbar reads "Simulating a GNSS blackout — pure INS dead reckoning", "Inertial sensors keep tracking."
- The payoff: a 60-second blackout time-lapse in ~3.8 s. The puck keeps driving along Road 236 on the app's own bundled offline OSM tiles, the halo swells, the clock reads T+0s → T+60s, the margin counter climbs ±3 m → ±45 m, and the ring drains 98% → 70%, going amber at T+17 s and red at the very end. Headline: **"It tells you how lost it is."**
- Recovery: tap **Reset GNSS**, pill goes purple "Reacquiring GNSS signal", then green "GNSS locked", ring snaps back to 98% ±3 m, backdrop returns to light.

## Outro / punchline
Logo mark + **GatiSaarth** wordmark from the app's own assets, tagline **"Intelligent Navigation Beyond GNSS"**, and the app's own italic footer, small: *"Not the final product — new features are still being added."* Bell hit on the strong beat at 17.91 s, music fades under the last line.

## User flow worth showing
1. **Entry:** Dashboard, GNSS locked, confidence ring 98%, ±3 m.
2. **Key action:** Scenarios → tap "Tunnel test" → GNSS blackout, pill turns red "Dead reckoning · inertial".
3. **Result:** Position keeps moving on the offline map, modelled margin grows, ring drains; "Reset GNSS" → "Reacquiring GNSS signal" → "GNSS locked".

## Tone
- Preset: app-store
- Creative direction: quiet Apple-keynote film for a phone that refuses to lie about being lost
- Interpretation: Clean slides and wipes, feature-card feel, sentence-case Inter, generous space, one idea per scene. Humor comes only from the two-line hook and "how lost it is"; everything else is restraint and honest numbers.

## Format: landscape — 1920x1080
## Duration: 21.7 seconds (scene 6 lengthened so the honest footer can be read)

## Visual identity (from the project)
- Background: #F2F2F7 (light, iOS systemGroupedBackground); #000000 (app's dark background) during the tunnel act
- Accent: #007AFF / #0A84FF (systemBlue); status colors #34C759 green, #FF9500 amber, #FF3B30 red, #AF52DE purple (reacquiring)
- Text: #1C1C1E primary, #8E8E93 secondary, #FFFFFF on dark
- Display font: Inter (the app's bundled `Inter-Variable.ttf`, mapped to ".SF Pro Text")
- Body font: Inter
- Strongest visual element: the confidence ring + fusion-mode pill flipping colour on white iOS cards with layered shadows; the app's own bundled offline OSM tiles (Vikaspuri, Delhi, Road 236) with the swelling confidence halo; the blue/orange GatiSaarth logo art

## Share copy (draft)
GPS drops in the tunnel? GatiSaarth keeps tracking on the phone's own sensors and shows how wrong it might be: ±45 m after 60 s at 40 km/h (modelled). Built for real-world navigation.

## Audio direction
- Role: warm bed with sparse professional accents
- Music: `happy-beats-business-moves-vol-11-by-ende-dot-app.mp3` (warm, business-y, 114.8 BPM), volume ~0.35
- Music treatment: starts at 0.0 s with a 0.8 s fade-in; ducks slightly (~0.28) during the tunnel act; fades out 20.3 → 21.7 s under the final line
- Music cue guidance: bundled preset read (`vol-11` cues, 114.84 BPM, beats every ~0.52 s from 1.60 s). Strong cues to lock: **1.60 s** (line 2 slam), **8.96 s** (tap on Tunnel test), **17.91 s** (end-card slam). Beat-grid windows: amber flip near 12.12 s, red flip at 14.76 s (T+60 s), "Reacquiring" at 15.81 s, "GNSS locked" at 16.86 s. Readable text is never revealed faster than every other beat.
- Audio-reactive treatment: subtle; music RMS/bass gently breathes the glow behind the phone (red in the tunnel act, green after recovery) and the map halo. No waveform or equalizer visuals.
- SFX posture: sparse, motion-matched; app-store consistent light layer at 0.65-0.75 volume
- Audio-coupled moments: pill flip, phone slide-up, simulated tap on Tunnel test, ring threshold changes, Reset GNSS tap, logo slam
- Restraint rule: no aggressive impacts, no sound on every text line, nothing that fights the music; the tunnel act stays quiet and tense.

## Storyboard

### Scene 1 — Hook — 3.70s (0.00 → 3.70)
Light #F2F2F7 frame. The real "GNSS locked" pill (green) is visible at 0.15 s and flips to red "Dead reckoning · inertial" at ~0.9 s. "Your GPS just died." (4 words) enters 0.3-0.8 s and holds until the cut. "Your phone didn't." enters at 1.60 s in blue and holds to the cut (≥1.5 s).
Sequential/interaction: yes — line 1, then pill flip, then line 2 (each holds its own reading floor).
Audio intent: dry, quiet setup, one soft accent on the slam.
Audio-coupled idea: pill flip = soft switch sound; line 2 = beat-locked pop at 1.60 s.
Music: warm bed fades in.
Transition mood: clean slide → Scene 2 (locked to the 3.70 s strong beat)

### Scene 2 — Reveal — 3.68s (3.70 → 7.38)
The phone slides up from below to the right half, showing the dashboard: "GatiSaarth", "Intelligent Navigation Beyond GNSS", confidence ring, "GNSS locked" green pill, "Nominal GNSS lock" card, offline map. Left: logo mark + "GatiSaarth" wordmark, then the tagline (5 words, ≥1.5 s hold). The ring draws in 0 → 98% with "±3 m" under it (4.55 → 5.45 s); the tagline lands on the 4.75 s beat.
Sequential/interaction: yes — logo, tagline, then ring fill.
Audio intent: confident, bright, product-forward.
Audio-coupled idea: phone slide = card slide; tagline = soft bong on the 4.75 s beat.
Music: bed continues.
Transition mood: soft dim → Scene 3

### Scene 3 — The tunnel — 3.68s (7.38 → 11.06)
Backdrop dims from #F2F2F7 to #000000 by ~8.0 s. Inside the phone the page scrolls to the Scenarios card (Tunnel test / Urban canyon / Reset GNSS / Diagnostics, real labels and icons). Left (white on dark): "Enter a tunnel." at ~7.7 s. A cursor moves to Tunnel test and taps on the 8.96 s strong beat: the button presses, the red snackbar "Simulating a GNSS blackout — pure INS dead reckoning" rises, the pill flips red. "Inertial sensors keep tracking." (4 words, ≥1.4 s hold) enters ~9.3 s. At ~10.3 s the phone scrolls back up to the header/map.
Sequential/interaction: yes — simulated cursor move + tap (beat-locked at 8.96 s), then snackbar, then subline.
Audio intent: the room goes quiet; a small, deliberate tap.
Audio-coupled idea: cursor click at 8.96 s, a soft low thud as the pill turns red; music ducks a touch.
Music: same bed, slightly ducked.
Transition mood: hold → Scene 4

### Scene 4 — Modelled drift — 4.75s (11.06 → 15.81)
Dark backdrop with a faint red glow behind the phone. Headline "It tells you how lost it is." (7 words, ≥2.1 s hold) enters at 11.06 s. Time-lapse 11.3 → 14.76 s: clock T+0s → T+60s, puck drives along Road 236 on the bundled tiles, halo swells, margin counter ±3 m → ±45 m, ring 98% → 70% (amber at T+17 s ≈ 12.1 s on the beat grid, red at T+60 s = 14.76 s). Under the counter: "Modelled drift margin" and small print "40 km/h · 60 s outage · modelled, not measured". Final numbers hold ≥1.0 s.
Sequential/interaction: yes — counter ticks, threshold colour changes on beats (amber ≈ 12.12 s, red = 14.76 s); text is not on the beat grid, the numbers are.
Audio intent: tension building, restrained.
Audio-coupled idea: quiet drop on amber, slightly weightier soft impact on red.
Music: bed continues, low.
Transition mood: hard cut → Scene 5

### Scene 5 — Recovery — 2.10s (15.81 → 17.91)
Left column shows a big echo of the app pill (purple "Reacquiring GNSS signal" → green "GNSS locked" on the 16.86 s beat) and the line "GNSS comes back." so the state change is legible while the phone is scrolled to the Scenarios card.
Backdrop returns to light. Cursor taps "Reset GNSS" at 15.81 s. Pill turns purple "Reacquiring GNSS signal" then green "GNSS locked" at 16.86 s; ring snaps back to 98%, margin ±3 m, halo tightens. Phone eases left/back to make room.
Sequential/interaction: yes — tap, purple pill, green pill (beats 15.81 / 16.86).
Audio intent: relief.
Audio-coupled idea: click on tap, glassy chime when "GNSS locked" lands.
Music: bed swells back to full.
Transition mood: clean slide → Scene 6

### Scene 6 — Outro — 3.79s (17.91 → 21.70)
Logo mark and "GatiSaarth" wordmark from the app's own assets slam in on the 17.91 s strong beat, then "Intelligent Navigation Beyond GNSS", then the small italic "Not the final product — new features are still being added." Hold ≥2.5 s on the full card. Music fades out.
Sequential/interaction: none
Audio intent: warm payoff.
Audio-coupled idea: single soft bell on the slam; music fades under the footer.
Music: fade 20.3 → 21.7 s.
Transition mood: fade to end.

**Music mood for this video:** warm, upbeat, restrained (app-store)
**Audio summary:** Warm bed under a quiet hook, a small deliberate tap into a hushed tunnel act, a glassy recovery chime, and one soft bell on the logo.
