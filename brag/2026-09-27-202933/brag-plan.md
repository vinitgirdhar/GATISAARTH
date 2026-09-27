# Brag Plan: GatiSaarth: 10-second sneak peek

## What is this app?
An offline-first Android navigator that keeps guiding the vehicle when GNSS disappears. It uses the phone's own sensors, a 15-state error-state Kalman filter and offline maps, all on the device.

## The angle
A teaser for the launch film (`brag/2026-09-27-132145`) in the same visual language: a white studio world, Inter Display type, satellites as hairlines, a graphite tunnel act with warm ceiling-light streaks, and a light burst on the exit. **It deliberately reveals no app UI and no phone screen.** The hero is abstract: a single position dot on a route line. Satellites hold it. They drop away. The world goes dark and the dot turns red, yet it keeps moving along the road with an honest growing uncertainty ring. Then light, the name, and "Coming soon".

## Hook (0–2.4 s)
White space. A route line draws across the frame and a blue position dot rides it. Four satellites (GPS, Galileo, BeiDou, NavIC) lock on one per 8th note. "Guided by satellites."

## Key moments
- 2.4–4.8 s: the satellite lines snap one by one. The world falls to graphite and tunnel lights streak past. "Until the signal disappears."
- 4.8–7.2 s: the beat drops. The dot turns red and keeps moving, leaving a dashed red trail, while its uncertainty ring slowly grows. "Something keeps moving."

## Outro (7.2–10 s)
The exit bursts to white. "GatiSaarth" / "Navigation beyond GNSS." / "Coming soon". The final chord rings to the end.

## User flow worth showing
None, on purpose: the user asked for a sneak peek that does not reveal the app. The film's own visual motifs (route, puck, dashed dead-reckoning trail, satellites, tunnel) carry it.

## Tone
- Preset: cinematic, held back with polished restraint
- Creative direction: Apple-style teaser; withholding, bright, precise
- Interpretation: one idea per beat, big quiet type, motion from the camera and the dot, with the drama coming only from light and sound.

## Format: landscape 1920x1080, 30 fps
## Duration: 10 s (user request; overrides /brag's 15-25 s default)

## Visual identity
The same tokens as the launch film: paper #F5F5F7, ink #1D1D1F, grey #86868B, blue #007AFF (#2997FF on dark), dead-reckoning red #FF3B30, graphite #0A0B0E, Inter Display 600 (the app's own font file) and JetBrains Mono for the satellite IDs.

## Share copy (draft)
When the sky goes quiet, something keeps moving. GatiSaarth — coming soon.

## Audio direction
- Role: cinematic support; an original score synthesized in `score/teaser_score.py` (the same instruments as the film), 100 BPM
- Arc: air and chimes → snaps, a boom, a near-silent tunnel with light whooshes → the drop at 4.8 s → a burst and final D major 9 chord at 7.2 s that rings out
- Strong cues: 2.4 (snap), 4.8 (drop), 7.2 (burst). Satellite locks on 8ths at 0.6/0.9/1.2/1.5, snaps at 2.4/2.55/2.7/2.85.
- Audio-reactive: subtle; RMS breathes the key light and the dot glow.
- Restraint: no alarms, and every text line holds at least 1.6 s.

## Storyboard
1. Satellites: 0.0–2.4. The route draws, the blue dot moves, 4 satellites lock. Text at 0.35 "Guided by satellites." (holds to 2.2).
2. Signal loss: 2.4–4.8. Lines snap (2.4–2.85), the world goes graphite by 3.2, tunnel streaks start. Text at 2.9 "Until the signal disappears." (holds to 4.6).
3. Keeps moving: 4.8–7.2. The dot is red with a dashed trail and a growing ring, and the camera tracks. Text at 5.0 "Something keeps moving." (holds to 7.0).
4. Reveal: 7.2–10. White flash, then "GatiSaarth" (7.45) / "Navigation beyond GNSS." (8.0) / "Coming soon" (8.5). Held to 10.
