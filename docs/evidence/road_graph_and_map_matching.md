# Real road graphs, live map matching, road constraints, lane-level scope (v3)

Covers `pending_work.md` items: populate the Delhi NCR and Maharashtra road graphs, activate live map
matching, demonstrate road/topological constraints on real data, address lane-level accuracy.

## What was built

* **Road graphs come from the maps the app already carries.** `core/nav/map/tile_roads.dart` +
  `road_noding.dart` turn the `roads` layer of the installed offline vector-tile archives (OpenStreetMap
  via Protomaps schema v4) into a `RoadGraph`: centre-lines, one-way (`oneway=yes/-1`), road class,
  bridge/tunnel, access filtering, lines cut at every junction (side streets that end 0.05–0.4 m off a
  bare segment of the road they join are joined; without that ~77 % of interior dead ends were
  phantoms). `core/platform/maps/pack_road_source.dart` reads a 5×5 block of z15 tiles around the vehicle
  off the UI thread and swaps the graph as the vehicle moves. Nothing extra ships in the app: a region
  has a road graph as soon as its map pack is installed.
* **Live map matching is on.** `LiveSessionController` hands the same graph to
  `NavigationEngine.setRoadGraph` (`MapMatcher.useGraph`), so the engine's HMM matcher now runs in the
  shipped app (before, it was always handed an empty graph and reported "unavailable"). The matcher was
  changed for graphs cut at junctions: edges of one road that share a node and continue within
  `MapMatchConfig.continuationDeg` (25°) pool their probability instead of counting as rivals
  (`test/nav/map_matching_test.dart`).
* **Road-locked marker** (`RoadFollower`, `RoadConstraint`): during an outage or the tunnel / urban-canyon
  demos the marker is held to the drawn road (see CLAUDE.md, "Road-locked dead reckoning").

## P4 / P5 — the graphs, measured (`road_graph_coverage.json`)

Region totals are counted over every tile of each archive (lines clipped at tile edges, nothing counted
twice); topology is measured on real 5×5-tile blocks built exactly as the phone builds them.
Reproduce: `EVIDENCE_DIR=docs/evidence MAP_PACK_DIR=<folder> flutter test test/tool/road_graph_coverage_report_test.dart`.

| Region (archive, zoom) | Road lines | Drivable km | One-way | Largest connected piece* | Junction nodes* | Dead-end nodes* |
|---|---:|---:|---:|---:|---:|---:|
| Delhi NCR (bundled, z15) | 216,340 | 38,969 | 18.7 % | 98–99 % | 74 % | 17 % |
| Mumbai (z15) | 82,280 | 16,424 | 26.4 % | 96–98 % | 64 % | 23 % |
| Pune (z15) | 65,743 | 11,621 | 14.3 % | 96–98 % | 59 % | 30 % |
| Nagpur (z15) | 39,157 | 7,633 | 14.4 % | 94–99 % | 71 % | 19 % |
| Nashik (z15) | 14,977 | 3,254 | 13.3 % | 93–99 % | 65 % | 23 % |
| Chhatrapati Sambhajinagar (z15) | 18,509 | 3,287 | 14.0 % | 94–97 % | 65 % | 24 % |
| Maharashtra statewide (z12) | 1,268,285 | 650,521 | – | – | – | – |

\* mean over sample blocks around each region's busiest tiles.

Limits, stated plainly: the statewide archive is zoom 12, so it has the state's road *classes* but not
street-level topology (the one-way attribute is absent at that zoom); Maharashtra has street-level graphs
for the five city packs only, not for every town. The graph is only as good as OpenStreetMap: one-way
direction is trustworthy (checked against the drive-on-the-left carriageway pairing in Delhi), names are
sparse (14 % of Delhi km).

## P6 / P7 — matching and constraints on real roads (`real_road_map_matching.json`)

`test/nav/real_road_map_matching_test.dart`: a simulated vehicle drives a route along **real streets**
(straight through every crossing, steered like a driver, slowing for bends), through a calibration drive,
120 s with GNSS, then a **60 s GNSS blackout**; the same sensor stream goes to two engines, with and
without the road graph. The sensors are simulated (there is no recorded drive on these roads): this shows
what the road constraint does on real topology, not field accuracy.

| Place | Matched while GNSS on | In map-assisted DR during blackout | Distance to nearest real road (no map → map) | Heading error (no map → map) | Blackout drift, % of distance (no map → map) |
|---|---:|---:|---:|---:|---:|
| Delhi, Dwarka | 85 % | 92 % | 2.1 → 0.4 m | 0.7 → 0.3° | 1.89 → 1.68 |
| Delhi, Rohini | 89 % | 92 % | 2.6 → 0.5 m | 0.7 → 0.2° | 1.47 → 0.72 |
| Delhi, Vasant Kunj | 88 % | 89 % | 1.6 → 1.7 m | 0.5 → 0.6° | 0.42 → 1.31 |
| Mumbai, Andheri | 89 % | 92 % | 2.1 → 0.4 m | 0.6 → 0.3° | 2.97 → 2.35 |

Reading it honestly: matching engages on real topology (parallel roads, junctions, dead ends) and pulls the
estimate onto the road and its heading in three of four places; in one it is neutral-to-slightly-worse
(Vasant Kunj, absolute error still tiny). Along-track drift is not what the map fixes. Matching costs
about 50–80 µs per sensor frame. Pune had no 700 m straight road to calibrate on and is skipped.

**Real sensors on real roads** (three Coventry drives, real IO-VNBD ESP/VBOX data, a real UK OpenStreetMap
archive cut by the phone's own downloader): the road graph lowers the median blackout drift at 60 s from
30.8 % to 23.2 % and at 120 s from 41.3 % to 38.8 %, by a lot on one trip (S4: 46.5 % → 17.3 % at 30 s) and
not at all on another; table and caveats in `iovnbd_engine_and_map_evidence.md` §2.

Two defects only real data exposed, both fixed and pinned by tests: the follower could go round a sliver
of digitising noise forever (`test/road_real_follower_property_test.dart`, which fails within 1 m of
"driving" when the guards are removed), and a graph cut at every junction made the matcher call one road
"two roads too close to call".

A finding to carry forward: on a real winding route the engine's dead reckoning eventually loses speed
under the *simulated* accelerometer bias when the IMU is very quiet at constant speed (estimated 10 m/s
decayed to 0 after ~80 s, error ~550 m). That is the case the AI forward-speed measurement (P1) exists
for, and the reason the blackout here is 60 s, the SIH example length.

## P8 — lane level: scope

**Not achieved and not claimed.** The map data carries no lane count, lane geometry or lane index, the
follower and matcher work at road / carriageway level, and no reference exists here to validate a lane
assignment (IO-VNBD has no lane truth). What *is* demonstrated: road-level constraint and carriageway
selection — a one-way carriageway is honoured, and the drive-on-the-left pairing of opposite one-way lines
is the property the data relies on. Reaching lane level would need lane-attributed map data and a
lateral-position sensor or a lane-truth recording; until then the defensible claim is "constrained to the
correct road/carriageway during GNSS outage".
