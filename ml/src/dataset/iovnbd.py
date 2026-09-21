"""IO-VNBD ingestion: trip discovery, S/V pairing and canonical column names.

Raw layout (fetched by `fetch_iovnbd.py`):
    <raw_root>/Synchronised V abd S datasets/Categorised IOVNB Dataset/<Category (Driver X)>/[<trip>/]{S-*.csv,V-*.csv}

`S-*` is the smartphone log (10 Hz IMU rows, GPS value held between fixes), `V-*` the vehicle + Racelogic
VBOX log (10 Hz).  "Synchronised" means the authors trimmed both files by hand so that row i of S is
roughly row i of V: row counts match in most trips, but the two streams are up to ~9 s apart and the
phone drops rows, so the pipeline re-aligns them by wall-clock time (`sync.py`); see
`ml/evaluation/metrics/01_dataset_summary.json` for the measurements.

Two label traps: the phone column "GPS SPEED (Kmh)" holds metres per second (median ratio to the VBOX speed
in m/s is 0.98-1.00 over every trip), and the gyroscope column labelled "Pitch" carries the yaw rate.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd

CATEGORISED = "Synchronised V abd S datasets/Categorised IOVNB Dataset"
G0 = 9.80665
EARTH_R = 6378137.0

# canonical name -> regex applied to the upper-cased, stripped header (headers carry mojibake units, so
# only the prefix is matched; a few files differ in the unit characters).
PHONE_COLUMNS = {
    "gps_lat": r"^GPS LATITUDE", "gps_lon": r"^GPS LONGITUDE", "gps_alt": r"^GPS ALTITUDE",
    "gps_speed_ms": r"^GPS SPEED",  # header says Kmh, the values are m/s
    "gps_acc_m": r"^GPS ACCURACY", "gps_heading": r"^GPS ORIENTATION",
    "gps_sats": r"^GPS SATELLITES", "t_ms": r"^TIME SINCE START", "wall": r"^DATE",
    "acc_x": r"^ACCELEROMETER X", "acc_y": r"^ACCELEROMETER Y", "acc_z": r"^ACCELEROMETER Z",
    "grav_x": r"^GRAVITY X", "grav_y": r"^GRAVITY Y", "grav_z": r"^GRAVITY Z",
    "gyro_yaw_col": r"^GYROSCOPE YAW", "gyro_pitch_col": r"^GYROSCOPE PITCH", "gyro_roll_col": r"^GYROSCOPE ROLL",
    "mag_x": r"^MAGNETIC FIELD X", "mag_y": r"^MAGNETIC FIELD Y", "mag_z": r"^MAGNETIC FIELD Z",
}
VBOX_COLUMNS = {
    "v_time_s": r"^TIME SINCE START OF DAY", "v_lat": r"^LATITUDE", "v_lon": r"^LONGITUDE",
    "v_speed_kmh": r"^VELOCITY", "v_heading": r"^HEADING", "v_height_km": r"^HEIGHT",
    "v_yaw_dps": r"^YAW RATE", "v_long_g": r"^INDICATED LONGITUDINAL", "v_lat_g": r"^INDICATED LATERAL",
    "v_ind_speed_kmh": r"^INDICATED VEHICLE SPEED", "v_steer_deg": r"^STEERING ANGLE",
    "v_wheel_fl": r"^WHEEL SPEED FRONT LEFT", "v_wheel_fr": r"^WHEEL SPEED FRONT RIGHT",
    "v_wheel_rl": r"^WHEEL SPEED REAR LEFT", "v_wheel_rr": r"^WHEEL SPEED REAR RIGHT",
    "v_sats": r"^NO OF GPS SATELLITES",
}


@dataclass(frozen=True)
class Trip:
    trip_id: str      # unique, e.g. "Vta02", "M", "Vfa01"
    category: str     # folder prefix, e.g. "Vta"
    driver: str       # "A".."E"
    s_path: Path
    v_path: Path


def _category_and_driver(folder: str) -> tuple[str, str]:
    m = re.match(r"^(.*?)\s*\(Driver ([A-Z])\)\s*$", folder)
    return (m.group(1), m.group(2)) if m else (folder, "?")


def discover_trips(raw_root: Path) -> list[Trip]:
    """Pair every S-*.csv with the V-*.csv in the same folder. Sorted by (category, trip id)."""
    base = Path(raw_root) / CATEGORISED
    trips = []
    for s_path in sorted(base.rglob("*.csv")):
        if not s_path.name.upper().startswith("S-"):
            continue
        partners = [p for p in s_path.parent.glob("*.csv") if p.name.upper().startswith("V-")]
        if len(partners) != 1:
            raise RuntimeError(f"expected exactly one V-*.csv next to {s_path}, found {len(partners)}")
        rel = s_path.relative_to(base).parts
        category, driver = _category_and_driver(rel[0])
        trip_id = s_path.parent.name if len(rel) > 2 else s_path.stem[2:]
        trip_id = re.sub(r"^V-", "", trip_id)  # folder "V-Vfa01" -> "Vfa01"
        trips.append(Trip(trip_id, category, driver, s_path, partners[0]))
    return sorted(trips, key=lambda t: (t.category, t.trip_id))


def parse_wallclock(col) -> tuple[np.ndarray, np.ndarray]:
    """'YYYY-MM-DD HH:MM:SS:mmm' -> (seconds since local midnight, yyyymmdd). NaN where unparseable."""
    d = col.astype(str).str.extract(r"(\d{4})-(\d\d)-(\d\d)[ T](\d\d):(\d\d):(\d\d)[:.](\d{1,3})").astype(float)
    return ((d[3] * 3600 + d[4] * 60 + d[5] + d[6] / 1000).to_numpy(),
            (d[0] * 10000 + d[1] * 100 + d[2]).to_numpy())


def _canonical(df: pd.DataFrame, table: dict[str, str]) -> pd.DataFrame:
    out = {}
    headers = {c: c.strip().upper() for c in df.columns}
    for name, pattern in table.items():
        hit = next((c for c, up in headers.items() if re.search(pattern, up)), None)
        if hit is None:
            continue
        col = df[hit]
        if name == "wall":  # "2019-09-07 09:13:29:506" -> seconds since local midnight + yyyymmdd
            out["wall_s"], out["wall_day"] = parse_wallclock(col)
            continue
        if name.endswith("sats"):  # "18 / 19" (in view / used) -> first number
            col = col.astype(str).str.split("/").str[0]
        out[name] = pd.to_numeric(col, errors="coerce")
    return pd.DataFrame(out)


def read_csv_pair(trip: Trip) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Both files with canonical numeric columns and their ORIGINAL row counts (no trimming here)."""
    s = pd.read_csv(trip.s_path, encoding="latin1")
    v = pd.read_csv(trip.v_path, encoding="latin1")
    return _canonical(s, PHONE_COLUMNS), _canonical(v, VBOX_COLUMNS)


def local_xy(lat_deg, lon_deg, lat0=None, lon0=None):
    """Equirectangular projection to (east, north) metres around the first sample (or lat0/lon0)."""
    lat = np.asarray(lat_deg, float)
    lon = np.asarray(lon_deg, float)
    lat0 = lat[0] if lat0 is None else lat0
    lon0 = lon[0] if lon0 is None else lon0
    east = np.radians(lon - lon0) * EARTH_R * np.cos(np.radians(lat0))
    north = np.radians(lat - lat0) * EARTH_R
    return east, north
