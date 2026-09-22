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
through bends and stops (30 s: 12 m vs 189 m) but is weak at 120 s (281 m median,
its own 3-sigma covers the error in 3 of 6) - see
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
