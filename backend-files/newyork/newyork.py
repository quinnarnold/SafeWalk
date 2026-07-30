"""New York City crime KDE surface generation and safe routing evaluation (time-binned).

Downloads crime data from NYC Open Data (SODA2 API), builds a time-binned
KDE risk surface (4 bins x 6 hours) on the street network, and runs a
Pareto sweep comparing risk-averse routes against shortest paths using
holdout month incidents.
"""

import argparse
import copy
import math
import random
import time
from pathlib import Path

import geopandas as gpd
import networkx as nx
import numpy as np
import osmnx as ox
import pandas as pd
import requests
from scipy.spatial import KDTree
from scipy.stats import gaussian_kde
from shapely import wkt
from shapely.geometry import LineString
from shapely.ops import unary_union
from tqdm.auto import tqdm

try:
    from shapely.ops import substring as _substring
    HAS_SUBSTRING = True
except Exception:
    HAS_SUBSTRING = False

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CITY = "New York, New York, USA"
SCRIPT_DIR = Path(__file__).resolve().parent
BASE_DIR = SCRIPT_DIR / "files"
GRAPH_PATH = BASE_DIR / "newyork_split.graphml"
CRS_UTM = 32618
MAX_EDGE_SEGMENT_M = 100.0
FILTER_STREET_CRIMES = True
KDE_BANDWIDTH_DEGREES = 0.0045

API_HISTORIC_URL = "https://data.cityofnewyork.us/resource/qgea-i56i.json"
API_YTD_URL = "https://data.cityofnewyork.us/resource/5uac-w243.json"
API_COLUMNS = "cmplnt_num,cmplnt_fr_dt,cmplnt_fr_tm,ofns_desc,pd_desc,law_cat_cd,boro_nm,addr_pct_cd,prem_typ_desc,latitude,longitude,ky_cd"

MIN_NET_DIST_M = 1000
MAX_NET_DIST_M = 5000
EUCLID_MIN_M = 600
EUCLID_MAX_M = 4000
N_HOTSPOT_PAIRS = 500
N_RANDOM_PAIRS = 500
CORRIDOR_RADIUS_M = 50
PARETO_ALPHAS = [0, 25000, 50000, 75000, 100000, 150000, 200000, 250000, 350000, 500000, 750000]
BINS_TO_TEST = [0, 1, 2, 3]

VIOLENT_TYPES = {
    "FELONY ASSAULT",
    "ASSAULT 3 & RELATED OFFENSES",
    "ROBBERY",
    "MURDER & NON-NEGL. MANSLAUGHTER",
    "KIDNAPPING & RELATED OFFENSES",
    "ARSON",
    "DANGEROUS WEAPONS",
    "HOMICIDE-NEGLIGENT-VEHICLE",
    "HOMICIDE-NEGLIGENT,UNCLASSIFIE",
}

SEXUAL_TYPES = {
    "SEX CRIMES",
    "RAPE",
    "PROSTITUTION & RELATED OFFENSES",
}

STREET_LOCATIONS = {
    "STREET",
    "TRANSIT - NYC SUBWAY",
    "TRANSIT FACILITY (OTHER)",
    "PARK/PLAYGROUND",
    "PARKING LOT/GARAGE (PUBLIC)",
    "PARKING LOT/GARAGE (PRIVATE)",
    "HIGHWAY/PARKWAY",
    "BUS (NYC TRANSIT)",
    "BUS STOP",
    "BUS TERMINAL",
    "BUS (OTHER)",
    "GAS STATION",
    "OPEN AREAS (OPEN LOTS)",
    "BRIDGE",
    "TUNNEL",
    "TAXI (LIVERY LICENSED)",
    "TAXI (YELLOW LICENSED)",
    "TAXI/LIVERY (UNLICENSED)",
    "FERRY/FERRY TERMINAL",
    "MARINA/PIER",
    "TRAMWAY",
    "CONSTRUCTION SITE",
}

hotspot_bboxes = [
    {"name": "times_square",
     "min_lon": -73.990, "max_lon": -73.981,
     "min_lat": 42.752, "max_lat": 40.762},
    {"name": "east_harlem",
     "min_lon": -73.950, "max_lon": -73.932,
     "min_lat": 40.792, "max_lat": 40.808},
    {"name": "bed_stuy",
     "min_lon": -73.955, "max_lon": -73.928,
     "min_lat": 40.678, "max_lat": 40.695},
    {"name": "brownsville",
     "min_lon": -73.922, "max_lon": -73.900,
     "min_lat": 40.655, "max_lat": 40.670},
    {"name": "south_bronx",
     "min_lon": -73.925, "max_lon": -73.900,
     "min_lat": 40.815, "max_lat": 40.830},
    {"name": "east_new_york",
     "min_lon": -73.893, "max_lon": -73.865,
     "min_lat": 40.655, "max_lat": 40.675},
]


# ---------------------------------------------------------------------------
# Graph building
# ---------------------------------------------------------------------------

def split_long_edges(G, max_seg_m=100.0):
    """Return a new graph where any edge longer than max_seg_m is split."""
    G_proj = ox.project_graph(G)
    existing_nodes = set(G_proj.nodes)
    next_node = -1
    while next_node in existing_nodes:
        next_node -= 1

    edges_to_remove = []
    edges_to_add = []

    for u, v, key, data in list(G_proj.edges(keys=True, data=True)):
        geom = data.get("geometry")
        if geom is None:
            x1, y1 = G_proj.nodes[u]["x"], G_proj.nodes[u]["y"]
            x2, y2 = G_proj.nodes[v]["x"], G_proj.nodes[v]["y"]
            geom = LineString([(x1, y1), (x2, y2)])

        length = geom.length
        if length <= max_seg_m:
            data["geometry"] = geom
            data["length"] = float(length)
            continue

        edges_to_remove.append((u, v, key))
        n_seg = int(np.ceil(length / max_seg_m))
        if n_seg < 2:
            n_seg = 2

        distances = [length * i / n_seg for i in range(n_seg + 1)]
        points = [geom.interpolate(d) for d in distances]
        split_points = points[1:-1]

        node_seq = [u]
        for p in split_points:
            nid = next_node
            next_node -= 1
            G_proj.add_node(nid, x=p.x, y=p.y)
            node_seq.append(nid)
        node_seq.append(v)

        for i, (a, b) in enumerate(zip(node_seq[:-1], node_seq[1:])):
            start_dist = distances[i]
            end_dist = distances[i + 1]
            if HAS_SUBSTRING:
                part_geom = _substring(geom, start_dist, end_dist, normalized=False)
            else:
                seg_len = end_dist - start_dist
                num_points = max(2, int(seg_len / 10.0))
                seg_dists = np.linspace(start_dist, end_dist, num_points)
                coords = [geom.interpolate(d).coords[0] for d in seg_dists]
                part_geom = LineString(coords)

            new_data = copy.deepcopy(data)
            new_data["geometry"] = part_geom
            new_data["length"] = float(part_geom.length)
            edges_to_add.append((a, b, new_data))

    print(f"Removing {len(edges_to_remove)} edges, adding {len(edges_to_add)} edges")

    for (u, v, key) in edges_to_remove:
        if G_proj.has_edge(u, v, key):
            G_proj.remove_edge(u, v, key)
    for (u, v, d) in edges_to_add:
        G_proj.add_edge(u, v, **d)

    G_small = ox.project_graph(G_proj, to_crs="EPSG:4326")
    return G_small


def drop_osmid(G):
    """Remove osmid attributes from graph, nodes, and edges."""
    G = G.copy()
    G.graph.pop("osmid", None)
    for _, d in G.nodes(data=True):
        d.pop("osmid", None)
    for _, _, _, d in G.edges(keys=True, data=True):
        d.pop("osmid", None)
    return G


def load_graph(graphml_path):
    """Load a GraphML file and return a NetworkX MultiDiGraph with proper types."""
    graphml_path = str(graphml_path)
    G_raw = nx.read_graphml(graphml_path)
    G = nx.MultiDiGraph(G_raw)

    for n, d in G.nodes(data=True):
        if "x" in d:
            d["x"] = float(d["x"])
        if "y" in d:
            d["y"] = float(d["y"])
        if "osmid" in d:
            try:
                d["osmid"] = int(float(d["osmid"]))
            except Exception:
                d["osmid"] = str(d["osmid"])

    for u, v, k, d in G.edges(data=True, keys=True):
        if "geometry" in d and isinstance(d["geometry"], str):
            d["geometry"] = wkt.loads(d["geometry"])
        if "length" in d:
            try:
                d["length"] = float(d["length"])
            except Exception:
                pass

    return G


def build_or_load_graph():
    """Load the graph from disk, or download and build it if missing."""
    if GRAPH_PATH.exists():
        print(f"Loading existing graph from {GRAPH_PATH}")
        return load_graph(GRAPH_PATH)

    print(f"Graph not found at {GRAPH_PATH}, downloading from OSMnx...")
    G = ox.graph_from_place(CITY, network_type="walk", simplify=True)
    G_split = split_long_edges(G, max_seg_m=MAX_EDGE_SEGMENT_M)

    GRAPH_PATH.parent.mkdir(parents=True, exist_ok=True)

    G_clean = drop_osmid(G)
    G_split_clean = drop_osmid(G_split)

    raw_path = GRAPH_PATH.with_name(GRAPH_PATH.name.replace("_split.graphml", ".graphml"))
    ox.save_graphml(G_clean, str(raw_path))
    ox.save_graphml(G_split_clean, str(GRAPH_PATH))

    print(f"Saved split graph to {GRAPH_PATH}")
    return load_graph(GRAPH_PATH)


# ---------------------------------------------------------------------------
# Data fetching
# ---------------------------------------------------------------------------

def fetch_date_range(base_url, start, end, batch_size=25000, max_retries=5, initial_delay=5):
    """Fetch crime records for a date range from NYC Open Data."""
    all_records = []
    offset = 0
    retries = 0

    while True:
        try:
            params = {
                "$select": API_COLUMNS,
                "$where": f"cmplnt_fr_dt >= '{start}' AND cmplnt_fr_dt < '{end}'",
                "$order": "cmplnt_num",
                "$limit": batch_size,
                "$offset": offset,
            }
            resp = requests.get(base_url, params=params, timeout=120)
            resp.raise_for_status()
            records = resp.json()

            if not records:
                break
            all_records.extend(records)
            offset += batch_size
            print(f"  {start[:7]}: downloaded {len(all_records)} records so far...")
            retries = 0

            if len(records) < batch_size:
                break
        except (requests.exceptions.ReadTimeout, requests.exceptions.ConnectionError) as e:
            if retries < max_retries:
                delay = initial_delay * (2 ** retries)
                print(f"Request failed at offset {offset}. "
                      f"Retrying in {delay}s ({retries + 1}/{max_retries})...")
                time.sleep(delay)
                retries += 1
            else:
                raise e

    return all_records


def incident_api_for_year(year, live_year):
    """Use YTD only for the live calendar year; completed years use history."""
    return API_YTD_URL if year == live_year else API_HISTORIC_URL


def fetch_crime_data(cutoff_year):
    """Fetch crime data from 2023 to cutoff_year inclusive, monthly to avoid offset limits."""
    live_year = pd.Timestamp.now().year
    if cutoff_year > live_year:
        raise ValueError("Cutoff year cannot be later than the live calendar year")
    years = list(range(2023, cutoff_year + 1))
    dfs = []

    for year in years:
        print(f"\nFetching year {year}...")
        base_url = incident_api_for_year(year, live_year)
        year_records = []
        for month in range(1, 13):
            if month == 12:
                start = f"{year}-12-01"
                end = f"{year + 1}-01-01"
            else:
                start = f"{year}-{month:02d}-01"
                end = f"{year}-{month + 1:02d}-01"
            records = fetch_date_range(base_url, start, end)
            year_records.extend(records)
        print(f"Year {year}: {len(year_records):,} total records")
        df_year = pd.DataFrame.from_records(year_records)
        df_year["year"] = year
        dfs.append(df_year)

    df_all = pd.concat(dfs, ignore_index=True)

    df_all["date"] = pd.to_datetime(df_all["cmplnt_fr_dt"], errors="coerce")
    if "cmplnt_fr_tm" in df_all.columns:
        time_parts = df_all["cmplnt_fr_tm"].fillna("00:00:00").str.split(":", expand=True)
        df_all["date"] = df_all["date"] + pd.to_timedelta(
            time_parts[0].astype(int, errors="ignore").fillna(0).astype(int) * 3600 +
            time_parts[1].astype(int, errors="ignore").fillna(0).astype(int) * 60,
            unit="s"
        )
    df_all["latitude"] = pd.to_numeric(df_all["latitude"], errors="coerce")
    df_all["longitude"] = pd.to_numeric(df_all["longitude"], errors="coerce")
    df_all["addr_pct_cd"] = pd.to_numeric(df_all.get("addr_pct_cd"), errors="coerce")
    df_all.dropna(subset=["latitude", "longitude", "date"], how="any", inplace=True)
    df_all = df_all[(df_all["latitude"] != 0) & (df_all["longitude"] != 0)]
    df_all = df_all[
        (df_all["latitude"] > 40.4) & (df_all["latitude"] < 41.0) &
        (df_all["longitude"] > -74.3) & (df_all["longitude"] < -73.6)
    ]

    df_all["is_violent"] = df_all["ofns_desc"].isin(VIOLENT_TYPES).astype(int)
    df_all["hour"] = df_all["date"].dt.hour
    df_all["bin_of_day"] = (df_all["hour"] // 6).astype("int8")
    df_all["prem_typ_desc"] = df_all["prem_typ_desc"].fillna("Other")

    prem_counts = df_all["prem_typ_desc"].value_counts()
    prems_to_replace = prem_counts[prem_counts < 50].index
    df_all["prem_typ_desc"] = df_all["prem_typ_desc"].replace(prems_to_replace, "OTHER")

    if FILTER_STREET_CRIMES:
        before = len(df_all)
        df_all = df_all[df_all["prem_typ_desc"].isin(STREET_LOCATIONS)]
        after = len(df_all)
        print(f"Street-location filter: {before} -> {after} crimes "
              f"({after / before * 100:.1f}% kept)")

    print(f"Total crime records after filtering: {len(df_all):,}")
    return df_all


# ---------------------------------------------------------------------------
# KDE surface
# ---------------------------------------------------------------------------

def build_kde_surface_binned(df_all, edges_gdf, cutoff_date):
    """Build per-bin KDE risk surfaces from violent crimes before cutoff_date.

    Runs a separate KDE for each 6-hour time bin (0-3). Returns a DataFrame
    with columns [edge_id, bin_of_day, kde_risk], matching warmup.py schema.
    """
    df_training = df_all[df_all["date"] < cutoff_date].copy()
    print(f"Total crimes: {len(df_all):,}")
    print(f"Crimes before cutoff ({cutoff_date}): {len(df_training):,}")

    df_violent = df_training[df_training["ofns_desc"].isin(VIOLENT_TYPES)].copy()
    print(f"Violent crimes (pre-cutoff): {len(df_violent):,}")

    edges_gdf = edges_gdf.copy()
    edges_gdf["centroid"] = edges_gdf.geometry.centroid
    edges_gdf["centroid_lat"] = edges_gdf.centroid.y
    edges_gdf["centroid_lon"] = edges_gdf.centroid.x
    edge_centroids = edges_gdf[["centroid_lat", "centroid_lon"]].values
    n_edges = len(edges_gdf)
    print(f"Total edges: {n_edges:,}")

    tree = KDTree(edge_centroids)
    crime_locs = df_violent[["latitude", "longitude"]].values
    _, nearest_edge_indices = tree.query(crime_locs, k=1)

    nearest_edges_df = edges_gdf.iloc[nearest_edge_indices][["u", "v", "key"]].reset_index(drop=True)
    edge_crime_counts = nearest_edges_df.groupby(["u", "v", "key"]).size().reset_index(name="crime_count")

    days_observed = (cutoff_date - df_training["date"].min()).days
    edge_crime_counts["historical_avg_risk"] = edge_crime_counts["crime_count"] / days_observed

    historical_avg_risk = edges_gdf[["u", "v", "key"]].merge(
        edge_crime_counts[["u", "v", "key", "historical_avg_risk"]],
        on=["u", "v", "key"], how="left",
    ).fillna(0)
    historical_mean = historical_avg_risk["historical_avg_risk"].mean()
    print(f"Historical avg mean (for scaling): {historical_mean:.6f}")

    edge_ids = edges_gdf["edge_id"].values
    all_bin_frames = []

    for b in BINS_TO_TEST:
        df_bin = df_violent[df_violent["bin_of_day"] == b]
        print(f"\n  Bin {b}: {len(df_bin):,} violent crimes")

        if len(df_bin) < 10:
            print("    Too few points for KDE, using zeros")
            bin_df = pd.DataFrame({
                "edge_id": edge_ids,
                "bin_of_day": b,
                "kde_risk": 0.0,
            })
            all_bin_frames.append(bin_df)
            continue

        crime_coords = df_bin[["latitude", "longitude"]].values
        kde = gaussian_kde(crime_coords.T, bw_method=KDE_BANDWIDTH_DEGREES)

        kde_scores = np.zeros(n_edges)
        eval_batch = 10000
        for i in range(0, n_edges, eval_batch):
            batch_end = min(i + eval_batch, n_edges)
            kde_scores[i:batch_end] = kde.evaluate(edge_centroids[i:batch_end].T)
            if (i // eval_batch) % 10 == 0:
                print(f"    KDE: {batch_end:,} / {n_edges:,} edges")

        scale_factor = historical_mean / np.mean(kde_scores) if np.mean(kde_scores) > 0 else 1.0
        kde_scores *= scale_factor

        print(f"    Mean: {np.mean(kde_scores):.6f}, Max: {np.max(kde_scores):.6f}")

        bin_df = pd.DataFrame({
            "edge_id": edge_ids,
            "bin_of_day": b,
            "kde_risk": kde_scores,
        })
        all_bin_frames.append(bin_df)

    kde_risk = pd.concat(all_bin_frames, ignore_index=True)
    kde_risk["edge_id"] = kde_risk["edge_id"].astype(np.int32)
    kde_risk["bin_of_day"] = kde_risk["bin_of_day"].astype(np.int8)

    print(f"\nBinned KDE surface: {len(kde_risk):,} rows "
          f"({n_edges} edges x {len(BINS_TO_TEST)} bins)")
    return kde_risk


# ---------------------------------------------------------------------------
# Edges export
# ---------------------------------------------------------------------------

def export_edges_wgs84(edges_gdf, output_path):
    """Export edges GeoDataFrame as WGS84 parquet."""
    edges_export = edges_gdf.copy()
    edges_export["u"] = edges_export["u"].astype(np.int64)
    edges_export["v"] = edges_export["v"].astype(np.int64)
    edges_export["key"] = edges_export["key"].astype(np.int64)
    edges_export["edge_id"] = edges_export["edge_id"].astype(np.int32)

    if "length" in edges_export.columns and "length_m" not in edges_export.columns:
        edges_export["length_m"] = edges_export["length"].astype(np.float32)
    elif "length_m" in edges_export.columns:
        edges_export["length_m"] = edges_export["length_m"].astype(np.float32)
    else:
        edges_export["length_m"] = edges_export.geometry.length.astype(np.float32)

    export_cols = ["u", "v", "key", "edge_id", "length_m", "geometry"]
    for col in ("highway", "foot"):
        if col in edges_export.columns:
            export_cols.append(col)

    edges_final = gpd.GeoDataFrame(
        edges_export[export_cols], geometry="geometry", crs=edges_export.crs,
    )
    if edges_final.crs != "EPSG:4326":
        edges_final = edges_final.to_crs("EPSG:4326")

    edges_final.to_parquet(str(output_path), index=False)
    print(f"Saved edges WGS84: {output_path}")
    print(f"  Shape: {edges_final.shape}, CRS: {edges_final.crs}")


# ---------------------------------------------------------------------------
# Routing helpers
# ---------------------------------------------------------------------------

def _haversine_m(lat1, lon1, lat2, lon2):
    """Great-circle distance in meters between two (lat, lon) points."""
    R = 6_371_000
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2))
         * math.sin(dlon / 2) ** 2)
    return R * 2 * math.asin(math.sqrt(a))


def nodes_in_bbox(G, min_lon, min_lat, max_lon, max_lat):
    """Return node IDs in G whose (x=lon, y=lat) fall inside the bbox."""
    candidate_nodes = []
    for n, data in G.nodes(data=True):
        lon = data.get("x", None)
        lat = data.get("y", None)
        if lon is None or lat is None:
            continue
        if (min_lon <= lon <= max_lon) and (min_lat <= lat <= max_lat):
            candidate_nodes.append(n)
    return candidate_nodes


def _sample_pairs_distance_filtered(G, candidate_nodes, n_pairs,
                                     min_net_dist, max_net_dist,
                                     euclid_min, euclid_max,
                                     seed=42, max_attempts=50_000):
    """Sample OD pairs with network distance in [min_net_dist, max_net_dist]."""
    rng = random.Random(seed)
    candidate_nodes = list(candidate_nodes)
    if len(candidate_nodes) < 2:
        raise ValueError("Need at least 2 candidate nodes.")

    pairs = []
    attempts = 0
    while len(pairs) < n_pairs and attempts < max_attempts:
        attempts += 1
        src, dst = rng.sample(candidate_nodes, 2)

        s_data, d_data = G.nodes[src], G.nodes[dst]
        euc = _haversine_m(s_data["y"], s_data["x"], d_data["y"], d_data["x"])
        if not (euclid_min <= euc <= euclid_max):
            continue

        try:
            net_dist = nx.shortest_path_length(G, src, dst, weight="length")
        except nx.NetworkXNoPath:
            continue
        if min_net_dist <= net_dist <= max_net_dist:
            pairs.append((src, dst))
        if attempts % 5000 == 0:
            print(f"    ... {len(pairs)} pairs after {attempts} attempts")

    if len(pairs) < n_pairs:
        print(f"  Warning: only found {len(pairs)}/{n_pairs} pairs "
              f"after {attempts} attempts")
    return pairs


def build_eval_od_pairs(G, base_seed=42):
    """Build evaluation OD list with network-distance filtering."""
    all_hot_nodes = set()
    for bbox in hotspot_bboxes:
        nodes = nodes_in_bbox(
            G, bbox["min_lon"], bbox["min_lat"],
            bbox["max_lon"], bbox["max_lat"],
        )
        all_hot_nodes.update(nodes)
    print(f"Hotspot candidate nodes: {len(all_hot_nodes):,}")

    print("Sampling hotspot pairs...")
    hotspot_pairs = _sample_pairs_distance_filtered(
        G, list(all_hot_nodes), N_HOTSPOT_PAIRS,
        min_net_dist=MIN_NET_DIST_M, max_net_dist=MAX_NET_DIST_M,
        euclid_min=EUCLID_MIN_M, euclid_max=EUCLID_MAX_M,
        seed=base_seed + 1,
    )
    print(f"  {len(hotspot_pairs)} hotspot pairs")

    print("Sampling random pairs...")
    random_pairs = _sample_pairs_distance_filtered(
        G, list(G.nodes()), N_RANDOM_PAIRS,
        min_net_dist=MIN_NET_DIST_M, max_net_dist=MAX_NET_DIST_M,
        euclid_min=EUCLID_MIN_M, euclid_max=EUCLID_MAX_M,
        seed=base_seed + 2,
    )
    print(f"  {len(random_pairs)} random pairs")

    od_pairs = []
    for src, dst in hotspot_pairs:
        od_pairs.append({"src": src, "dst": dst, "kind": "hotspot"})
    for src, dst in random_pairs:
        od_pairs.append({"src": src, "dst": dst, "kind": "random"})

    rng = random.Random(base_seed + 3)
    rng.shuffle(od_pairs)
    return od_pairs


def od_pairs_cache_path(seed):
    """Return the seed-specific evaluation-pair cache path."""
    return BASE_DIR / f"OD_pairs_seed_{seed}.csv"


def select_edges_for_path(G, node_path, weight_spec):
    """Select the best edge key for each consecutive node pair in a path."""
    edges = []
    for i in range(len(node_path) - 1):
        u, v = node_path[i], node_path[i + 1]
        if G.is_multigraph():
            best_k, best_w = None, float("inf")
            for k, data in G[u][v].items():
                w = (weight_spec(u, v, data) if callable(weight_spec)
                     else data.get(weight_spec, float("inf")))
                try:
                    w = float(w)
                except Exception:
                    w = float(data.get("length_m", 1.0))
                if w < best_w:
                    best_w, best_k = w, k
            edges.append((u, v, best_k))
        else:
            edges.append((u, v, 0))
    return edges


def path_edge_ids(G, edges_uvw):
    """Extract edge_id values from a list of (u, v, key) tuples."""
    eids = []
    for u, v, k in edges_uvw:
        data = G.get_edge_data(u, v, k)
        eid = int(data.get("edge_id", -1))
        if eid >= 0:
            eids.append(eid)
    return eids


def corridor_month_mean_count(corridor_poly, incidents_df, holdout_month):
    """Count incidents within a corridor polygon for a holdout month."""
    if corridor_poly is None or incidents_df.empty:
        return 0.0, 0
    pts = gpd.GeoSeries(
        gpd.points_from_xy(incidents_df["x"], incidents_df["y"]),
        crs=f"EPSG:{CRS_UTM}",
    )
    total = int(pts.within(corridor_poly).sum())
    days = int((holdout_month + pd.offsets.MonthEnd(1)).day)
    return float(total / max(days, 1)), total


# ---------------------------------------------------------------------------
# Routing evaluation
# ---------------------------------------------------------------------------

def build_holdout_incidents(df_all, holdout_month_start, holdout_month_end):
    """Build holdout incidents from raw crime data for the holdout month.

    Filters to violent crimes, projects to UTM, adds bin_of_day.
    Returns a dict mapping bin_of_day -> DataFrame with columns [x, y, bin_of_day].
    """
    df_holdout = df_all[
        (df_all["date"] >= holdout_month_start) &
        (df_all["date"] < holdout_month_end) &
        (df_all["ofns_desc"].isin(VIOLENT_TYPES))
    ].copy()

    print(f"Holdout violent incidents: {len(df_holdout):,} "
          f"({holdout_month_start.strftime('%Y-%m-%d')} to "
          f"{holdout_month_end.strftime('%Y-%m-%d')})")

    if df_holdout.empty:
        return {b: pd.DataFrame(columns=["x", "y", "bin_of_day"]) for b in BINS_TO_TEST}

    gdf = gpd.GeoDataFrame(
        df_holdout,
        geometry=gpd.points_from_xy(df_holdout["longitude"], df_holdout["latitude"]),
        crs="EPSG:4326",
    ).to_crs(f"EPSG:{CRS_UTM}")

    gdf["x"] = gdf.geometry.x
    gdf["y"] = gdf.geometry.y
    gdf["bin_of_day"] = (gdf["date"].dt.hour // 6).astype("int8")

    incidents_cache = {}
    for b in BINS_TO_TEST:
        inc_bin = gdf[gdf["bin_of_day"] == b][["x", "y", "bin_of_day"]].copy()
        incidents_cache[b] = inc_bin
        print(f"  Bin {b}: {len(inc_bin):,} violent incidents")

    return incidents_cache


def run_pareto_sweep(G, edges_gdf, kde_risk_df, incidents_cache,
                     holdout_month_start, seed):
    """Run Pareto alpha sweep using time-binned KDE risk surface."""
    edges_utm = edges_gdf[["edge_id", "geometry"]].copy().to_crs(CRS_UTM)
    edges_utm["edge_id"] = edges_utm["edge_id"].astype(int)

    for n, data in G.nodes(data=True):
        data["x"] = float(data["x"])
        data["y"] = float(data["y"])

    edge_map = edges_gdf[["u", "v", "key", "edge_id", "length_m"]].copy()
    edge_map[["u", "v", "key"]] = (
        edge_map[["u", "v", "key"]].astype(float).astype(int).astype(str)
    )
    lookup = edge_map.set_index(["u", "v", "key"]).to_dict("index")

    missing = 0
    for u, v, k, data in G.edges(keys=True, data=True):
        rec = lookup.get((str(u), str(v), str(k)))
        if rec is not None:
            data["edge_id"] = int(rec["edge_id"])
            data["length_m"] = float(rec["length_m"])
        else:
            data["edge_id"] = -1
            data["length_m"] = float(data.get("length", 1.0))
            missing += 1
    print(f"Patched edge_ids into G (missing: {missing})")

    kde_lookup = (
        kde_risk_df
        .set_index(["edge_id", "bin_of_day"])["kde_risk"]
        .to_dict()
    )

    od_path = od_pairs_cache_path(seed)
    if od_path.exists():
        print(f"Loading existing OD pairs from {od_path}")
        OD_pairs = pd.read_csv(str(od_path))
        OD_pairs["src"] = OD_pairs["src"].astype(str)
        OD_pairs["dst"] = OD_pairs["dst"].astype(str)
    else:
        print("Generating OD pairs...")
        od_list = build_eval_od_pairs(G, base_seed=seed)
        OD_pairs = pd.DataFrame(od_list)
        OD_pairs["src"] = OD_pairs["src"].astype(str)
        OD_pairs["dst"] = OD_pairs["dst"].astype(str)
        OD_pairs.to_csv(str(od_path), index=False)
        print(f"Saved OD pairs to {od_path}")

    nodes_set = set(G.nodes())
    OD_pairs = OD_pairs[
        OD_pairs["src"].isin(nodes_set) & OD_pairs["dst"].isin(nodes_set)
    ].copy()
    print(f"Valid OD pairs: {len(OD_pairs):,}")

    def route_corridor_geom(edge_ids, R_m=CORRIDOR_RADIUS_M):
        segs = edges_utm.loc[edges_utm["edge_id"].isin(edge_ids), "geometry"].values
        if len(segs) == 0:
            return None
        return unary_union(list(segs)).buffer(float(R_m))

    def build_weight_function(alpha, bin_of_day):
        def weight_fn(u, v, data):
            if isinstance(data, dict) and data and isinstance(next(iter(data.values())), dict):
                best = float("inf")
                for k, attr in data.items():
                    eid = int(attr.get("edge_id", -1))
                    length_m = float(attr.get("length_m", attr.get("length", 1.0)))
                    risk = kde_lookup.get((eid, bin_of_day), 0.0)
                    w = length_m + float(alpha) * float(np.log1p(risk))
                    if w < best:
                        best = w
                return best
            eid = int(data.get("edge_id", -1))
            length_m = float(data.get("length_m", data.get("length", 1.0)))
            risk = kde_lookup.get((eid, bin_of_day), 0.0)
            return length_m + float(alpha) * float(np.log1p(risk))
        return weight_fn

    print("\nCaching shortest paths...")
    valid_pairs = OD_pairs[OD_pairs["src"].isin(G.nodes) & OD_pairs["dst"].isin(G.nodes)]
    shortest_path_cache = {}

    for idx, row in tqdm(valid_pairs.iterrows(), total=len(valid_pairs), desc="  Shortest paths"):
        src, dst = str(row["src"]), str(row["dst"])
        try:
            path_nodes = nx.shortest_path(G, src, dst, weight="length_m")
            edges = select_edges_for_path(G, path_nodes, "length_m")
            eids = path_edge_ids(G, edges)
            dist = sum(float(G.get_edge_data(u, v, k)["length_m"]) for u, v, k in edges)
            shortest_path_cache[(src, dst)] = {
                "eids": eids, "dist": dist, "kind": row["kind"],
            }
        except nx.NetworkXNoPath:
            shortest_path_cache[(src, dst)] = None

    valid_cached = sum(1 for v in shortest_path_cache.values() if v is not None)
    print(f"  Cached {valid_cached:,} valid shortest paths")

    R_m = CORRIDOR_RADIUS_M
    print(f"\nBuilding corridors (R={R_m}m)...")
    shortest_with_corridor = {}
    for pair_key, cache in shortest_path_cache.items():
        if cache is None:
            shortest_with_corridor[pair_key] = None
            continue
        corridor = route_corridor_geom(cache["eids"], R_m=R_m)
        shortest_with_corridor[pair_key] = {
            "eids": cache["eids"],
            "dist": cache["dist"],
            "corridor": corridor,
            "kind": cache["kind"],
        }

    shortest_gt = {}
    for b in BINS_TO_TEST:
        inc = incidents_cache[b]
        for pair_key, cache in tqdm(shortest_with_corridor.items(), desc=f"  GT bin {b}"):
            if cache is None:
                continue
            _, true_total = corridor_month_mean_count(
                cache["corridor"], inc, holdout_month_start,
            )
            shortest_gt[(pair_key[0], pair_key[1], b)] = true_total

    holdout_tag = f"{holdout_month_start.year}-{holdout_month_start.month:02d}"
    print(f"\nRunning Pareto sweep (R_m={R_m})...")
    all_results = []

    for alpha in tqdm(PARETO_ALPHAS, desc="  KDE alphas"):
        for b in BINS_TO_TEST:
            inc = incidents_cache[b]
            weight_fn = build_weight_function(alpha, b)

            for pair_key, short_cache in shortest_with_corridor.items():
                if short_cache is None:
                    continue

                src, dst = pair_key
                short_truth = shortest_gt.get((src, dst, b), 0)

                try:
                    if alpha == 0:
                        safe_eids = short_cache["eids"]
                        safe_dist = short_cache["dist"]
                        safe_corridor = short_cache["corridor"]
                    else:
                        path_nodes = nx.shortest_path(G, src, dst, weight=weight_fn)
                        edges = select_edges_for_path(G, path_nodes, weight_fn)
                        safe_eids = path_edge_ids(G, edges)
                        safe_dist = sum(
                            float(G.get_edge_data(u, v, k)["length_m"])
                            for u, v, k in edges
                        )
                        safe_corridor = route_corridor_geom(safe_eids, R_m=R_m)

                    _, safe_truth = corridor_month_mean_count(
                        safe_corridor, inc, holdout_month_start,
                    )

                    all_results.append({
                        "test_month": holdout_tag,
                        "radius_m": R_m,
                        "method": "kde_binned",
                        "alpha": alpha,
                        "bin_of_day": b,
                        "kind": short_cache["kind"],
                        "pct_detour": 100.0 * (safe_dist - short_cache["dist"]) / max(short_cache["dist"], 1e-9),
                        "crimes_avoided": short_truth - safe_truth,
                        "true_short": short_truth,
                        "true_safe": safe_truth,
                    })
                except nx.NetworkXNoPath:
                    continue

    print(f"  {len(all_results):,} evaluations")
    return pd.DataFrame(all_results)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    global BASE_DIR, GRAPH_PATH

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=BASE_DIR)
    parser.add_argument("--cutoff-date", help="Exclusive cutoff date (YYYY-MM-DD)")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    BASE_DIR = args.output_dir.resolve()
    GRAPH_PATH = BASE_DIR / "newyork_split.graphml"
    ox.settings.cache_folder = str(BASE_DIR / "cache")
    random.seed(args.seed)
    np.random.seed(args.seed)
    now = pd.Timestamp(args.cutoff_date) if args.cutoff_date else pd.Timestamp.now()
    cutoff_date = now.normalize().replace(day=1)
    holdout_month_start = cutoff_date - pd.DateOffset(months=1)
    holdout_month_end = cutoff_date
    current_year = now.year

    print(f"Current date: {now.strftime('%Y-%m-%d')}")
    print(f"Cutoff date (exclusive): {cutoff_date}")
    print(f"Holdout month: {holdout_month_start.strftime('%Y-%m')} "
          f"({holdout_month_start} to {holdout_month_end})")
    print(f"Fetching crime data from 2023 to {current_year}")

    G = build_or_load_graph()

    edges_gdf = ox.graph_to_gdfs(G, nodes=False).reset_index()
    edges_gdf["u"] = edges_gdf["u"].astype(np.int64)
    edges_gdf["v"] = edges_gdf["v"].astype(np.int64)
    edges_gdf["key"] = edges_gdf["key"].astype(str)
    edges_gdf["edge_id"] = np.arange(len(edges_gdf), dtype=np.int32)
    print(f"Edges: {len(edges_gdf):,}")

    df_all = fetch_crime_data(current_year)

    # Step 3: Build time-binned KDE surface
    kde_risk = build_kde_surface_binned(df_all, edges_gdf, cutoff_date)
    kde_path = BASE_DIR / "newyork_surface.parquet"
    kde_risk.to_parquet(str(kde_path), index=False)
    print(f"Saved binned KDE surface: {kde_path}")

    edges_path = BASE_DIR / "newyork_edges_wgs84.parquet"
    export_edges_wgs84(edges_gdf, edges_path)

    if "length_m" not in edges_gdf.columns:
        if "length" in edges_gdf.columns:
            edges_gdf["length_m"] = edges_gdf["length"].astype(np.float32)
        else:
            edges_gdf_proj = edges_gdf.to_crs(CRS_UTM)
            edges_gdf["length_m"] = edges_gdf_proj.geometry.length.astype(np.float32)

    incidents_cache = build_holdout_incidents(df_all, holdout_month_start, holdout_month_end)

    results_dir = BASE_DIR / "results"
    results_dir.mkdir(parents=True, exist_ok=True)

    results_df = run_pareto_sweep(
        G, edges_gdf, kde_risk, incidents_cache, holdout_month_start, args.seed,
    )

    if results_df.empty:
        print("\nNo evaluation results produced.")
    else:
        out_path = results_dir / "pareto_frontier.csv"
        results_df.to_csv(str(out_path), index=False)
        print(f"\nSaved: {out_path} ({len(results_df):,} rows)")

        print("\nSummary:")
        print(f"  Holdout month: {results_df['test_month'].unique().tolist()}")
        print(f"  Radius: {results_df['radius_m'].unique().tolist()}")
        print(f"  Alphas: {len(results_df['alpha'].unique())}")
        print(f"  Total evaluations: {len(results_df):,}")


if __name__ == "__main__":
    main()
