# Hyperframes Composition Brief: GatiSaarth

## Objective

Create a 20-second flagship launch-style brag video for GatiSaarth, a privacy-first on-device navigation app that continues positioning a vehicle when GNSS is unavailable.

## Output

- Composition directory: `brag-output-2026-09-22-113212/composition/`
- Rendered video: `brag-output-2026-09-22-113212/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 20 seconds

## Source Material

- Project root: `C:/Users/vidhy/Downloads/gathisarthi`
- Primary files read: `README.md`, `frontend/lib/core/theme/app_theme.dart`, navigation/benchmark Flutter screens, and project assets.
- Product name: GatiSaarth
- Tagline / strongest claim: Intelligent Navigation Beyond GNSS.
- Key UI or visual moment to recreate: the iOS-like navigation map changing from a solid blue GNSS route to a dashed red dead-reckoning route, with a vehicle puck and honest expanding uncertainty ring.
- Copy that must appear verbatim:
  - `Dead Reckoning Active · GNSS Outage`
  - `INTELLIGENT NAVIGATION BEYOND GNSS`

## Creative Direction

- Tone preset: cinematic
- Creative direction: Flagship launch video for appl
- Interpretation: restrained trailer-scale confidence, dark map-based visuals, large declarative type, slow deliberate reveals; no metric dump or generic AI claims.
- Angle: At the instant ordinary maps lose their way, GatiSaarth keeps the journey moving on the road using the phone itself.
- Hook: a route enters a tunnel; satellite indicators disappear but the map does not freeze. Text: `WHEN GNSS GOES DARK.`
- Outro / punchline: GatiSaarth, `INTELLIGENT NAVIGATION BEYOND GNSS.`
- Avoid: generic SaaS language, abstract filler, unrelated UI redesign, alarmist outage effects, and unsupported accuracy claims.

## Visual Identity

- Background: `#000000`
- Text: `#FFFFFF`
- Accent: `#0A84FF` GNSS / `#FF3B30` dead reckoning / `#34C759` reacquired
- Display font: SF Pro Text with Inter fallback
- Body font: SF Pro Text with Inter fallback
- Visual references: app's dark mode, iOS-style rounded controls, map route, uncertainty ring, blue/red/green state palette, GatiSaarth wordmark under `frontend/assets/icons/`.

## Storyboard

Use `brag-plan.md` as the creative contract.

1. Signal — 3s — dark map, blue route and vehicle puck; satellite indicators die one by one; `WHEN GNSS GOES DARK.`
2. Outage — 5s — tunnel mask, live route continues and changes blue solid to red dashed; show `Dead Reckoning Active · GNSS Outage`.
3. Honest navigation — 5s — curved red road-following trajectory and expanding uncertainty ring; `STILL ON THE ROAD.` then `On-device inertial navigation.`
4. Return — 4s — green GNSS returns; route reconciles smoothly, no teleport; `NO FREEZE. NO TELEPORT.`
5. GatiSaarth — 3s — wordmark, tagline, settled blue route line.

## Audio

- Audio role: cinematic support.
- Audio arc: sparse at lock, controlled tension during the outage, then a calm resolved swell at reacquisition and logo.
- Music: `happy-beats-business-moves-vol-12-by-ende-dot-app.mp3`, copied into `composition/assets/music/`.
- Music treatment: 0.30–0.35 volume, soft fade-in at 0s and tail-out under final logo.
- Music cue guidance: bundled cue preset at `.agents/skills/brag/assets/music/cues/happy-beats-business-moves-vol-12-by-ende-dot-app.music-cues.json`; use 1–3 strong cues only if they preserve readability.
- Audio-reactive treatment: subtle; let the existing map glow and uncertainty ring breathe from music energy. No waveform/equalizer imagery.
- Audio-coupled moments:
  - satellite status fade — quiet signal cut
  - outage activation — two restrained pulses
  - dashed route draw — soft state-change accent
  - GNSS return and wordmark — quiet lock chime and logo hit
- SFX selection guidance: select 2–3 low/high-frequency-safe cinematic cues after animation exists; restraint over density.
- SFX analysis guidance: `.agents/skills/brag/assets/sfx/sfx-analysis.md`.
- Exact SFX choice: choose files, timestamps, density, and volume to match the final motion.

## Hyperframes Instructions

Build with native Hyperframes conventions. Show the planned real app-inspired navigation UI and preserve text reading holds. Keep duration 15–25 seconds, render at 1920x1080, include the prepared music and restrained SFX, use local assets only, and run `npx hyperframes check` with zero errors before render. Major reveals may use nearby music cues, but story and readability take priority.
