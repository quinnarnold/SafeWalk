"""Path computation using igraph and precomputed risk-weighted Dijkstra."""
import logging
from typing import Any

import numpy as np

from config import settings
from services.city_loader import get_city
from services.geometry import extract_raw_coords
from services.spatial import nearest_edge

logger = logging.getLogger(__name__)


def _extend_coords(coords, src_lon, src_lat, dst_lon, dst_lat):
    """Prepend the actual source and append the actual destination to the
    coordinate list so that the rendered geometry reaches the requested
    endpoints instead of stopping at the nearest graph node."""
    if not coords:
        return [[src_lon, src_lat], [dst_lon, dst_lat]]
    src_pt = [src_lon, src_lat]
    dst_pt = [dst_lon, dst_lat]
    if coords[0] != src_pt:
        coords.insert(0, src_pt)
    if coords[-1] != dst_pt:
        coords.append(dst_pt)
    return coords


def _closer_node(ig_graph, nx_node_to_idx, node_u, node_v, lon, lat):
    """Return the igraph vertex index for whichever of node_u / node_v is
    geographically closer to (lon, lat)."""
    u_idx = nx_node_to_idx[node_u]
    v_idx = nx_node_to_idx[node_v]
    ux, uy = ig_graph.vs[u_idx]["x"], ig_graph.vs[u_idx]["y"]
    vx, vy = ig_graph.vs[v_idx]["x"], ig_graph.vs[v_idx]["y"]
    dist_u = (ux - lon) ** 2 + (uy - lat) ** 2
    dist_v = (vx - lon) ** 2 + (vy - lat) ** 2
    return u_idx if dist_u <= dist_v else v_idx


def compute_routes(
    city_name: str,
    src_lat: float,
    src_lon: float,
    dst_lat: float,
    dst_lon: float,
    bin_of_day: int,
    speed_mps: float | None = None
) -> dict[str, Any]:
    """
    Compute shortest, moderate, and safest routes between two points.

    Uses igraph's C-based Dijkstra with precomputed weight vectors for each
    (time_bin, route_type) combination.
    """
    if speed_mps is None:
        speed_mps = settings.DEFAULT_SPEED_MPS

    city = get_city(city_name)
    ig_graph = city["ig_graph"]
    nx_node_to_idx = city["nx_node_to_idx"]
    length_weights = city["length_weights"]
    precomputed_weights = city["precomputed_weights"]
    risk_array = city["risk_array"]
    edge_tree = city["edge_tree"]
    edge_refs = city["edge_refs"]

    src_u, src_v, _ = nearest_edge(edge_tree, edge_refs, src_lon, src_lat)
    dst_u, dst_v, _ = nearest_edge(edge_tree, edge_refs, dst_lon, dst_lat)

    src_idx = _closer_node(ig_graph, nx_node_to_idx, src_u, src_v, src_lon, src_lat)
    dst_idx = _closer_node(ig_graph, nx_node_to_idx, dst_u, dst_v, dst_lon, dst_lat)

    shortest_epath = ig_graph.get_shortest_paths(
        src_idx, to=dst_idx, weights=length_weights, output="epath"
    )[0]
    moderate_epath = ig_graph.get_shortest_paths(
        src_idx, to=dst_idx, weights=precomputed_weights[(bin_of_day, "moderate")], output="epath"
    )[0]
    safest_epath = ig_graph.get_shortest_paths(
        src_idx, to=dst_idx, weights=precomputed_weights[(bin_of_day, "safest")], output="epath"
    )[0]

    dist_short, pred_short, time_short = _path_metrics(
        length_weights, shortest_epath, risk_array, bin_of_day, speed_mps
    )
    dist_moderate, pred_moderate, time_moderate = _path_metrics(
        length_weights, moderate_epath, risk_array, bin_of_day, speed_mps
    )
    dist_safest, pred_safest, time_safest = _path_metrics(
        length_weights, safest_epath, risk_array, bin_of_day, speed_mps
    )

    short_coords = _extend_coords(extract_raw_coords(ig_graph, shortest_epath), src_lon, src_lat, dst_lon, dst_lat)
    moderate_coords = _extend_coords(extract_raw_coords(ig_graph, moderate_epath), src_lon, src_lat, dst_lon, dst_lat)
    safest_coords = _extend_coords(extract_raw_coords(ig_graph, safest_epath), src_lon, src_lat, dst_lon, dst_lat)

    result: dict[str, Any] = {
        "shortest": {
            "distance_m": dist_short,
            "time_s": time_short,
            "pred_risk": pred_short,
            "raw_coords": short_coords,
        },
    }

    if pred_moderate < pred_short:
        result["moderate"] = {
            "distance_m": dist_moderate,
            "time_s": time_moderate,
            "pred_risk": pred_moderate,
            "raw_coords": moderate_coords,
        }
    else:
        result["moderate"] = None
        logger.debug(
            f"Moderate route excluded: pred_risk ({pred_moderate:.4f}) >= "
            f"shortest pred_risk ({pred_short:.4f})"
        )

    if pred_safest < pred_short:
        result["safest"] = {
            "distance_m": dist_safest,
            "time_s": time_safest,
            "pred_risk": pred_safest,
            "raw_coords": safest_coords,
        }
    else:
        result["safest"] = None
        logger.debug(
            f"Safest route excluded: pred_risk ({pred_safest:.4f}) >= "
            f"shortest pred_risk ({pred_short:.4f})"
        )

    return result


def _path_metrics(
    length_weights: np.ndarray,
    edge_path: list[int],
    risk_array: np.ndarray,
    bin_of_day: int,
    speed_mps: float
) -> tuple[float, float, float]:
    """
    Compute distance, predicted risk, and travel time for an edge path.

    Args:
        length_weights: 1D numpy array of edge lengths indexed by edge index
        edge_path: List of igraph edge indices
        risk_array: 2D numpy array shaped (n_edges, 4) indexed by (edge_idx, bin)
        bin_of_day: Time bin (0-3)
        speed_mps: Walking speed in m/s

    Returns:
        Tuple of (distance_m, pred_risk, time_s)
    """
    if not edge_path:
        return 0.0, 0.0, 0.0

    idx = np.array(edge_path)
    dist = float(length_weights[idx].sum())
    pred = float(risk_array[idx, bin_of_day].sum())
    time_s = dist / max(speed_mps, 1e-6)

    return dist, pred, time_s
