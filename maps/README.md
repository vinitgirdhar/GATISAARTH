# maps/

Offline road-graph tooling. The app no longer ships a road graph (it builds one on
the phone from the installed vector map packs, see `frontend/lib/core/nav/map/`);
this folder keeps the Python builder whose JSON format
`frontend/test/nav/graph_builder_contract_test.dart` pins.

```bash
python -m maps.tools.graph_builder maps/raw_osm/demo_overpass.json out.json
```

- `tools/osm_parser.py` reads an Overpass API JSON export and keeps drivable ways.
- `tools/graph_builder.py` cuts ways at junctions into nodes and edges with bearings.
