# Hyperframes Composition Brief: GatiSaarth

## Objective
Create a 20-second launch-style brag video for GatiSaarth centered on its tunnel-test navigation flow.

## Output
- Composition directory: `brag-output-2026-09-22-120939/composition/`
- Rendered video: `brag-output-2026-09-22-120939/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 20 seconds

## Source Material
- Project root: current repository
- Primary files read: `README.md`, `frontend/lib/core/theme/app_theme.dart`, navigation UI screens, `frontend/pubspec.yaml`
- Product name: GatiSaarth
- Tagline / strongest claim: Intelligent Navigation Beyond GNSS
- Key UI moment: tunnel test changes a verified solid-blue route into a dashed-red inertial route while the vehicle continues and the uncertainty ring expands
- Copy that must appear verbatim:
  - GPS disappears.
  - Dead Reckoning Active
  - Navigation beyond satellites.
  - 100% on-device · zero cloud reliance.

## Creative Direction
- Tone preset: cinematic
- Creative direction: premium night-drive launch film with scientific restraint
- Interpretation: spacious dark frames, bold but readable typography, product-first motion, and measured benchmark labels
- Angle: Satellites disappear in a tunnel; the navigation experience continues visibly and honestly.
- Hook: “GPS disappears. You don’t.” over a route entering darkness.
- Outro: “Navigation beyond satellites.”
- Avoid: generic SaaS language, military HUD clichés, unsupported field-performance claims, abstract filler, or unrelated visual redesign.

## Visual Identity
- Background: #000000
- Text: #FFFFFF
- Accent: #0A84FF
- Secondary state accents: #34C759 GNSS, #FF3B30 dead reckoning, #AF52DE reacquiring
- Display and body font: local Inter Variable project asset as the app's `.SF Pro Text` implementation
- Visual references: iOS-style status capsule, 20px cards, map puck, accuracy ring, solid/dashed trail states

## Storyboard
Use `../brag-plan.md` as the creative contract.

1. The outage — 3s — route loses GPS and continues in red.
2. Tunnel test — 5.75s — real dark-mode navigation UI demonstrates the state change.
3. Measured, not magical — 4.25s — benchmark rows reveal and hold.
4. Private by design — 4.5s — on-device sensor-to-filter flow.
5. Brand landing — 2.5s — logo and final claim.

## Audio
- Audio role: cinematic support
- Audio arc: low bed, dry switch cue, restrained metric ticks, final logo accent and fade
- Music: `happy-beats-business-moves-vol-12-by-ende-dot-app.mp3`, volume 0.30
- Music cue guidance: bundled cue preset; major reveals near 8.74s and 17.47s; metrics at 9.29s, 9.83s, 10.37s
- Audio-reactive treatment: subtle glow/halo breathing only
- SFX: use low-risk interface/card sounds matched to the tunnel switch, metric arrivals, and logo; sparse and quiet
- SFX analysis guidance: `.agents/skills/brag/assets/sfx/sfx-analysis.md`
- Audio files: copy local music and selected SFX into the composition assets tree

## Hyperframes Instructions
- Use one standalone 1920x1080, 20s composition and one paused GSAP timeline registered as `main`.
- Show the working product flow, not only marketing claims.
- Keep all required text settled long enough to read.
- Use local font, logo, music, and SFX assets.
- Mark the 8.74s and 17.47s major locks and 9.29/9.83/10.37 metric beat grid in code comments.
- Keep all motion seek-safe and deterministic.
- Run `npx hyperframes check` as the single pre-render gate.
