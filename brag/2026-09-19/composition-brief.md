# Hyperframes Composition Brief: GatiSaarth

## Objective
Create a short launch-style brag video for GatiSaarth ("Intelligent Navigation Beyond GNSS"), a Flutter dead-reckoning prototype.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 21.7 seconds

## Source Material
- Project root: `GATISAARTHI` (Flutter app in `frontend/`)
- Primary files read: `frontend/lib/core/theme/app_theme.dart`, `frontend/lib/core/constants/dr_constants.dart`, `dashboard_screen.dart`, `active_nav_screen.dart`, `dashboard_header.dart`, `fusion_mode_badge.dart`, `fusion_confidence_badge.dart`, `session_status_card.dart`, `session_controls.dart`, `navigation_map.dart`, `confidence_halo.dart`, `telemetry_card.dart`, `uncertainty_model.dart`, `frontend/pubspec.yaml`, `README.md`, `CLAUDE.md`, real device screenshots in the parent folder.
- Product name: GatiSaarth
- Tagline / strongest claim: "Intelligent Navigation Beyond GNSS" (verbatim, `AppConstants.appSubTitle`); brag = it tells you how lost it is (modelled drift margin).
- Key UI or visual moment to recreate: the dashboard header (title + confidence ring), the fusion-mode pill, the status card, the offline map with the confidence halo, and the Scenarios card (Tunnel test / Urban canyon / Reset GNSS / Diagnostics).
- Copy that must appear verbatim (all from the Flutter source):
  - "GatiSaarth", "Intelligent Navigation Beyond GNSS"
  - Pills: "GNSS locked", "Dead reckoning · inertial", "Reacquiring GNSS signal"
  - "Scenarios", "Simulate GNSS loss to see dead reckoning take over", "Tunnel test", "Urban canyon", "Reset GNSS", "Diagnostics"
  - Snackbar: "Simulating a GNSS blackout — pure INS dead reckoning"
  - "Modelled drift margin", "Confidence", "Inertial sensors keep tracking."
  - Footer: "Not the final product — new features are still being added."
- Honesty constraints (owner's standing rule): every number is derived from the app's real `UncertaintyModel` (margin = 3 m + 0.05 × distance + 0.15 × seconds; confidence = 1 − margin/150 clamped 0.30–0.99; green ≥ 0.90, amber ≥ 0.70, else red). At 40 km/h (11.11 m/s): T+60 s → 666.7 m travelled, ±45 m, 70%. Show it as "modelled, not measured". No README benchmark figures (6.46 m, 4.39 ms, 15-state UKF). Do not claim AI drift reduction. Tunnel status subtitle omits the app's "AI dead reckoning · " prefix.

## Creative Direction
- Tone preset: app-store
- Creative direction: quiet Apple-keynote film for a phone that refuses to lie about being lost
- Interpretation: clean slides and dims, sentence-case Inter, one idea per scene, restraint. Humor only from the two-line hook and "how lost it is".
- Angle: Every navigation app is confident right up until the tunnel. GatiSaarth keeps tracking on the phone's own sensors and shows an honest, growing error margin. The video runs the tunnel scenario and lets the modelled margin climb while the confidence ring drains, then recovers.
- Hook: "Your GPS just died." + real pill flips green → red, then (beat-locked at 1.60 s) "Your phone didn't."
- Outro / punchline: logo mark + GatiSaarth wordmark + "Intelligent Navigation Beyond GNSS" + the app's own italic "Not the final product — new features are still being added."
- Avoid:
  - Generic SaaS language
  - Abstract filler visuals (no waveforms, particles, gradients-for-their-own-sake)
  - Inflated accuracy claims or README benchmark numbers
  - Unrelated visual redesign of the app UI

## Visual Identity
- Background: #F2F2F7 (light acts); #000000 (dark tunnel act, the app's own dark background)
- Text: #1C1C1E on light, #FFFFFF on dark; secondary #8E8E93 (darkened only where `check` contrast requires)
- Accent: #007AFF systemBlue; status #34C759 / #FF9500 / #FF3B30 / #AF52DE
- Display font: Inter (bundled `assets/fonts/Inter-Variable.ttf`, the app's own font)
- Body font: Inter
- Visual references from the project: iOS white cards with layered soft shadows (radius 20), pill status chips with a dot, circular confidence ring with % + margin, iOS segmented/round buttons, the bundled offline OSM tiles (Vikaspuri, Delhi, Road 236) with the swelling confidence halo and blue navigation puck, `logo_mark.png` and `wordmark.png`

## Storyboard
Use the storyboard in `brag-output/brag-plan.md` as the creative contract.

Scene summary:
1. Hook — 3.70s — "Your GPS just died." / "Your phone didn't." + pill flip
2. Reveal — 3.68s — phone rises with the real dashboard; logo, wordmark, tagline; ring fills to 98% ±3 m
3. The tunnel — 3.68s — dim to dark; scroll to Scenarios; cursor taps Tunnel test on 8.96 s; snackbar; "Enter a tunnel." / "Inertial sensors keep tracking."
4. Modelled drift — 4.75s — "It tells you how lost it is." + 60 s time-lapse T+0→T+60, ±3→±45 m, 98%→70%, ring green → amber → red, puck on Road 236
5. Recovery — 2.10s — light returns; touch taps Reset GNSS; big pill echo purple "Reacquiring GNSS signal" → green "GNSS locked" + "GNSS comes back."; ring back to 98% ±3 m
6. Outro — 3.79s — logo + wordmark + tagline + honest footer, bell on 17.91 s

## Audio
- Audio role: warm bed with sparse professional accents
- Audio arc: warm bed fades in under a quiet hook, ducks slightly in the tunnel act, swells back on recovery, fades out under the last line
- Music: `happy-beats-business-moves-vol-11-by-ende-dot-app.mp3`
- Music treatment: volume ~0.35, fade-in 0–0.8 s, duck to ~0.26 from 9.0 s to 15.8 s, back to 0.35 on recovery, fade out 20.3–21.7 s
- Music cue guidance: bundled preset `assets/music/cues/happy-beats-business-moves-vol-11-by-ende-dot-app.music-cues.json` (114.84 BPM, beats ≈ every 0.52 s from 1.60 s). Strong-cue locks: 1.60 s, 8.96 s, 17.91 s. Beat-grid: 12.12 s (amber), 14.76 s (red), 15.81 s (Reset tap), 16.86 s ("GNSS locked").
- Audio-reactive treatment: subtle; pre-extracted RMS/bass (`extract-audio-data.py`, 30 fps) breathes the glow behind the phone and the map halo by a few percent. No waveform or equalizer visuals.
- Audio-coupled moments:
  - Hook — pill flip (soft click), line 2 pop (1.60 s)
  - Scene 2 — phone slide (card slide), tagline soft bong (4.75 s), ring draws in 4.55–5.45 s
  - Scene 3 — simulated touch tap (click, 8.96 s) + soft thud as the app flips to dead reckoning
  - Scene 4 — quiet accent at amber (12.12 s), heavier soft thud at red (14.76 s)
  - Scene 5 — tap click (15.81 s), glass chime at "GNSS locked" (16.86 s)
  - Scene 6 — bell on the logo slam (17.91 s)
- SFX selection guidance: sparse, low high-frequency-risk files, 0.45–0.8 volume; card/UI sounds match the visible gesture.
- SFX analysis guidance: `~/.claude/skills/brag/assets/sfx/sfx-analysis.md` (plugin copy) — chosen files: `impactSoft_medium_001/003`, `impactSoft_heavy_003`, `impactBell_heavy_000`, `impactGlass_light_001`, `bong_001`, `card-slide-1`, `ui/click2`, `ui/rollover2`.
- Exact SFX choice: Hyperframes composition decides timestamps and volume from the implemented animation.
- Audio files: copied into `brag-output/composition/assets/`

## Hyperframes Instructions
Domain skills used (read from the official `heygen-com/hyperframes` repo, not installed globally): `hyperframes-core`, `hyperframes-animation` (GSAP adapter), `hyperframes-creative` (audio-reactive), `hyperframes-cli`. /brag is its own workflow; the `hyperframes` intent interview and generic promo route were not used.

Requirements:
- Show real UI, copy and visuals from the source project (done: recreated dashboard UI with verbatim strings, bundled OSM tiles, real logo assets).
- Keep all text readable; honour the reading-time floors in the plan.
- Keep the video 15–25 s (21.7 s).
- Include the planned music/SFX layer.
- Cue metadata is a hint; readability and story win.
- Local assets only (gsap, Inter, logos, tiles, audio); no CDN.
- Run `npx hyperframes check` before render.
