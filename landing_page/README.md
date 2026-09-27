# GatiSaarth launch website

An original, responsive launch website built with semantic HTML, CSS, and JavaScript. Vite handles development and the static production build. GSAP and ScrollTrigger orchestrate the motion; no UI framework is required.

## Run

Requires Node.js 22.12+ (tested with 22.16).

```powershell
cd D:\gathisarthi\landing_page
npm.cmd ci
npm.cmd run dev
```

Development: http://127.0.0.1:5173. `npm.cmd run build` creates `dist/`; `npm.cmd run preview` serves it at http://127.0.0.1:4173.

## Design and behavior

The visual language pairs white (`#ffffff`), graphite (`#1d1d1f`), cool gray (`#f2f2f4`), and route orange (`#ec5830`) with locally hosted Manrope variable typography. Stronger typography, restrained terrain graphics, neutral product surfaces, and graphite/silver device frames keep the actual app in focus. Interactive navigation scenes explain the product visually. The engineering summary, fusion diagram, Android download, and their disclosures share one responsive section so the conclusion stays compact.

Motion includes scroll-linked journey progress strokes, a reversible signal-loss comparison with manual controls, expanding confidence rings, gentle FAQ reveals, a staggered hero entrance, a drawn route, scroll-linked phone movement, progressive journey steps, drawn sensor traces, and a sequenced fusion diagram. Scrolling through the tunnel scene advances its positioning stages; choosing a stage manually holds that choice until the next scroll boundary is crossed, in either direction. Native smooth scrolling preserves keyboard and touch behavior, without pinned sections or scroll hijacking. GSAP matchMedia reverts animations and ScrollTriggers when reduced motion is requested, including changes made while the page is open.

The two-track comparison contrasts a downloaded map with an added motion-estimation layer. Its signal toggle moves the estimated position and changes the uncertainty ring. This is a conceptual capability illustration, not a competitor benchmark. Supporting context and primary sources are in a disclosure. The footer credits Team CodeAstra, team ID 120431.

The hero phone is upright and contains an interactive frontend app. **Experience app** or the map's expand control opens the same running app in an immersive native dialog. The second phone retains its full-resolution Android Home capture. Both frames use graphite and silver highlights, without a gloss layer over the screen. Escape closes the current app sheet/page before closing its outer dialog; closing restores scrolling and focus.

## Interactive app experience

`src/app-simulator.js` implements an isolated Shadow DOM component, using the running Pixel 9 application and Flutter theme/screens as references. Its state moves intact between the hero and expanded view. Phone screens fill the available viewport; landscape puts map and controls side by side; larger screens show a framed phone with a short introduction.

- **Home:** readiness, journey summary, editable starting point/destination, local place search, map-point selection, route preparation, preview, and navigation.
- **Map:** Mumbai street geometry, route/position/destination, vehicle-following camera, route-derived guidance distance, collision-filtered street labels, drag/keyboard pan, pinch/button zoom, overview/recenter, accelerated journey playback, arrival, growing uncertainty during signal gaps, and recovery. Tunnel tests cruise at a sample 45 km/h until ended; urban canyon alternates lost/intermittent fixes at 30 km/h. Timed GPS loss has the app's 10/20/30/45/60-second picker, countdown, reacquisition, example scorecard, rerun, and cancellation without a saved result.
- **Sensors:** status and changing sample diagnostic readings.
- **Profile:** vehicle selection, light/dark appearance and preferences, local map selection, recordings/JSON export, outage logs, sample benchmark replay, all nine fault presets with single/batch replay, trusted/unrecognized sample portal matching, diagnostics pause/clear/export, and navigation-engine information. Preferences persist in localStorage; routes, recordings, and logs last for the page session. Cancelling a replay does not create results.

`src/simulator-scenarios.js` supplies deterministic illustration values. Benchmark/fault/anchor flows explicitly identify their local sample data; they are not measured engine results, signed evidence, or surveyed anchors. Tunnel/canyon behavior and timed-outage controls were checked against the current Flutter controllers and screens. The component responds to visual-viewport changes for on-screen keyboards and keeps controls scrollable in short viewports.

This is a frontend simulation, not compiled Flutter or the production navigation engine. All sensor values and journey timing are samples. The bounded local street graph does not implement driving restrictions, production routing, live GPS, AI inference, hardware haptics/voice, or physical accuracy measurement. No navigation/backend service, API key, permission prompt, or mobile core change is involved. About and the expanded desktop introduction explain this scope.

The map is bundled in `public/simulator/mumbai.json` (about 981 KB), extracted from the app's existing `frontend/assets/maps/packs/mumbai.pmtiles`. Geometry is drawn in grouped SVG paths; no third-party map requests are made at runtime. OSM/Protomaps attribution stays visible. The derived data retains ODbL 1.0 licensing; the JSON includes provenance and can be obtained directly from the static site. Regenerate from the repository root's app pack with:

```powershell
cd D:\gathisarthi\landing_page
node tools/prepare-simulator-map.mjs
```

The app font is the actual bundled Inter variable font, losslessly repackaged as WOFF in `public/fonts/app-inter.woff`; its license is `public/fonts/Inter-OFL.txt`. Map extraction packages are development dependencies only. Reduced-motion settings suppress decorative app transitions; deliberate navigation playback remains interactive.

## Assets and provenance

- `public/screenshots/map.png` and `home.png` are unmodified 1280 × 2856 PNG captures taken directly from the running Pixel 9 Android emulator on 2026-09-27. Installed package: `com.gatisaarth.app`, version `5.2.1`, code `52`. They are actual application UI, not generated mock interfaces. The map capture shows a simulated drive in Mumbai: a saved 2.1 km route from 18.9401 N, 72.8347 E near CSMT to the Gateway of India. The Android emulator GPS was moved south with a southbound bearing and a displayed speed of 45 km/h. The captured app shows 2.0 km remaining, turn guidance onto Dr Dadabhai Naoroji Road, and the destination marker. The native screenshots have no yellow edge overlay; no cropping, sharpening, or generated interface was applied. The site identifies the drive as simulated in the enlarged view and FAQ. It demonstrates UI, not field accuracy. App simulation tests were ended and emulator GPS speed was reset to zero after capture.
- `public/downloads/gatisaarth-5.2.1.apk` is copied byte for byte from `../apks/GatiSaarth-v5.2.1+52-release.apk`. Package metadata confirms Android API 24 minimum, version 5.2.1/code 52, and `arm64-v8a`, `armeabi-v7a`, and `x86_64` support. File size: 113,704,871 bytes (113.7 decimal MB). The page and `SHA256SUMS.txt` include its actual SHA-256.
- `public/fonts/manrope-latin.woff2` is the Manrope variable Latin font served by Google Fonts; the SIL Open Font License is in `public/fonts/OFL.txt`. It is served locally, without a Google Fonts connection at page load.
- The route, terrain, and sensor diagrams are original SVG/CSS illustrations. They do not depict another application's UI or measured performance.
- Unused legacy assets were preserved in ignored `legacy-assets/`, outside `public/`, and are excluded from the build.

## Demo video

**View demo** and the demo FAQ open the 60-second, 1920 x 1080 launch film in an accessible native dialog. `public/media/gatisaarth-launch-v1.mp4` is a byte-for-byte copy of `../brag/2026-09-27-132145/Launch Video V1.mp4` (36,618,146 bytes; H.264/AAC). `launch-poster.jpg` is a frame extracted at 3 seconds. The video source is assigned only on an explicit click; opening starts playback with native seek, volume, and fullscreen controls. Escape, the close button, or the backdrop closes the player, pauses playback, and restores scrolling and focus. A download link remains available. The film presents simulated navigation, not field accuracy evidence.

On phone-sized screens, opening the film requests native video fullscreen and then `screen.orientation.lock("landscape")` when available. Orientation is released when leaving fullscreen or closing the dialog. iPhone/WebKit uses its native video fullscreen API where available. Browser permissions, OS rotation settings, and platform support can prevent forced landscape; the player retains native controls, a fullscreen retry button, and a rotate-phone hint. Fullscreen and orientation requests are tested using API stubs, including the WebKit and denied-fullscreen paths; these tests do not establish physical-device rotation compatibility. Verify on target Android/iPhone hardware before claiming universal automatic rotation.

## Updating the APK or app captures

Replace the APK in `public/downloads/`, then update both download URLs, visible version/size information, the SHA-256 in `index.html`, `SHA256SUMS.txt`, and the release expectations in `tests/launch.spec.js`. Compute the hash with `Get-FileHash -Algorithm SHA256`. Verify package metadata with Android SDK `aapt dump badging`. Do not infer version or architecture from the filename alone.

Capture screenshots from the actual application with ADB screencap, pull the PNG files into `public/screenshots/`, and update the capture version labels if needed. Keep these actual captures unmodified and distinct from the interactive frontend simulation.

## Content evidence

The journey copy was checked against `frontend/lib/features/journey/application/journey_service.dart` and `presentation/route_planner_screen.dart`: checking coverage, downloading missing corridor maps, computing routes locally, saving journeys, and a current destination distance limit of 80 km. The navigation engine, uncertainty model, AI feed, and engine specification screen support the descriptions of sensor fusion, confidence, and on-device models.

The page does not repeat the former unverified sub-2% drift, lane-centering, millimeter precision, or field benchmark claims. Performance depends on mounting, sensor quality, and outage duration; technical details explain those limits. Initial GNSS position and prepared map coverage are part of the described flow.

Approach comparisons link to primary sources directly:

- [Google Maps offline navigation](https://support.google.com/maps/answer/6291838?hl=en): offline maps are already available in existing navigation apps.
- [NovAtel GNSS/INS](https://novatel.com/products/gnss-inertial-navigation-systems): dedicated systems combine GNSS receivers and inertial hardware.
- [TLIO research](https://arxiv.org/abs/2007.01867): learned inertial estimation combined with filtering is established research. The page claims integration into the mobile journey experience, not invention of this field.

## Verification

```powershell
npm.cmd run check
npm.cmd run build
npx.cmd playwright install chromium
npm.cmd test
npm.cmd audit
```

Tests exercise 320, 390, 768, and 1440 px layouts, missing assets/runtime errors, actual capture loading, signal stages, the visual comparison, mobile menu keyboard behavior, screenshot dialogs and focus restoration, expanded technical/FAQ content, APK download and checksum, hidden scrollbars with functional scrolling, GSAP reveals, dynamic reduced-motion changes, team attribution, and automated WCAG A/AA checks.

Simulator tests additionally cover tablet/laptop/landscape sizes, route input and cancellation, map-picked destinations, driving/recording/export, signal loss and restoration, zoom/recenter, preference persistence, state retention during expansion, nested Escape behavior, and accessibility across its four tabs. These browser checks do not establish physical Android/iOS device compatibility or production navigation accuracy.

If a Chromium executable is already installed, set `PLAYWRIGHT_CHROMIUM_EXECUTABLE` to its absolute path before running tests. Browser screenshots are generated in ignored `test-results/`.

## Deployment

Deploy `dist/` as a static site. Relative base paths support deployment at a subdirectory. The APK is a 113.7 MB static file; choose a host that permits files of that size, or upload it to a release asset host and update the download URLs. No deployment has been made by this rebuild.

Source layout: `index.html` for content, `src/style.css` for styling, `src/main.js` for interactions, `public/` for shipping assets, and `tests/` for browser verification.
