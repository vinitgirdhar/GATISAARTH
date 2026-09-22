# Hyperframes Composition Brief: GatiSaarth

## Objective
Create a 30-second feature-tour brag video for GatiSaarth from the current UI.

## Output
- Composition directory: `brag-output-2026-09-22-231548/composition/`
- Rendered video: `brag-output-2026-09-22-231548/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 30.5 s (user-requested ~30 s)

## Source Material
- Project root: `C:\Users\vidhy\Downloads\gathisarthi`
- Primary sources: current release build 3.1.0 on the Pixel emulator (screenshots in `assets/shots/`), `frontend/lib/features/**` for verbatim strings, `frontend/lib/core/theme/app_theme.dart` for colours, `frontend/assets/icons/` for brand
- Product name: GatiSaarth
- Tagline: "Intelligent Navigation Beyond GNSS"
- Key UI moments: map tunnel test (Estimated road corridor, red DR puck on streets, ±7 → ±25 m), Sensor Status 8/8 Online, GNSS Integrity Lab, Outage mission banner, Trusted portal anchor result, Car/Walk/Two-wheeler selector
- Verbatim copy: "Estimated road corridor", "DEAD RECKONING", "GNSS restored · validating the returned fix", "Outage mission · 000°", "Speaks only on GNSS loss, unsafe ambiguity, and recovery", "SIH demo tunnel portal A accepted · EKF corrected", "Camera frames are processed on this phone and are not saved or uploaded.", "Automatic activity mode", "Delhi NCR · Maharashtra · 171 MB on this phone", "100% on-device pure Dart dead reckoning", "Few visible satellites are contributing to the fix"

## Creative Direction
- Tone preset: polished (app-store card structure)
- Creative direction: confident night-drive product tour
- Angle: see brag-plan.md
- Hook: "Tunnels. Underpasses. Urban canyons." → "Your GPS gives up."
- Outro: wordmark + tagline + "100% on-device pure Dart dead reckoning"
- Avoid: generic SaaS language, abstract filler, accuracy claims beyond the app's own simulated tunnel values, anything from earlier brag runs

## Visual Identity
- Background #05070B (app #000000, tinted); surfaces #1C1C1E/#2C2C2E; border #38383A
- Text #FFFFFF / #98989F; accent #0A84FF; green #34C759; red #FF3B30; amber #FF9500
- Font: Inter Variable (app asset) for everything
- Background layer: faint street-grid lines (map motif) + audio-reactive blue glow

## Storyboard
Scene list and timings are in brag-plan.md (8 scenes, 0-30.5 s).

## Audio
- Music: `assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3`, 0.34, fade out over the last 1.5 s
- Cues: preset JSON in the brag skill's `assets/music/cues/`. Locks at 9.29, 19.66 (portal accept) and 26.20 (extrapolated)
- Audio-reactive: `assets/audio-data.js` (RMS + bass per frame, 30 fps) drives the glow and the grid opacity
- SFX: chosen from `sfx-analysis.md`, low-HF picks, copied to `assets/sfx/`
