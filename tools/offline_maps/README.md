# Offline maps

The app draws its map from OpenStreetMap **vector tiles stored on the phone**, so
it works with no connection and stays sharp at any zoom. Each area is one
archive (a PMTiles file), and the phone downloads only the areas the person
wants:

| Map | Area | Detail | Size |
|---|---|---|---|
| `delhi-ncr` | Delhi, Gurugram, Noida, Faridabad, part of Ghaziabad | every street, zoom 15 | 37 MB |
| `maharashtra-state` | the whole state | roads, towns, coast, zoom 12 | 79 MB |
| `mumbai` | Mumbai, Thane, Navi Mumbai | every street, zoom 15 | 26 MB |
| `pune` | Pune, Pimpri-Chinchwad | every street, zoom 15 | 17 MB |
| `nagpur` | Nagpur | every street, zoom 15 | 5 MB |
| `nashik` | Nashik | every street, zoom 15 | 4 MB |
| `sambhajinagar` | Chhatrapati Sambhajinagar | every street, zoom 15 | 3 MB |

Data: (c) OpenStreetMap contributors (ODbL), from the Protomaps daily build.

## How a phone gets them

* **Delhi NCR ships inside the app** (`frontend/assets/maps/packs/`, stored
  uncompressed in the APK and read in place - no second copy on the phone), so a
  fresh install has a working offline map of Delhi.
* **Everything else is downloaded on demand**, inside the app:
  * Profile > Offline Maps lists every area with a Download / Delete button.
  * When the first GPS position is in an area whose maps are missing, the app
    asks once ("Save maps for Pune?") and starts nothing until the person taps
    Download. "Not now" asks again after 3 days, "Do not ask again" never.
* A download cuts the area out of the newest Protomaps planet build
  (`build.protomaps.com/<date>.pmtiles`, 138 GB) with HTTP range requests, the
  same thing `pmtiles extract` does, in Dart (`RegionExtractor`,
  `PmTilesWriter`). Only the area's bytes cross the network. The result is an
  ordinary PMTiles file: `pmtiles verify` accepts it.
* Files are written as `<id>.pmtiles.part`, verified, then renamed, so the map
  never sees half a file. Deleting a map deletes the file.

Where files live on Android:

| Origin | Path | Removable |
|---|---|---|
| bundled | inside the APK | no |
| downloaded | `<app files>/offline_maps/<id>.pmtiles` | yes |
| hand-copied (testing) | `/sdcard/Android/data/com.gatisaarth.app/files/offline_maps/` | yes; wins over the others |

## Change or add an area

1. Add an `OfflinePack` (and put it in a region) in
   `frontend/lib/core/platform/maps/offline_catalog.dart`.
2. Mirror its row in `PACKS` in `build_offline_maps.py`. `flutter test
   test/offline_catalog_test.dart` fails if the two disagree.

## `build_offline_maps.py` (developer tool)

Not needed to run the app. It cuts the same archives on a PC with the official
[`pmtiles` CLI](https://github.com/protomaps/go-pmtiles/releases), for bundling
another area into an APK or copying archives onto a test phone:

```
python tools/offline_maps/build_offline_maps.py --pmtiles C:/path/to/pmtiles.exe --dry-run
python tools/offline_maps/build_offline_maps.py --pmtiles C:/path/to/pmtiles.exe pune
adb push pune.pmtiles /sdcard/Android/data/com.gatisaarth.app/files/offline_maps/
```

The `.pmtiles` files under `frontend/assets/maps/packs/` are git-ignored (big); an
app built without them still runs, the map then uses cached and online tiles
until an area is downloaded.

## Reading, drawing, styling

Pure Dart: `pmtiles` (reading), `vector_map_tiles` (drawing, in isolates in a
release build), Protomaps' light and dark styles adapted by `BasemapStyle`. That
class exists because the renderer cannot parse Protomaps' label rules (no street
names at all) and because `ProtomapsThemes` gives every style the id `default`,
under which the renderer caches finished tiles on disk - light tiles in dark
mode. Every style now has its own id and a `revision`.
