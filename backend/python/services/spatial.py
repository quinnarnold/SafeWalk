"""Spatial operations using KDTree."""
from typing import Any

from sklearn.neighbors import KDTree

MAX_SNAP_DISTANCE_DEG = 0.1  # ~10km at mid-latitudes


def nearest_edge(
    edge_tree: KDTree,
    edge_refs: list[tuple[Any, Any, Any]],
    lon: float,
    lat: float
) -> tuple[Any, Any, Any]:
    """Find the nearest edge to a given coordinate.

    Raises ValueError if the nearest edge is more than MAX_SNAP_DISTANCE_DEG
    away, indicating the coordinate is outside the graph coverage area.
    """
    dist, idx = edge_tree.query([[lon, lat]], k=1)
    if dist[0][0] > MAX_SNAP_DISTANCE_DEG:
        raise ValueError("Requested point is outside the graph coverage area")
    return edge_refs[idx[0][0]]
