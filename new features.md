# GatiSaarth — SIH26168 feature research and build shortlist

**Problem statement.** SIH26168 is ISRO's software challenge, *“AI-ML based Intelligent Dead Reckoning system for seamless navigation”* under Smart Vehicles. It targets vehicle navigation when GNSS fails in tunnels/underpasses, multilevel parking, dense forests and urban canyons. [Problem record](https://sih2026.vuce.in/ps/SIH26168)

## What we already have (do not spend hackathon time duplicating it)

GatiSaarth already has the difficult baseline: a 15-state ES-EKF, inertial mechanisation, automatic phone-to-vehicle alignment, NHC, ZUPT/ZARU, GNSS innovation gating, an advisory on-device speed model, offline PMTiles maps, HMM map matching, transparent covariance, and replay benchmarking. The README also identifies the important current gaps: real-device field evidence, long-outage drift, an empty shipped road graph, and simulated rather than real Android raw-GNSS/NavIC telemetry.

The winning direction is therefore **not “another navigation app.”** It is a *navigation-resilience platform*: it knows how trustworthy its location is, obtains safe correction from independent signals when possible, keeps working without network, and proves the result on real routes.

## Ranked major features

| Priority | Feature | What the user sees | Why it changes the solution | Demo / success metric |
|---|---|---|---|---|
| P0 | **1. Resilience Fusion Engine** | A live “Trusted / Degraded / Recovering” state, an uncertainty corridor, and the best remaining correction source | Fuse the existing EKF with map constraints, barometric floors, GNSS quality and optional visual/Wi-Fi anchors instead of treating every outage alike | Real 2–5 minute tunnel/parking run; report median and P95 along-track error versus GNSS truth |
| P0 | **2. Real GNSS + NavIC Integrity Lab** | Per-constellation sky plot, C/N0 trend, carrier-phase/raw-measurement availability, multipath/jamming suspicion and an exported signed evidence report | Delivers the ISRO-relevant, device-real part currently simulated; Android exposes raw measurements on supported devices, but capabilities vary by chipset | Compare clean sky, urban canyon and tunnel entrance; accurately reject a deliberately replayed/bad fix without falsely calling it spoofing |
| P0 | **3. Offline route corridor and turn recovery** | Before an outage, the app caches the route and announces only high-confidence turns; during it, it shows possible road branches rather than a falsely exact blue dot | Converts dead reckoning into decision support. Map matching should constrain the filter, while ambiguity is preserved as multiple hypotheses | At a fork inside a simulated/real outage, show two corridors then collapse to the correct one after an anchor/fix |
| P0 | **4. Field-validation console** | One-tap “record mission,” route replay, automatic outage slicing, phone/mount metadata and a shareable accuracy card | A national jury can trust measured performance more than a headline claim. This directly fixes the README's simulated-benchmark limitation | Publish three repeatable routes (tunnel, urban canyon, parking) with raw logs, ground truth method and a reproducible score |
| P1 | **5. Multi-modal profile switcher** | Auto-detects car, two-wheeler, pedestrian/last-mile and stationary; each has its own constraints and confidence model | India is two-wheeler-heavy and the problem explicitly includes ride-hailing/logistics. Car NHC is unsafe for a bike and unusable on foot | Start a ride, park, then walk: mode switches must be visible and no car-only lateral constraint is applied to walking |
| P1 | **6. Anchor marketplace, privacy-first** | “Anchor acquired” from a QR/AprilTag at a tunnel portal, a known parking checkpoint, BLE beacon, Wi-Fi RTT or approved visual landmark | Each independent anchor bounds MEMS drift during long outages. Start with QR/visual portal anchors (cheap and deterministic); make radio anchors optional, never required | Place two printed portal markers in a 200 m test route; demonstrate drift reset and quantify the error before/after |
| P1 | **7. Visual re-localisation, not continuous camera surveillance** | The camera activates only after the user opts in or confidence becomes low; it recognises a preloaded landmark/portal and proposes a correction with confidence | A compelling AI feature that is believable on a phone. It corrects the existing filter rather than replacing it with a fragile black box | Recognise 10 held-out portal/landmark images offline, show precision/recall and reject unfamiliar scenes |
| P1 | **8. Device capability & self-calibration passport** | At setup: sensor-rate check, raw-GNSS support, barometer/magnetometer status, mount-confidence, thermal/battery warning and the expected outage range | Commodity phones differ sharply. Honest per-device capability prevents impressive-but-unrepeatable results | Compare two phones; the app selects a conservative profile and explains why its confidence differs |
| P1 | **9. Safe-outage mission mode** | Driver-first voice/haptic prompts, no distracting map interaction, last trusted exit/turn, “do not reroute while uncertain,” and SOS/last-known-location packet | Improves the actual safety scenario—emergency responders, delivery and ride-hailing—not merely location accuracy | Screen-record a tunnel exit: all critical feedback is audible/haptic and the app avoids a false turn instruction |
| P2 | **10. Federated road-quality and GNSS-risk map** | An opt-in layer shows anonymised, time-bounded “GNSS risk” and verified tunnel/portal anchors; it also recommends where to calibrate before an outage | Moves from one-phone resilience to a public-good, India-scale system without uploading raw tracks | Simulate contributions from 20 devices, aggregate only into road cells, and show k-anonymity threshold + expiry |
| P2 | **11. Road graph pack builder + local routing** | Users download a city pack containing routable roads, restrictions, tunnel/parking metadata and voice instructions—fully offline | Completes the currently empty road graph and makes the offline claim useful for actual navigation | Generate one city graph from OSM, prove offline route + reroute in airplane mode |
| P2 | **12. Explainable ML guardrails** | Every correction has a “why accepted/rejected” card: sensor quality, map likelihood, anchor score and estimated impact; ML can lower confidence but cannot silently overwrite physics | Stronger than adding an LLM: it combines AI with auditable navigation safety | Inject a bad GNSS fix and low-quality visual match; show the exact gate which rejected each |

## Recommended build order

### Phase A — jury-winning core (build these first)

1. **Real GNSS + NavIC Integrity Lab**: replace simulated satellite panels with `GnssStatus` / raw-measurement bindings, capability detection and log export. Android documents that raw GNSS is broadly available but that individual fields are chipset-dependent; feature-detect rather than promise every signal. [Android raw GNSS documentation](https://developer.android.com/develop/sensors-and-location/sensors/gnss)
2. **Offline route corridor + real road graph**: package a small Delhi/Pune/Mumbai graph and extend the current HMM to retain top-k plausible road paths during degraded operation.
3. **Field-validation console**: use the same raw record/replay to generate a clear accuracy report. This is the proof layer for every claim.
4. **Safe-outage mission mode**: make the narrative human: a delivery rider/emergency driver reaches the correct exit despite a tunnel outage, with transparent uncertainty.

#### Phase A completion status — 22 September 2026

**Implementation status: complete.** The software gate for starting Phase B is closed. The application version intentionally remains `3.1.0`; it will be changed to `4.1` only after all planned phases are complete.

- [x] **Real GNSS/NavIC Integrity Lab:** native Android GNSS status and raw-measurement observation counts; constellation-aware satellite data; C/N0 history; used-in-fix ratio; ADR availability; conservative Healthy/Degraded/Anomaly/Unavailable classification; and explicit capability fallback without claiming spoofing detection.
- [x] **Offline route corridor + real road graph:** bundled Delhi-NCR PMTiles road data, dynamic OSM road-graph extraction, HMM top-three corridor hypotheses during an outage, ranked map rendering, and ambiguity-preserving UI instead of a falsely exact location.
- [x] **Field-validation console:** mission recording/replay, automatic outage benchmark comparison, device/app/vehicle/mount/config metadata, receiver evidence summaries, field-versus-simulated labeling, Android Keystore EC signatures, public-key export, SHA-256 digest, and one-tap evidence sharing.
- [x] **Safe-outage mission mode:** last-trusted-road/heading retention, automatic-reroute pause, uncertainty and ambiguous-fork warnings, recovery announcement, optional English-India voice guidance, haptic warnings, and suppression of unsafe turn instructions while the road hypothesis is ambiguous.
- [x] **Automated acceptance:** unit/widget/integration coverage for GNSS integrity, road corridors, field evidence, mission guidance, and recording metadata; Dart static analysis and Android native compilation included in the delivery gate.
- [ ] **Physical field campaign:** collect the three planned real-world evidence sets—tunnel/underpass, urban canyon, and multilevel parking—on a supported Android handset. This is an operational validation run using the completed recorder and signed-evidence workflow, not an unfinished software feature.

**Phase B entry criterion:** Phase B development can start now. Before the SIH demonstration freeze, the physical field campaign above must be completed and its signed evidence artifacts archived with the tested handset and mount details.

### Phase B — the differentiators

5. Add QR/AprilTag tunnel/parking portal anchors, then one optional radio anchor. Do not begin with a beacon network; it is expensive to deploy and weakens the “commodity phone” story.
6. Add multi-modal classification and profile-specific constraints. Android's activity-transition API supports in-vehicle, bicycle, walking, running and still transitions, making this practical and battery-aware. [Android documentation](https://developer.android.com/codelabs/activity-recognition-transition)
7. Add offline visual re-localisation as a gated measurement update, with a hard reject threshold and no background video upload.

#### Phase B software status — 23 September 2026

- [x] **Trusted portal-anchor core:** a QR/AprilTag payload is an identifier only; it must resolve against a device-local registry, may be used only during an outage, and must pass a conservative residual gate.
- [x] **EKF integration:** an accepted portal is recorded as an auditable `portal_anchor` measurement with its own fusion contribution. It never directly overwrites the estimated position and never falsely declares GNSS recovery.
- [x] **Offline anchor-pack and scanner flow:** versioned device-local packs, strict coordinate/descriptor/BSSID validation, QR/Data Matrix camera scanner, user-facing acceptance/rejection, and app-specific sideload path. The bundled pack is deliberately empty: its old unsurveyed demo coordinate was removed, so it cannot correct a live journey.
- [x] **Multimodal switching:** opt-in Android Activity Transition events for car, bicycle, walking, running and still; the matching car/two-wheeler/pedestrian dynamics; no car-only lateral constraint or driving-road snap while walking. A manual profile selection disables automatic switching until re-enabled.
- [x] **Offline visual landmark path:** user-triggered camera capture, temporary-file deletion, on-device 256-bit descriptor matching against enrolled local landmarks, hard confidence and runner-up margins, outage/residual gate, then a named `visual_anchor` EKF measurement. No background video or image upload.
- [x] **Optional radio path:** user-triggered Android Wi-Fi RTT to an installed, RTT-capable access point BSSID; permission/hardware/freshness/range/uncertainty checks; a rejected or unsupported reading never moves the estimate. It is not needed for the commodity-phone QR path. [Android Wi-Fi RTT guide](https://developer.android.com/develop/connectivity/wifi/wifi-rtt)
- [x] **Software verification:** 1,019 Flutter tests passed (29 skipped), 86.9% overall Dart line coverage, targeted Dart analysis clean, Android Kotlin compilation successful, and a debug APK built. Repository-wide analysis still reports 10 pre-existing warnings/info in unrelated home-tab, motion-widget and calibration-test files.
- [ ] **Field acceptance:** survey and install a real portal/landmark/RTT AP pack; run held-out image false-positive/false-negative trials and physical tunnel/parking routes on the target Pixel. Confirm that core EKF acceptance improves measured position before enabling it to lead the driver-facing map. The QR/visual/radio update currently corrects the navigation core, while the map only follows that core after the existing field-validation handover gate. Do not present simulated or unsurveyed anchors as physical proof.

**Phase B handoff:** the software integration is ready for Phase C work, but the field-acceptance item is an open operational gate for the SIH demo. App version and the Pixel installation remain at `3.1`; do not switch to `4.1` or update the handset until all planned phases and release checks are complete.

##### Field anchor-pack contract

The operator must measure each marker's actual WGS84 coordinate and conservative horizontal uncertainty. A printed QR/Data Matrix contains only `GSARTH-ANCHOR:1:<id>`, never raw coordinates. To enroll a landmark photo locally, run `dart run tool/anchor_descriptor.dart <photo>` from `frontend` and copy the 64-character lowercase hash. A Wi-Fi RTT `radioId` is the AP's lowercase BSSID; the AP and phone must both support RTT, and a single range is treated as a coarse, near-AP correction rather than triangulation. Android exposes RTT hardware and permission limits in its [official guide](https://developer.android.com/develop/connectivity/wifi/wifi-rtt).

```json
{"schemaVersion":1,"packId":"surveyed-site-2026-09","anchors":[
  {"id":"portal-a","label":"Surveyed tunnel portal A","kind":"tunnelPortal","lat":28.6000,"lon":77.1000,"sigmaM":5},
  {"id":"landmark-b","label":"Approved landmark B","kind":"approvedLandmark","lat":28.6001,"lon":77.1001,"sigmaM":5,"visualDescriptor":"<64 lowercase hex characters>"}
]}
```

The JSON example is a schema illustration, **not a real surveyed pack**. Replace every coordinate, uncertainty and descriptor using actual field measurements. Save the validated file as `anchors/portal_anchors.json` under the Android app-specific external files directory (`/sdcard/Android/data/com.gatisaarth.app/files/`). Restart the session to load it. An invalid installed pack fails closed; it does not silently fall back to demo coordinates. Capture several independent landmark views and unknown-scene negatives before allowing a visual correction in a judged field run.

### Phase C — scale narrative

8. Build the opt-in aggregated GNSS-risk map only after the single-device story is validated. It needs explicit consent, minimum aggregation thresholds, short retention and a local-only default; do not collect raw location histories by default.

## Architecture: keep the filter authoritative

```text
IMU + barometer + GNSS/NavIC raw quality + activity mode
                         |
                         v
                   existing ES-EKF
                         |
    +--------------------+---------------------+
    |                    |                     |
road-corridor      anchor measurement     integrity policy
(top-k paths)      (QR / visual / RTT)    (accept / downweight / reject)
    |                    |                     |
    +--------------------+---------------------+
                         v
         trusted pose + uncertainty + explanation
                         |
          safe voice/haptic guidance + field report
```

Every new source must be represented as a measurement with uncertainty. If its confidence is inadequate, it may widen the uncertainty or flag an incident, **never silently move the vehicle**. This is the core engineering distinction from a generic AI navigation demo.

## Features to avoid or defer

- **Generic chatbot/LLM assistant:** not a positioning improvement and difficult to validate.
- **Blockchain for route/location logs:** no direct benefit to dead reckoning; signed local reports are simpler.
- **Continuous cloud video or raw-track upload:** contradicts the existing privacy-first value proposition and creates consent/security risk.
- **Claiming spoofing detection from a single failed fix:** label it “integrity anomaly” unless raw-signal evidence supports a stronger conclusion.
- **Promising sub-2% drift for all phones/outage lengths:** replace with device-specific, route-specific measured confidence bounds.

## Research basis and design implications

| Evidence | Implication for GatiSaarth |
|---|---|
| ISRO says NavIC is India's independent regional navigation system and that phone location may combine multiple constellations, including NavIC. [ISRO NavIC FAQ](https://www.isro.gov.in/Navic.html) | Show constellation-aware diagnostics and leverage NavIC where the handset exposes it; do not label every satellite-derived location “GPS.” |
| Android makes raw GNSS measurements available on many devices and provides antenna information on Android 11+, while warning that fields differ by chipset. [Android raw GNSS](https://developer.android.com/develop/sensors-and-location/sensors/gnss) | Build a capability passport and a raw-signal integrity score with graceful fallback. |
| Reviews of indoor positioning find smartphone inertial-only positioning vulnerable to accumulated drift and recommend combining it with map matching or another absolute source for higher accuracy. [Review](https://www.mdpi.com/2072-4292/16/2/398) | Prioritise independent anchors and uncertainty-aware road corridors over a larger IMU-only neural model. |
| Offline OSM data is useful underground, in unreliable networks and disaster relief; offline routing frameworks are available. [OpenStreetMap offline guidance](https://wiki.openstreetmap.org/wiki/Offline) | Ship a routable graph pack, not only rendered map tiles. |
| Android activity transitions can identify mode changes without continuously polling multiple signals. [Android activity transitions](https://developer.android.com/codelabs/activity-recognition-transition) | Implement a power-conscious multi-modal state machine and mode-specific EKF constraints. |

## One sentence for the SIH pitch

**GatiSaarth is an India-first, on-device navigation-resilience layer that fuses phone sensors, NavIC/GNSS integrity, offline road intelligence and trusted local anchors—telling a driver not just where they are during an outage, but how certain the system is and why.**
