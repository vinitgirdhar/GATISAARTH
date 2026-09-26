# Navigation core — working notes

Loaded when working under `frontend/lib/core/nav/`. The hand-over contract, the
two clock traps and the "never quote simulated results" rule live in the root
`CLAUDE.md`. Read `docs/architecture/EVOLUTION_PLAN.md` before changing the core.

## Rules

- `nav_config.dart` holds every tunable in one versioned place. Nothing under
  `core/nav/` may hard-code a threshold; add it there instead.
- **Always rotate via `NavMath.rotateBodyToNav` / `rotateNavToBody`.**
  `vector_math`'s own `Quaternion.rotated()` applies the *opposite* sense to the
  matrix that same quaternion's `asRotationMatrix()` produces; a guard test in
  `test/nav/math_test.dart` pins that so a package upgrade cannot silently flip
  the heading sign.
- The GNSS integrity monitor says "GNSS integrity anomaly detected", never
  "spoofing".
- The HMM map matcher **refuses to snap** unless one road clears a threshold,
  beats the runner-up by a margin, and sits within the filter's own
  uncertainty. It feeds only *heading* back into the filter; the map never
  pushes position into the state.
- Replay is **bit-exact**: replaying a log reproduces the live run exactly,
  which is what makes a drift regression attributable to a code change. Keep it
  that way.

## Outage benchmark (`benchmark/`)

**The only accuracy yardstick that works on real phones.**
`OutageBenchmark.run(records)` replays any drive log with GNSS withheld from many
start times and scores the core and a hold-last-velocity baseline against the
*withheld fixes* (truth = the phone's own GNSS, so no reference receiver and any
phone works). Scores the core only while `NavigationSnapshot.canLeadPosition`
(the app's own hand-over test) holds; reports the truth's noise floor, the
phone's IMU/GNSS rates and sensors, and every window it skipped and why. On
device: Profile > Outage Benchmark (background isolate, reference drive or any
recording). Headless: `flutter test test/nav/reference_drive_asset_test.dart`
prints the report. Bundled reference drive is **simulated** (regenerate with
`UPDATE_REFERENCE_DRIVE=1`); on it the core beats hold-velocity by a wide margin
through bends and stops (30 s: 12 m vs 189 m) and, since the 2026-09-26 heading fix,
60 m median at 120 s (3-sigma 6/6; it was 281 m) - see
`docs/architecture/EVOLUTION_PLAN.md` P2. **Never quote simulated results as
field accuracy; record real drives (Sensors > Navigation core) and score them.**

## Measured numbers (quote honestly)

**Measured limits:** at rest, accelerometer bias and tilt are not separately
observable (a 0.3 m/s² bias is absorbed as 1.744° of pitch), so ZUPT stops
velocity drift but does *not* identify the bias. NHC alone cannot observe yaw —
only NHC together with an independent velocity reference can (measured: 0.68° vs
34° heading sigma). A constant acceleration has zero variance, so the stillness
gate must test horizontal specific force, not just variance. Gravity may only be
estimated while the vehicle is *not* accelerating.

**Drift, simulated only:** 1.75 % at 60 s, 5.64 % at 300 s
(`flutter test test/nav/drift_benchmark_test.dart` prints the table). That is a
bound on the estimator under modelled sensor error — **not** a field
measurement, and never to be quoted as measured accuracy.

**Cost:** 20 µs per sensor frame, 74 µs peak — about 0.1 % of a core at 50 Hz, so
the C++ port stays unjustified until profiling says otherwise.

**Measured ablation** (`flutter test test/nav/ablation_test.dart`, 60 s outage,
5 seeded drives): raw inertial 35.1 % drift, + GNSS velocity 15.4 %,
**+ non-holonomic constraint 1.4 %**, and nothing after that moves the number. NHC
is the dominant lever by 11×. ZUPT/ZARU shows no measurable benefit on these
cruising profiles — do not claim it does until a stop-and-go profile says
otherwise.

## Hand-held mode (2026-09-24, iteration 2)

`FeatureFlags.handHeldMode` (default **off**) lets the core lead with no
phone-to-vehicle mount at all: `motion/phone_handling.dart` (gravity-projected,
orientation-invariant yaw rate; a "handling" flag from how fast the low-passed
gravity direction is moving; an std(|a|) stop detector) plus
`motion/gyro_bias.dart` (a slow EMA of the yaw-rate bias, from GNSS-speed-gated
stops and from a course derived from GNSS position displacement while moving
straight and steady) feed `motion/hand_held_tracker.dart`, a small kinematic
integrator (bias-corrected heading + held GNSS speed, **not** the mounted EKF
— there is no known forward axis, so no NHC and no body-frame accel
integration). `NavigationEngine._runMapMatchHandHeld` feeds a matched road's
heading back into the tracker exactly like the mounted path's `_runMapMatch`
does for the EKF (§58: heading only, never position) — this is the "road
lock" for hand-held; the yaw rate still drives moment-to-moment heading and
would settle a junction choice, since `RoadFollower`'s own position lock is a
different, Flutter-side mechanism outside the pure-Dart core and out of scope
here. `NavigationSnapshot.handHeld` marks a hand-held solution;
`canLeadPosition` accepts it once `NavigationEngine._integrity()` clears it
(never above `NavIntegrity.medium` for hand-held, by construction).

**A real bug dominated the first cut's numbers.** `HandHeldTracker.onFix` only
ever read the fix's own `bearingDeg` for heading — and on one of the three real
drives, 0 of 459 fixes report a bearing at all (some receivers just don't).
With no heading, dead reckoning could not move at all (speed held nonzero,
heading stuck null), so the reported position sat frozen at the last fix while
the vehicle drove away — which is indistinguishable, in the error metric, from
open-loop bias drift (both read close to 100 % of the distance travelled). Now
`onFix` falls back to a course from the raw lat/lon displacement between
consecutive fixes when no native bearing is present
(`HandHeldConfig.headingSigmaFromDisplacementRad` etc.) — this alone accounts
for most of the improvement below, not the bias term.

**Also found:** `benchmark_job.dart`'s `_roadGraphFor` reads
`DriveRecord.latitude`/`.longitude`, which are only ever populated for a
simulated `truth` record — a real phone log has none, only `gnss` ones, so
`DRIVE_MAP=` silently built no graph at all for a real drive. Not touched
(off-limits); `score_drive_test.dart` now builds the graph itself from the
log's own `gnss` fixes and calls `OutageBenchmark.run` directly.

**Real-drive result, all three drives, tuned on all three together** (not a
strict per-fold search — see the leave-one-out note below):
`DRIVE_LOG=... NAV_HANDHELD=1 [DRIVE_MAP=.../mumbai.pmtiles] flutter test
test/nav/score_drive_test.dart`. Median error at the end of the outage,
metres (see the CLAUDE.md-adjacent test output for p95 and 3-sigma-ok %):

| drive | dur | hold | hand-held (no map) | hand-held + map |
|---|---|---|---|---|
| 145822 (n=2, mostly `engineNotLeading`) | 30s/60s/120s | 18.8 / 140.8 / 177.1 | 102.5 / 262.7 / 664.3 | 106.8 / 271.3 / 668.6 |
| 151514 (n=12-15) | 30s/60s/120s | 60.0 / 156.2 / 328.3 | 70.4 / 203.5 / 422.1 | 44.8 / 140.3 / 438.9 |
| 162733 (n=11-15) | 30s/60s/120s | 89.6 / 182.2 / 402.5 | 123.4 / 153.4 / 248.5 | 89.6 / 101.9 / 241.1 |

3-sigma consistency (real error inside 3 sigma), hand-held + map, tuned
config: drive 145822 (n=2, too small to read) 100/100/50/0 %, drive 151514
13/13, 14/15, 13/15, 9/12 (100/93/87/75 %), drive 162733 7/7, 7/11, 7/13, 7/15
(100/64/54/47 %) at 10/30/60/120 s. Up from 0/n on every bucket of every drive
in iteration 1 (the frozen-position bug made every error near-deterministic,
so the old sigma never had a chance) - the along-track fraction
(`alongTrackErrorFraction`) and heading-sigma growth rates were raised until
further increases stopped moving the shorter buckets and only inflated the
longer ones; **60-120 s consistency on drive 162733 still falls short of
~90 %** - a few outlier windows (a missed turn, a stop mis-detected) drive
errors far outside what a smooth linear-growth sigma can honestly cover
without being absurdly conservative everywhere else. Left as a known gap
rather than chased further.

**Leave-one-out, honestly:** the sigma-growth constants above were tuned while
looking at all three drives' 3-sigma numbers together, not by a strict
"tune on two, score the third" search per fold - with only three drives (one
of them n=2), a real per-fold parameter search would be fitting noise. What
*is* leave-one-out-clean: the map-matching wiring and the bias/heading-source
fixes were built and debugged against the mechanism (the synthetic test,
`phone_handling_test.dart`), not against any of the three drives' numbers, so
their improvement on all three is not circular.

**Decision: `FeatureFlags.handHeldMode` stays off by default.** Hand-held +
map beats hold on 2 of 3 drives at 60 s and 120 s (151514 at 60 s only, 162733
at both), but drive 145822 is worse by 3-6x, not within the 10 % the
coordinator's bar allows - and that drive also mostly fails to lead at all
(`engineNotLeading` skipped 44 of 60 window-attempts), a separate, unexplained
weakness worth its own investigation before this ships. `NavConfig.live` does
not set `handHeldMode`, so the shipped app is unaffected either way; this
stays benchmark-only. Unit tests (`test/nav/phone_handling_test.dart`,
`test/nav/hand_held_engine_test.dart`) still cover the detector/bias/tracker
mechanism in isolation on a synthetic outage with a real stop and a bias in
it.

**Next iteration, if resumed:** find out why drive 145822 mostly cannot lead
at all (44/60 window-attempts skipped) before touching sigma again; a fourth
real drive would make the leave-one-out study honest; the map-matching gain on
151514/162733 suggests investing there (a tighter road search radius, a real
junction-choice policy from the yaw rate) rather than more sigma tuning.

## Heading, divergence and earned trust (2026-09-26, first real rickshaw drive)

A realme RMX3851 lying on an auto-rickshaw seat (100 Hz IMU, 1 Hz GNSS, 10.6
min) exposed three real-phone failures the simulations never showed:

- **No bearing ever reached the core.** `LiveSessionController` never passed
  `bearingDeg`, so the filter started at heading 0 (north) and never got a
  GNSS velocity update. A wrong heading is self-sealing: NHC pins velocity
  along the wrong axis, speed collapses, and yaw becomes unobservable from
  position. The core ran ~90 deg off for the whole drive while reporting
  integrity HIGH. Fixed three ways: the app now passes the Android bearing
  (`GnssFix.bearing`, only when moving); `gnss/gnss_course.dart` fills in a
  course traced by the fixes when there is none (straight chords of >= 20 m),
  and the filter waits for a heading before it initialises; and a heading
  guard re-seeds the filter when the GNSS course keeps disagreeing
  (`GnssCourseConfig.guard*`), refusing to lead meanwhile.
- **Velocity ran away while GNSS was live** (32 m/s vs 3 m/s), with the
  filter's gate refusing the fixes. Fixed: the receiver's Doppler speed is a
  forward-speed update whenever there is no course, and three position fixes
  refused in a row re-seed the filter (position only: a refused speed can be
  the receiver's ~1 s lag in hard acceleration).
- **The core led while worse than holding the last velocity.** Fixed with the
  earned-trust gate (`NavigationSnapshot.predictionTrusted`): while GNSS is
  live the core must predict each next fix within 1.25x + 2 m of what holding
  the last velocity predicts (median over 20 fixes), or it may not lead.

Result on that drive (Mumbai map, `score_drive_test.dart`): before, the core
led from 64 s and was 272 m off at 10 s against 5.6 m for hold. After, it
declines to lead on 56 of 57 windows and the app keeps its own pipeline. **A
loose phone on a seat still does not beat hold**: the EKF's accel-bias
estimate absorbs the phone's changing tilt (~0.5 m/s^2). `FeatureFlags.
speedPrior` (last GNSS speed as a growing-sigma forward-speed update in an
outage) helped a little (10 s 62 -> 42 m) and stays off until more drives show
it helps. The simulated reference drive changed too, because it has no
bearings either: 30 s 12.0 m, 60 s 23.4 m, **120 s 60.1 m (was 281 m)**,
3-sigma 6/6 at 120 s. Simulated, not field accuracy.

Tools: `DRIVE_LOG=... [OUTAGE_AT=s] [REJECT_WIN=a-b] [NAV_NOMAG=1] flutter
test test/nav/diagnose_drive_test.dart` prints the core against GNSS per fix;
`NAV_SPEEDPRIOR=1` on `score_drive_test.dart` A/Bs the speed prior.

## Road graph and map matching

**No road graph file ships** (`maps/processed_graphs/road_edges.json` is
`{"edges": []}` and nothing reads it): since v3 the engine's HMM matcher is handed
the graph the phone builds from its installed map packs
(`NavigationEngine.setRoadGraph`, called from `LiveSessionController` whenever
`RoadConstraint` loads roads), so map matching is **live wherever a pack with
maxZoom >= 13 covers the vehicle** and reports unavailable elsewhere. The graph is
cut at every junction, so the matcher pools consecutive edges of one road
(`MapMatchConfig.continuationDeg`) instead of calling them rivals. The Python
builder (`python -m maps.tools.graph_builder overpass.json out.json`) and
`test/nav/graph_builder_contract_test.dart` still pin the JSON format.

## Road-locked dead reckoning — internals and traps

- Tile roads are clipped at the tile edge and lines are cut at junctions (side
  streets end 0.05-0.4 m off a bare segment of the road they join; without the
  noding ~77 % of interior dead ends were phantom). Edge ids are 1..N per build
  and node ids opaque: **never hold either across builds.**
- `road_follower.dart`: position = (edge, direction, metres along). **Geometry
  only** - long edges run through many crossings and neighbouring tiles overlap,
  so `fromNode/toNode/outgoing` say nothing. Straight through a crossing unless
  the gyro shows a turn (`yawDeg`: compass-positive, right = +; **exactly 0 means
  "no gyro information"**, which is what the simulators send). Thresholds live in
  `NavConfig.roadFollow`. Skip yaw while stopped or a gyro bias reads as a turn.
  A dead end stops a real drive (the map has run out) and turns a simulated one
  round (`reverseAtDeadEnd`).
- `road_constraint.dart` locks on at outage start (satellite course beats the
  compass).
- Urban canyon: a fix only nudges along-track when its speed is >= 1 m/s; a
  standing phone (the emulator's) keeps the simulated 8.33 m/s cruise.
- `test/road_real_map_drive_test.dart` drives both simulators through the real
  Delhi archive (in the repo, git-ignored) and through any archive in
  `MAP_PACK_DIR` (`adb pull` a phone's `files/offline_maps/*.pmtiles`); it skips
  what it does not find.
- Real-data traps found only by driving real roads (both pinned by tests): the
  follower could circle a sliver of digitising noise for ever (a closed edge of a
  metre or two taken for a roundabout, or an exit back onto the edge just left) -
  `RoadFollowConfig.ringMinLengthM` / `recentEdgeWindowM`, property test
  `test/road_real_follower_property_test.dart` (fails within 1 m of "driving" when
  the guards are off); and a graph cut at every junction made the matcher say "two
  roads too close to call".
- Evidence (all reproducible, numbers in `docs/evidence/`): region road-graph
  coverage (`road_graph_coverage.json`), matching on real streets with simulated
  sensors (`real_road_map_matching.json`), and real IO-VNBD drives on a real UK
  OSM archive cut with the phone's own downloader (`iovnbd_real_map_matching.json`).
