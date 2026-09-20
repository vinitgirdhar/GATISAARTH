#!/usr/bin/env python3
"""Cut the app's offline map archives out of the Protomaps OpenStreetMap build.

Each archive is one PMTiles file of vector tiles for a bounding box. The tool
that does the cutting is the official `pmtiles` command line program
(https://github.com/protomaps/go-pmtiles/releases): it reads the huge daily
planet build with HTTP range requests and downloads only the bytes for the box,
about 171 MB for everything below.

    python tools/offline_maps/build_offline_maps.py --pmtiles C:/tools/pmtiles.exe
    python tools/offline_maps/build_offline_maps.py --dry-run          # sizes only
    python tools/offline_maps/build_offline_maps.py delhi-ncr pune     # a subset

The archives land in frontend/assets/maps/packs/ (git-ignored) and are bundled
into the APK on the next build. The boxes here must match
frontend/lib/core/platform/maps/offline_catalog.dart; `flutter test` checks it.

Map data: (c) OpenStreetMap contributors, ODbL. Basemap schema: Protomaps.
"""

import argparse
import json
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

# id, west, south, east, north, maxzoom
PACKS = [
    ("delhi-ncr", 76.83, 28.38, 77.45, 28.90, 15),
    ("maharashtra-state", 72.60, 15.60, 80.90, 22.10, 12),
    ("mumbai", 72.72, 18.85, 73.30, 19.45, 15),
    ("pune", 73.65, 18.35, 74.05, 18.70, 15),
    ("nagpur", 78.95, 20.98, 79.25, 21.28, 15),
    ("nashik", 73.68, 19.90, 73.92, 20.08, 15),
    ("sambhajinagar", 75.22, 19.78, 75.42, 19.95, 15),
]

BUILDS_INDEX = "https://build-metadata.protomaps.dev/builds.json"
BUILD_URL = "https://build.protomaps.com/{build}.pmtiles"


def latest_build() -> str:
    with urllib.request.urlopen(BUILDS_INDEX, timeout=30) as response:
        builds = json.load(response)
    return builds[-1]["key"].removesuffix(".pmtiles")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("only", nargs="*", help="pack ids to build (default all)")
    parser.add_argument("--pmtiles", default="pmtiles", help="path to the pmtiles CLI")
    parser.add_argument("--build", help="Protomaps build, YYYYMMDD (default latest)")
    parser.add_argument(
        "--out",
        default=str(Path(__file__).resolve().parents[2] / "frontend/assets/maps/packs"),
    )
    parser.add_argument("--dry-run", action="store_true", help="only print sizes")
    args = parser.parse_args()

    if shutil.which(args.pmtiles) is None and not Path(args.pmtiles).is_file():
        print(f"pmtiles CLI not found: {args.pmtiles}", file=sys.stderr)
        return 2
    wanted = set(args.only)
    unknown = wanted - {p[0] for p in PACKS}
    if unknown:
        print(f"unknown pack ids: {sorted(unknown)}", file=sys.stderr)
        return 2

    build = args.build or latest_build()
    source = BUILD_URL.format(build=build)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    print(f"source: {source}\noutput: {out}")

    for pack_id, west, south, east, north, max_zoom in PACKS:
        if wanted and pack_id not in wanted:
            continue
        target = out / f"{pack_id}.pmtiles"
        command = [
            args.pmtiles, "extract", source, str(target),
            f"--bbox={west},{south},{east},{north}", f"--maxzoom={max_zoom}",
        ]
        if args.dry_run:
            command.append("--dry-run")
        print("\n>", " ".join(command))
        result = subprocess.run(command)
        if result.returncode != 0:
            return result.returncode
    print(f"\nBuild date to record in offline_catalog.dart (dataBuild): {build}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
