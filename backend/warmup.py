# warmup_build_pickle.py
import os
import io
import math
import time
import pickle
import networkx as nx
import igraph as ig
import geopandas as gpd
import pandas as pd
import numpy as np
from sklearn.neighbors import KDTree
from pyproj import Transformer
from shapely.geometry import LineString
from shapely import wkt

LOCAL_DATA_DIR = os.getenv("LOCAL_DATA_DIR", "/app/city_data")
OUTPUT_DATA_DIR = os.getenv("OUTPUT_DATA_DIR", "/app/data")


def read_file_bytes(object_name):
    """Read a generated city artifact from the local build context."""
    local_path = os.path.join(LOCAL_DATA_DIR, object_name)
    if os.path.exists(local_path):
        print(f"[warmup] Reading local file: {local_path}")
        with open(local_path, "rb") as f:
            return f.read()
    raise FileNotFoundError(
        f"Missing city artifact: {local_path}. "
        "Generate it with backend-files or place it in backend/city_data."
    )


# -----------------------------
# Helpers
# -----------------------------
def _nodes_to_4326_if_needed(G):
    n0 = next(iter(G.nodes))
    x0, y0 = float(G.nodes[n0]["x"]), float(G.nodes[n0]["y"])
    if abs(x0) > 1000 or abs(y0) > 1000:
        t = Transformer.from_crs(3857, 4326, always_xy=True).transform
        for n, d in G.nodes(data=True):
            d["x"], d["y"] = t(d["x"], d["y"])

def read_edges_parquet(raw_bytes: bytes) -> gpd.GeoDataFrame:
    gdf = gpd.read_parquet(io.BytesIO(raw_bytes))
    if gdf.crs and str(gdf.crs).upper() not in ("EPSG:4326", "WGS 84"):
        gdf = gdf.to_crs("EPSG:4326")
    return gdf

def read_clean_parquet(raw_bytes: bytes) -> pd.DataFrame:
    return pd.read_parquet(io.BytesIO(raw_bytes))

def build_city_data(city_name, graph_obj, edges_obj, risk_obj):
    t0 = time.time()

    graphml_bytes = read_file_bytes(graph_obj)
    G_raw = nx.read_graphml(io.BytesIO(graphml_bytes))

    if isinstance(G_raw, nx.MultiDiGraph):
        G = G_raw
    else:
        G = nx.MultiDiGraph(G_raw)

    for n, data in G.nodes(data=True):
        try:
            data["x"] = float(data["x"])
            data["y"] = float(data["y"])
        except (TypeError, ValueError):
            pass
        if "osmid" in data:
            try:
                data["osmid"] = int(data["osmid"])
            except (TypeError, ValueError):
                pass

    for u, v, k, data in G.edges(keys=True, data=True):
        geom = data.get("geometry")
        if geom is not None and isinstance(geom, str):
            try:
                data["geometry"] = wkt.loads(geom)
            except Exception:
                data["geometry"] = None

        if "length" in data:
            try:
                data["length"] = float(data["length"])
            except (TypeError, ValueError):
                data["length"] = 1.0

    _nodes_to_4326_if_needed(G)

    edges_bytes = read_file_bytes(edges_obj)
    risk_bytes = read_file_bytes(risk_obj)
    edges_gdf = read_edges_parquet(edges_bytes)
    risk_surface = read_clean_parquet(risk_bytes)

    risk_lookup_dict = (
        risk_surface
        .set_index(["edge_id", "bin_of_day"])["kde_risk"]
        .to_dict()
    )

    want = ["u", "v", "key", "edge_id", "length_m", "geometry", "highway", "foot"]
    have = [c for c in want if c in edges_gdf.columns]
    edge_map = edges_gdf[have]
    lookup = edge_map.set_index(["u", "v", "key"]).to_dict("index")

    for u, v, k, data in G.edges(keys=True, data=True):
        try:
            rec = lookup[(int(u), int(v), int(k))]
            data["edge_id"]  = int(rec["edge_id"])
            data["length_m"] = float(rec["length_m"])
            if rec.get("geometry") is not None:
                data["geometry"] = rec["geometry"]
            if "highway" in rec: data["highway"] = rec["highway"]
            if "foot"    in rec: data["foot"]    = rec["foot"]
        except KeyError:
            data.setdefault("edge_id", -1)
            data.setdefault("length_m", float(data.get("length", 1.0)))

    edge_points, edge_refs = [], []
    for u, v, k, _d in G.edges(keys=True, data=True):
        x1, y1 = G.nodes[u]["x"], G.nodes[u]["y"]
        x2, y2 = G.nodes[v]["x"], G.nodes[v]["y"]
        edge_points.append(((x1 + x2) / 2, (y1 + y2) / 2))
        edge_refs.append((u, v, k))
    edge_tree = KDTree(np.array(edge_points))

    t_ig = time.time()
    ig_graph = ig.Graph.from_networkx(G)
    print(f"[warmup] igraph conversion: {ig_graph.vcount()} vertices, "
          f"{ig_graph.ecount()} edges in {time.time()-t_ig:.2f}s")

    nx_node_to_idx = {v["_nx_name"]: v.index for v in ig_graph.vs}

    n_edges = ig_graph.ecount()
    risk_array = np.zeros((n_edges, 4), dtype=np.float64)
    for i, e in enumerate(ig_graph.es):
        eid = e["edge_id"] if e["edge_id"] is not None else -1
        for b in range(4):
            risk_array[i, b] = risk_lookup_dict.get((eid, b), 0.0)

    print(f"[warmup] risk_array shape: {risk_array.shape}")

    CITY_ALPHAS = {
        "atlanta":      (150_000.0, 350_000.0),
        "boston":        ( 50_000.0, 100_000.0),
        "chicago":      (100_000.0, 250_000.0),
        "newyork":      ( 75_000.0, 200_000.0),
        "philadelphia": ( 25_000.0,  75_000.0),
        "seattle":      ( 50_000.0, 100_000.0),
    }
    MODERATE_ALPHA, SAFEST_ALPHA = CITY_ALPHAS.get(city_name, (75_000.0, 200_000.0))
    print(f"[warmup] alphas for {city_name}: moderate={MODERATE_ALPHA}, safest={SAFEST_ALPHA}")

    length_weights = np.array(
        [e["length_m"] if e["length_m"] is not None else 1.0 for e in ig_graph.es],
        dtype=np.float64,
    )

    precomputed_weights = {}
    for bin_val in range(4):
        precomputed_weights[(bin_val, "moderate")] = length_weights + MODERATE_ALPHA * np.log1p(risk_array[:, bin_val])
        precomputed_weights[(bin_val, "safest")] = length_weights + SAFEST_ALPHA * np.log1p(risk_array[:, bin_val])

    print(f"[warmup] precomputed {len(precomputed_weights)} weight vectors")

    city_data = {
        "ig_graph": ig_graph,
        "nx_node_to_idx": nx_node_to_idx,
        "length_weights": length_weights,
        "precomputed_weights": precomputed_weights,
        "risk_array": risk_array,
        "edge_tree": edge_tree,
        "edge_refs": edge_refs,
    }

    print(f"[warmup] build_city_data done in {time.time()-t0:.2f}s")
    return city_data

def save_city_pickle_local(city_name, city_data, filename="city_data.pkl"):
    out_dir = os.path.join(OUTPUT_DATA_DIR, city_name)
    os.makedirs(out_dir, exist_ok=True)
    local_path = os.path.join(out_dir, filename)
    with open(local_path, "wb") as f:
        pickle.dump(city_data, f, protocol=pickle.HIGHEST_PROTOCOL)
    print(f"[warmup] Wrote {local_path}")
    return local_path


city_sources = {
    "atlanta": (
        "atlanta_split.graphml",
        "atlanta_edges_wgs84.parquet",
        "atlanta_surface.parquet",
    ),
    "boston": (
        "boston_split.graphml",
        "boston_edges_wgs84.parquet",
        "boston_surface.parquet",
    ),
    "chicago": (
        "chicago_split.graphml",
        "chicago_edges_wgs84.parquet",
        "chicago_surface.parquet",
    ),
    "newyork": (
        "newyork_split.graphml",
        "newyork_edges_wgs84.parquet",
        "newyork_surface.parquet",
    ),
    "philadelphia": (
        "philadelphia_split.graphml",
        "philadelphia_edges_wgs84.parquet",
        "philadelphia_surface.parquet",
    ),
    "seattle": (
        "seattle_split.graphml",
        "seattle_edges_wgs84.parquet",
        "seattle_surface.parquet",
    ),
}


def main():
    city_name = os.getenv("CITY_NAME", "boston")
    if city_name not in city_sources:
        raise SystemExit(f"[warmup] Unknown city specified: {city_name}")

    graph_obj, edges_obj, risk_obj = city_sources[city_name]
    print(f"[warmup] Building pickle for {city_name}...")
    city_data = build_city_data(city_name, graph_obj, edges_obj, risk_obj)
    save_city_pickle_local(city_name, city_data, filename="city_data.pkl")


if __name__ == "__main__":
    main()
