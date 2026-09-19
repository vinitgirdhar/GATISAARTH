"""OpenStreetMap input and drivable-road filtering.

Input is Overpass API JSON — what you get from a query like::

    [out:json][timeout:120];
    area["name"="Delhi"]->.a;
    way(area.a)["highway"];
    (._;>;);
    out body;

downloaded to a file and passed to :mod:`maps.tools.graph_builder`. No data is
fetched here and none is bundled: the repository ships no road graph, and the
app reports map matching as unavailable until one is built.
"""

from __future__ import annotations

import json
import re
from typing import Any, Dict, Iterable, List, Optional, Tuple

# Road classes the navigation core understands, keyed by OSM `highway` value.
# Anything not listed is either not drivable or not useful for matching.
HIGHWAY_TO_CLASS = {
    "motorway": "motorway",
    "motorway_link": "motorway",
    "trunk": "trunk",
    "trunk_link": "trunk",
    "primary": "primary",
    "primary_link": "primary",
    "secondary": "secondary",
    "secondary_link": "secondary",
    "tertiary": "tertiary",
    "tertiary_link": "tertiary",
    "residential": "residential",
    "living_street": "residential",
    "unclassified": "unclassified",
    "service": "service",
    "road": "unclassified",
}

_MPH_TO_MPS = 0.44704
_KMH_TO_MPS = 1 / 3.6
_SPEED_PATTERN = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*(mph|km/h|kmh)?\s*$", re.I)


def load_overpass_json(path: str) -> Dict[str, Any]:
    """Reads an Overpass JSON export."""
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def parse_elements(document: Dict[str, Any]) -> Tuple[Dict[int, Tuple[float, float]], List[Dict[str, Any]]]:
    """Splits an Overpass document into a node lookup and a list of ways."""
    elements = document.get("elements")
    if not isinstance(elements, list):
        raise ValueError("Overpass document has no 'elements' list")

    nodes: Dict[int, Tuple[float, float]] = {}
    ways: List[Dict[str, Any]] = []
    for element in elements:
        if not isinstance(element, dict):
            continue
        kind = element.get("type")
        if kind == "node":
            node_id = element.get("id")
            lat = element.get("lat")
            lon = element.get("lon")
            if isinstance(node_id, int) and _is_finite(lat) and _is_finite(lon):
                nodes[node_id] = (float(lat), float(lon))
        elif kind == "way":
            ways.append(element)
    return nodes, ways


def filter_drivable_roads(ways: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Keeps only ways a road vehicle can actually drive on."""
    drivable = []
    for way in ways:
        tags = way.get("tags") or {}
        highway = tags.get("highway")
        if highway not in HIGHWAY_TO_CLASS:
            continue
        # Explicitly closed to all traffic.
        if tags.get("access") in {"no", "private"}:
            continue
        refs = way.get("nodes")
        if not isinstance(refs, list) or len(refs) < 2:
            continue
        drivable.append(way)
    return drivable


def road_class(tags: Dict[str, Any]) -> str:
    return HIGHWAY_TO_CLASS.get(tags.get("highway"), "unclassified")


def parse_max_speed(raw: Optional[str]) -> Optional[float]:
    """Speed limit in m/s, or None.

    None when the tag is absent or is something this parser does not
    understand (``IN:urban``, ``walk``, ``signals``). The navigation core
    treats a missing limit as unknown rather than substituting a default, so
    returning None is the correct answer, not a failure.
    """
    if not isinstance(raw, str):
        return None
    match = _SPEED_PATTERN.match(raw)
    if match is None:
        return None
    value = float(match.group(1))
    unit = (match.group(2) or "").lower()
    if unit == "mph":
        return value * _MPH_TO_MPS
    return value * _KMH_TO_MPS


def parse_one_way(tags: Dict[str, Any]) -> bool:
    value = tags.get("oneway")
    if value in {"yes", "true", "1", "-1"}:
        return True
    # Motorway carriageways are one-way unless tagged otherwise.
    if tags.get("highway") in {"motorway", "motorway_link"} and value is None:
        return True
    return False


def parse_access(tags: Dict[str, Any]) -> List[str]:
    """Which vehicle classes may use the way."""
    allowed = []
    motorcar = tags.get("motorcar", tags.get("motor_vehicle"))
    motorcycle = tags.get("motorcycle", tags.get("motor_vehicle"))
    if motorcar not in {"no", "private"}:
        allowed.append("cars")
    if motorcycle not in {"no", "private"}:
        allowed.append("twoWheelers")
    return allowed


def is_reversed(tags: Dict[str, Any]) -> bool:
    """True when ``oneway=-1`` means the way runs against its node order."""
    return tags.get("oneway") == "-1"


def _is_finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and value == value and abs(value) != float("inf")
