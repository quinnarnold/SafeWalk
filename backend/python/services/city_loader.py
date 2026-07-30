"""Load city data from pickle files.

Pickle is used here to load prebuilt city data files created by this
repository's warmup step from locally supplied artifacts. Never load artifacts
from an untrusted source: pickle and joblib files can execute arbitrary code.
"""
import logging
import os
import pickle
from typing import Any

import joblib

from config import settings

logger = logging.getLogger(__name__)

_CITIES: dict[str, dict[str, Any]] = {}
_CITY_DIRECTORIES = {
    "atlanta": "atlanta",
    "boston": "boston",
    "chicago": "chicago",
    "newyork": "newyork",
    "philadelphia": "philadelphia",
    "seattle": "seattle",
}


def get_city(name: str | None = None) -> dict[str, Any]:
    """
    Load prebuilt pickle or joblib file containing city_data.

    Contains: ig_graph, nx_node_to_idx, length_weights, precomputed_weights,
    risk_array (numpy 2D array indexed by edge_idx and bin), edge_tree (KDTree),
    and edge_refs. Cached in memory after first load.
    """
    city_name = name or settings.CITY_NAME
    city_directory = _CITY_DIRECTORIES.get(city_name)
    if city_directory is None:
        raise ValueError("Unsupported city")

    if city_name in _CITIES:
        return _CITIES[city_name]

    logger.info(f"[city_loader] Loading prebuilt {city_name} data...")

    data_dir = os.path.join(settings.DATA_DIR, city_directory)
    pickle_path = os.path.join(data_dir, "city_data.pkl")
    joblib_path = os.path.join(data_dir, "city_data.joblib")

    if os.path.exists(joblib_path):
        city_data = joblib.load(joblib_path, mmap_mode='r')
        source_format = "joblib"
    elif os.path.exists(pickle_path):
        with open(pickle_path, "rb") as f:
            city_data = pickle.load(f)
        source_format = "pickle"
    else:
        raise FileNotFoundError(f"No city data found for configured city {city_name}")

    ig_graph = city_data.get("ig_graph")
    if ig_graph is not None:
        logger.info(
            f"[city_loader] {city_name} igraph: {ig_graph.vcount()} vertices, "
            f"{ig_graph.ecount()} edges"
        )
        pw = city_data.get("precomputed_weights", {})
        logger.info(f"[city_loader] {city_name} precomputed weight vectors: {len(pw)}")
    else:
        logger.warning(f"[city_loader] {city_name} missing igraph data, rebuild pickle")

    _CITIES[city_name] = city_data
    logger.info(f"[city_loader] {city_name} loaded successfully ({source_format})")
    return city_data


def preload_city() -> None:
    """Preload the configured city's data at startup."""
    try:
        get_city(settings.CITY_NAME)
        logger.info(f"[city_loader] Preloaded {settings.CITY_NAME}")
    except Exception as e:
        logger.error(
            "[city_loader] Failed to preload %s (%s)",
            settings.CITY_NAME,
            type(e).__name__,
        )
        raise
