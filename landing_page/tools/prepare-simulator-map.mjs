// Build-time extraction from the app's own offline map. No runtime map service.
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { PMTiles } from "pmtiles";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader as Pbf } from "pbf";
const bytes = await readFile("../frontend/assets/maps/packs/mumbai.pmtiles");
const archive = new PMTiles({
  getKey: () => "local-mumbai",
  getBytes: async (offset, length) => ({
    data: bytes.buffer.slice(
      bytes.byteOffset + offset,
      bytes.byteOffset + offset + length,
    ),
  }),
});
const header = await archive.getHeader();
const z = Math.min(14, header.maxZoom);
const tileX = (lon) => Math.floor(((lon + 180) / 360) * 2 ** z);
const tileY = (lat) =>
  Math.floor(
    ((1 - Math.asinh(Math.tan((lat * Math.PI) / 180)) / Math.PI) / 2) * 2 ** z,
  );
const roads = [],
  buildings = [],
  water = [],
  parks = [],
  seen = new Set();
for (let x = tileX(72.817); x <= tileX(72.849); x++) {
  for (let y = tileY(18.948); y <= tileY(18.915); y++) {
    const tile = await archive.getZxy(z, x, y);
    if (!tile) continue;
    const layers = new VectorTile(new Pbf(tile.data)).layers;
    for (const name of ["roads", "buildings", "water", "landuse"]) {
      const layer = layers[name];
      if (!layer) continue;
      for (let i = 0; i < layer.length; i++) {
        const feature = layer.feature(i).toGeoJSON(x, y, z);
        const props = feature.properties,
          geometry = feature.geometry;
        const round = (coordinates) =>
          coordinates.map((p) => [+p[0].toFixed(6), +p[1].toFixed(6)]);
        if (name === "roads") {
          const lines =
            geometry.type === "LineString"
              ? [geometry.coordinates]
              : geometry.coordinates;
          for (const line of lines) {
            const points = round(line),
              key = JSON.stringify(points);
            if (seen.has(key)) continue;
            seen.add(key);
            roads.push({
              name: props.name || "",
              kind: props.kind || "minor_road",
              points,
            });
          }
        } else {
          if (
            name === "landuse" &&
            !["park", "garden", "grass", "recreation_ground"].includes(
              props.kind,
            )
          )
            continue;
          const polygons =
            geometry.type === "Polygon"
              ? [geometry.coordinates]
              : geometry.type === "MultiPolygon"
                ? geometry.coordinates
                : [];
          for (const polygon of polygons)
            (name === "water"
              ? water
              : name === "landuse"
                ? parks
                : buildings
            ).push(polygon.map(round));
        }
      }
    }
  }
}
await mkdir("public/simulator", { recursive: true });
await writeFile(
  "public/simulator/mumbai.json",
  JSON.stringify({
    attribution: "© OpenStreetMap contributors · Protomaps",
    source: "frontend/assets/maps/packs/mumbai.pmtiles",
    license: "ODbL 1.0",
    roads,
    buildings,
    water,
    parks,
  }),
);
console.log({
  zoom: z,
  roads: roads.length,
  buildings: buildings.length,
  water: water.length,
});
