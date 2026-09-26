# GatiSaarth UI redesign plan

## Goal

Make Home, Map, and Sensors feel calm, legible, and native to iOS conventions. Keep the live navigation and safety information truthful, while making the main task obvious without asking everyday users to read an engineering dashboard. Keep Profile's settings structure and the saved appearance preference intact.

## Visual direction

Use the app's existing iOS system palette and spacing tokens instead of introducing a second visual language:

- **Background:** OLED black `#000000` in dark mode; grouped system background `#F2F2F7` in light mode.
- **Raised surfaces:** `#1C1C1E` with `#2C2C2E` for nested controls in dark mode; white cards in light mode.
- **Primary label:** white / `#1C1C1E`; secondary label: `#98989F` / `#8E8E93`.
- **Accent:** system blue `#007AFF` for primary actions and selection. Use green, orange, and red only for actual navigation states.
- **Type:** use the app theme's SF Pro system type ramp consistently. Remove page-level Inter overrides in redesigned content.
- **Shape and spacing:** preserve the 8 pt rhythm and generous iOS sheet corners. Use grouped rows and only a few elevated surfaces; avoid a stack of equal-weight cards, gauges, and outlined badges.

The distinctive element is a single confident location/navigation status on each page. Everything else supports that message quietly. This keeps the Apple-inspired direction tied to GatiSaarth's real job—trustworthy navigation—rather than adding generic glass, gradients, or decorative chrome.

## Page concepts

### Home — at-a-glance navigation health

```text
Home                                     [status]
Navigation ready
GPS connected                           ±5 m

Navigation health
Location  ·  Sensors  ·  Road data

Recent activity / useful next action

System details                         Show
```

Replace the confidence/sensor/road ring trio and the prominent AI/telemetry stack with a single status summary, a concise speed/accuracy/phone-alignment snapshot, and a clear Start navigation action. Keep alerts, degraded states, outage/recovery guidance, and meaningful next actions prominent. Move model latency, temperature, vibration, and anomaly telemetry into Sensors or a collapsed detail section. Remove duplicate status announcements where the location banner and session card say the same thing.

### Map — map first, controls on demand

```text
[ Position reliable · ±5 m ]             [ Simulate ]
[ Drive recorder · core state ]           [ Record ]

                 MAP
          (recenter / layers)

╭──────────────────────────────╮
│  0 km/h             ±5 m     │
│  GPS accuracy          Details│
╰──────────────────────────────╯
```

Keep position trust and simulations in one compact row. Put the compact, live drive recorder directly below it, then let the map fill the remaining height. The recorder reports actual core state and recording duration/sample count. Keep speed and accuracy in the lower sheet, with heading and mode under Details. Open test scenarios from the simulation action; show a contextual end action only during a test.

### Sensors — status first, diagnostics by choice

```text
System health
All systems ready

Location                         Connected
Motion sensors                   Active
Phone alignment                  Learning
Navigation model                 Ready

Technical diagnostics                         Show
```

Replace the large mount-quality score panel and long technical inventory as the opening view with concise, named health rows and one overall state. Keep faults and degraded states visible in plain language. Put sample rates, per-axis scores, satellite constellations, NavIC weighting, and integrity history under Technical diagnostics. Keep the live-sensor count aligned in the disclosure header so it stays associated with diagnostics.

### Profile

Keep the existing vehicle selector and grouped Preferences list. Reuse its familiar settings-row treatment on Sensors; do not redesign Profile as part of this pass.

## Implementation scope

1. Rework Home hierarchy and remove duplicated status/gauge emphasis.
2. Rework Map's top overlays, bottom sheet, and simulation control labels/visibility without changing navigation actions.
3. Rework Sensors into a summary plus explicit diagnostic disclosure, preserving current measured values and fault states.
4. Reuse the existing theme tokens and Profile's grouped-row visual pattern; leave the appearance toggle and Profile content in place.
5. Keep section reveals vertical and layout-driven; use a directional parallax slide for tab changes, iOS-style push transitions for opened routes, and bouncing scroll physics rather than broad crossfades. Adapt tab-slide distance and duration to measured frame times and the display refresh budget, restoring full motion after sustained smooth frames. Respect the system reduced-motion setting.

## Review criteria

- A first-time user can tell whether location is reliable, degraded, or lost without interpreting GNSS acronyms or multiple gauges.
- The map is the dominant visual object on Map; safety state, location recentering, and map gestures remain easy to find.
- Sensors opens with an understandable health summary; technical values remain available after one deliberate expansion.
- Simulations read as simulations and cannot be confused with the live navigation state or a GNSS reset.
- Dark and light appearances remain legible, and the UI continues to scroll on smaller devices.
- Build, install on `emulator-5554`, open the app, and inspect all three redesigned tabs. Copy the verified debug APK into `D:\gathisarthi\apks` with a new versioned name, preserving existing APKs.
