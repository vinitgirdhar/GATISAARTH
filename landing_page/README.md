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

The visual language pairs white (`#ffffff`), graphite (`#1d1d1f`), cool gray (`#f2f2f4`), and route orange (`#ec5830`) with locally hosted Manrope variable typography. Stronger typography, restrained terrain graphics, neutral product surfaces, and graphite/silver device frames keep the actual app in focus. Interactive navigation scenes explain the product visually.

Motion includes scroll-linked journey progress strokes, a reversible signal-loss comparison with manual controls, expanding confidence rings, gentle FAQ reveals, a staggered hero entrance, a drawn route, scroll-linked phone movement, progressive journey steps, drawn sensor traces, and a sequenced fusion diagram. Scrolling through the tunnel scene advances its positioning stages; choosing a stage manually holds that choice until the next scroll boundary is crossed, in either direction. Native smooth scrolling preserves keyboard and touch behavior, without pinned sections or scroll hijacking. GSAP matchMedia reverts animations and ScrollTriggers when reduced motion is requested, including changes made while the page is open.

The two-track comparison contrasts a downloaded map with an added motion-estimation layer. Its signal toggle moves the estimated position and changes the uncertainty ring. This is a conceptual capability illustration, not a competitor benchmark. Supporting context and primary sources are in a disclosure. The footer credits Team CodeAstra, team ID 120431.

Both phone frames use graphite and silver edge highlights, with shallow 2D rotation to preserve screen readability. The screen itself is not covered by a gloss layer. Click to inspect the full-resolution capture.

Click either phone to inspect its actual screen in a keyboard-accessible native dialog. Escape closes the dialog and restores focus. The mobile menu, FAQs, and technical disclosures work with keyboard controls.

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

Capture screenshots from the actual application with ADB screencap, pull the PNG files into `public/screenshots/`, and update the capture version labels if needed. Do not recreate the app interface in HTML or change the screenshot contents.

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

If a Chromium executable is already installed, set `PLAYWRIGHT_CHROMIUM_EXECUTABLE` to its absolute path before running tests. Browser screenshots are generated in ignored `test-results/`.

## Deployment

Deploy `dist/` as a static site. Relative base paths support deployment at a subdirectory. The APK is a 113.7 MB static file; choose a host that permits files of that size, or upload it to a release asset host and update the download URLs. No deployment has been made by this rebuild.

Source layout: `index.html` for content, `src/style.css` for styling, `src/main.js` for interactions, `public/` for shipping assets, and `tests/` for browser verification.
