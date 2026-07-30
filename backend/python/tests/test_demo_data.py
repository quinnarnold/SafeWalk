"""Tests for the synthetic local-development dataset."""

import importlib.util
from pathlib import Path

import geopandas as gpd
import networkx as nx
import pandas as pd

SCRIPT_PATH = Path(__file__).resolve().parents[2] / "scripts" / "create_demo_data.py"


def _load_demo_module():
    spec = importlib.util.spec_from_file_location("create_demo_data", SCRIPT_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_create_demo_data_writes_runtime_inputs(tmp_path):
    module = _load_demo_module()
    module.create_demo_data(tmp_path)

    graph = nx.read_graphml(tmp_path / "boston_split.graphml")
    edges = gpd.read_parquet(tmp_path / "boston_edges_wgs84.parquet")
    surface = pd.read_parquet(tmp_path / "boston_surface.parquet")

    assert graph.number_of_nodes() == 4
    assert graph.number_of_edges() == 8
    assert len(edges) == 8
    assert set(surface["bin_of_day"]) == {0, 1, 2, 3}
    assert len(surface) == 32
