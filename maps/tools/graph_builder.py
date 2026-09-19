"""Road graph construction for the navigation core.

Turns an Overpass JSON export into the graph format
``frontend/lib/core/nav/map/road_graph.dart`` loads::

    {
      "region": "delhi",
      "version": 1,
      "nodes": [{"id": 1, "lat": 28.6, "lon": 77.2}, ...],
      "edges": [{
        "id": 10, "from": 1, "to": 2,
        "polyline": [lat0, lon0, lat1, lon1, ...],
        "class": "primary", "oneWay": true, "maxSpeedMps": 16.7,
        "tunnel": false, "bridge": false,
        "access": ["cars", "twoWheelers"], "name": "NH-48"
      }, ...]
    }

Usage::

    python -m maps.tools.graph_builder overpass.json maps/processed_graphs/delhi.json --region delhi

The repository deliberately ships **no** graph data. Until a real region is
built and placed in the app's assets, map matching reports itself unavailable
rather than matching against nothing.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter
from typing import Any, Dict, List, Optional, Tuple

try:  # Support both `python -m maps.tools.graph_builder` and direct execution.
    from . import osm_parser
except ImportError:  # pragma: no cover - only hit when run as a loose script
    import osm_parser  # type: ignore


EARTH_RADIUS_M = 6_371_008.8


def build_graph(
    document: Dict[str, Any],
    region: str = "",
    version: int = 1,
    min_edge_length_m: float = 1.0,
) -> Dict[str, Any]:
    """Builds the graph from an Overpass document."""
    node_coords, ways = osm_parser.parse_elements(document)
    drivable = osm_parser.filter_drivable_roads(ways)

    # A node shared by two or more ways is a junction; so is any way endpoint.
    usage: Counter = Counter()
    for way in drivable:
        refs = way["nodes"]
        for ref in refs:
            usage[ref] += 1
        # Endpoints always split, even when only one way touches them.
        usage[refs[0]] += 1
        usage[refs[-1]] += 1

    edges: List[Dict[str, Any]] = []
    used_nodes: Dict[int, Tuple[float, float]] = {}
    next_edge_id = 1

    for way in drivable:
        tags = way.get("tags") or {}
        refs = [ref for ref in way["nodes"] if ref in node_coords]
        if len(refs) < 2:
            continue
        if osm_parser.is_reversed(tags):
            refs = list(reversed(refs))

        segment: List[int] = [refs[0]]
        for ref in refs[1:]:
            segment.append(ref)
            if usage[ref] >= 2 or ref == refs[-1]:
                edge = _make_edge(
                    edge_id=next_edge_id,
                    segment=segment,
                    node_coords=node_coords,
                    tags=tags,
                    min_edge_length_m=min_edge_length_m,
                )
                if edge is not None:
                    edges.append(edge)
                    used_nodes[segment[0]] = node_coords[segment[0]]
                    used_nodes[segment[-1]] = node_coords[segment[-1]]
                    next_edge_id += 1
                segment = [ref]

    nodes = [
        {"id": node_id, "lat": coords[0], "lon": coords[1]}
        for node_id, coords in sorted(used_nodes.items())
    ]
    return {"region": region, "version": version, "nodes": nodes, "edges": edges}


def _make_edge(
    edge_id: int,
    segment: List[int],
    node_coords: Dict[int, Tuple[float, float]],
    tags: Dict[str, Any],
    min_edge_length_m: float,
) -> Optional[Dict[str, Any]]:
    if len(segment) < 2:
        return None
    polyline: List[float] = []
    for ref in segment:
        lat, lon = node_coords[ref]
        polyline.extend((lat, lon))
    if polyline_length_m(polyline) < min_edge_length_m:
        return None

    edge: Dict[str, Any] = {
        "id": edge_id,
        "from": segment[0],
        "to": segment[-1],
        "polyline": [round(value, 7) for value in polyline],
        "class": osm_parser.road_class(tags),
        "oneWay": osm_parser.parse_one_way(tags),
        "tunnel": tags.get("tunnel") in {"yes", "building_passage"},
        "bridge": tags.get("bridge") == "yes",
        "access": osm_parser.parse_access(tags),
    }
    speed = osm_parser.parse_max_speed(tags.get("maxspeed"))
    if speed is not None:
        edge["maxSpeedMps"] = round(speed, 2)
    name = tags.get("name")
    if isinstance(name, str) and name:
        edge["name"] = name
    return edge


def polyline_length_m(polyline: List[float]) -> float:
    """Length of a flat ``[lat, lon, ...]`` polyline, in metres."""
    total = 0.0
    for i in range(0, len(polyline) - 3, 2):
        total += haversine_m(
            polyline[i], polyline[i + 1], polyline[i + 2], polyline[i + 3]
        )
    return total


def haversine_m(lat0: float, lon0: float, lat1: float, lon1: float) -> float:
    phi0 = math.radians(lat0)
    phi1 = math.radians(lat1)
    dphi = phi1 - phi0
    dlambda = math.radians(lon1 - lon0)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi0) * math.cos(phi1) * math.sin(dlambda / 2) ** 2
    )
    return 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(a)))


def summarise(graph: Dict[str, Any]) -> str:
    total_length = sum(polyline_length_m(e["polyline"]) for e in graph["edges"])
    classes = Counter(e["class"] for e in graph["edges"])
    named = sum(1 for e in graph["edges"] if e.get("name"))
    with_speed = sum(1 for e in graph["edges"] if "maxSpeedMps" in e)
    lines = [
        f"region      {graph['region'] or '(unnamed)'}",
        f"nodes       {len(graph['nodes'])}",
        f"edges       {len(graph['edges'])}",
        f"length      {total_length / 1000:.1f} km",
        f"named       {named}",
        f"with speed  {with_speed}",
        "classes     " + ", ".join(f"{k}={v}" for k, v in classes.most_common()),
    ]
    return "\n".join(lines)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("input", help="Overpass API JSON export")
    parser.add_argument("output", help="where to write the graph JSON")
    parser.add_argument("--region", default="", help="region name to record")
    parser.add_argument("--version", type=int, default=1)
    args = parser.parse_args(argv)

    document = osm_parser.load_overpass_json(args.input)
    graph = build_graph(document, region=args.region, version=args.version)
    if not graph["edges"]:
        print("No drivable roads found — refusing to write an empty graph.",
              file=sys.stderr)
        return 1

    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(graph, handle, separators=(",", ":"))
    print(summarise(graph))
    return 0


def _self_check() -> None:
    """A tiny end-to-end build, so the splitting logic cannot rot unnoticed."""
    document = {
        "elements": [
            {"type": "node", "id": 1, "lat": 28.6000, "lon": 77.2000},
            {"type": "node", "id": 2, "lat": 28.6045, "lon": 77.2000},
            {"type": "node", "id": 3, "lat": 28.6090, "lon": 77.2000},
            {"type": "node", "id": 4, "lat": 28.6045, "lon": 77.2051},
            {
                "type": "way",
                "id": 100,
                "nodes": [1, 2, 3],
                "tags": {
                    "highway": "primary",
                    "name": "North Road",
                    "maxspeed": "60",
                },
            },
            {
                "type": "way",
                "id": 101,
                "nodes": [2, 4],
                "tags": {"highway": "residential", "oneway": "yes"},
            },
            {"type": "way", "id": 102, "nodes": [1, 4], "tags": {"highway": "footway"}},
        ]
    }
    graph = build_graph(document, region="self-check")

    # The through road is split at the junction node 2.
    assert len(graph["edges"]) == 3, graph["edges"]
    ids = {(e["from"], e["to"]) for e in graph["edges"]}
    assert ids == {(1, 2), (2, 3), (2, 4)}, ids

    # The footway is dropped.
    assert all(e["class"] != "footway" for e in graph["edges"])

    north = next(e for e in graph["edges"] if (e["from"], e["to"]) == (1, 2))
    assert north["name"] == "North Road"
    assert north["class"] == "primary"
    assert abs(north["maxSpeedMps"] - 16.67) < 0.02, north["maxSpeedMps"]
    assert north["oneWay"] is False
    assert set(north["access"]) == {"cars", "twoWheelers"}
    assert abs(polyline_length_m(north["polyline"]) - 500) < 10

    branch = next(e for e in graph["edges"] if (e["from"], e["to"]) == (2, 4))
    assert branch["oneWay"] is True

    # Unparseable speed tags stay absent rather than becoming a default.
    assert osm_parser.parse_max_speed("IN:urban") is None
    assert osm_parser.parse_max_speed(None) is None
    assert abs(osm_parser.parse_max_speed("30 mph") - 13.41) < 0.02

    # Only junction and endpoint nodes are kept.
    assert {n["id"] for n in graph["nodes"]} == {1, 2, 3, 4}
    print("graph_builder self-check passed")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-check":
        _self_check()
    else:
        raise SystemExit(main())
