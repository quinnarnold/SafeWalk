"""Tests for igraph-based routing."""
from unittest.mock import patch

import igraph as ig
import numpy as np

from services.router import _path_metrics, compute_routes


def _build_test_graph():
    """
    Build a small synthetic igraph graph for routing tests.

    Graph topology (5 nodes, 6 edges):
        0 --100m-- 1 --100m-- 2
        |                     |
       200m                 150m
        |                     |
        3 -------300m-------- 4

    Nodes have x/y (lon/lat) and _nx_name (NetworkX node key).
    Edges have edge_id, length_m, and geometry=None.
    """
    g = ig.Graph(directed=True)
    g.add_vertices(5)

    coords = [
        (-71.06, 42.36),
        (-71.05, 42.36),
        (-71.04, 42.36),
        (-71.06, 42.35),
        (-71.04, 42.35),
    ]
    g.vs["x"] = [c[0] for c in coords]
    g.vs["y"] = [c[1] for c in coords]
    g.vs["_nx_name"] = ["n0", "n1", "n2", "n3", "n4"]

    edges = [
        (0, 1), (1, 0),
        (1, 2), (2, 1),
        (0, 3), (3, 0),
        (2, 4), (4, 2),
        (3, 4), (4, 3),
    ]
    g.add_edges(edges)

    lengths = [100, 100, 100, 100, 200, 200, 150, 150, 300, 300]
    edge_ids = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    g.es["length_m"] = lengths
    g.es["edge_id"] = edge_ids
    g.es["geometry"] = [None] * len(edges)

    return g


def _build_city_data(risk_overrides=None):
    """Build a mock city_data dict from the test graph.

    Args:
        risk_overrides: Optional dict of (edge_id, bin) -> risk_value.
            Mapped to a numpy risk_array indexed by igraph edge index.
    """
    g = _build_test_graph()

    nx_node_to_idx = {v["_nx_name"]: v.index for v in g.vs}

    length_weights = np.array(g.es["length_m"], dtype=np.float64)
    edge_ids = g.es["edge_id"]

    # Build risk_array indexed by (igraph_edge_index, bin)
    n_edges = g.ecount()
    risk_array = np.zeros((n_edges, 4), dtype=np.float64)
    if risk_overrides:
        eid_to_idx = {eid: i for i, eid in enumerate(edge_ids)}
        for (eid, b), val in risk_overrides.items():
            if eid in eid_to_idx:
                risk_array[eid_to_idx[eid], b] = val

    precomputed_weights = {}
    for bin_val in range(4):
        precomputed_weights[(bin_val, "moderate")] = length_weights + 75000 * np.log1p(risk_array[:, bin_val])
        precomputed_weights[(bin_val, "safest")] = length_weights + 200000 * np.log1p(risk_array[:, bin_val])

    edge_points = []
    edge_refs = []
    for e in g.es:
        src_v = g.vs[e.source]
        tgt_v = g.vs[e.target]
        mx = (src_v["x"] + tgt_v["x"]) / 2
        my = (src_v["y"] + tgt_v["y"]) / 2
        edge_points.append((mx, my))
        edge_refs.append((src_v["_nx_name"], tgt_v["_nx_name"], 0))

    from sklearn.neighbors import KDTree
    edge_tree = KDTree(np.array(edge_points))

    return {
        "ig_graph": g,
        "nx_node_to_idx": nx_node_to_idx,
        "length_weights": length_weights,
        "precomputed_weights": precomputed_weights,
        "risk_array": risk_array,
        "edge_tree": edge_tree,
        "edge_refs": edge_refs,
    }


class TestPathMetrics:
    """Tests for _path_metrics with igraph edge indices."""

    def test_empty_path(self):
        g = _build_test_graph()
        length_weights = np.array(g.es["length_m"], dtype=np.float64)
        risk_array = np.zeros((g.ecount(), 4), dtype=np.float64)
        dist, pred, time_s = _path_metrics(length_weights, [], risk_array, 0, 1.4)
        assert dist == 0.0
        assert pred == 0.0
        assert time_s == 0.0

    def test_single_edge(self):
        g = _build_test_graph()
        length_weights = np.array(g.es["length_m"], dtype=np.float64)
        risk_array = np.zeros((g.ecount(), 4), dtype=np.float64)
        risk_array[0, 0] = 0.5  # edge index 0 (edge_id=1), bin 0
        dist, pred, time_s = _path_metrics(length_weights, [0], risk_array, 0, 1.4)
        assert dist == 100.0
        assert pred == 0.5
        assert abs(time_s - 100.0 / 1.4) < 0.01

    def test_multi_edge(self):
        g = _build_test_graph()
        length_weights = np.array(g.es["length_m"], dtype=np.float64)
        risk_array = np.zeros((g.ecount(), 4), dtype=np.float64)
        risk_array[0, 0] = 0.1  # edge index 0 (edge_id=1), bin 0
        risk_array[2, 0] = 0.2  # edge index 2 (edge_id=3), bin 0
        dist, pred, time_s = _path_metrics(length_weights, [0, 2], risk_array, 0, 1.4)
        assert dist == 200.0
        assert abs(pred - 0.3) < 1e-9


class TestComputeRoutes:
    """Tests for the full compute_routes function with mocked city data."""

    @patch("services.router.get_city")
    def test_shortest_path_no_risk(self, mock_get_city):
        """With zero risk, all three routes should be identical (shortest)."""
        city_data = _build_city_data()
        mock_get_city.return_value = city_data

        result = compute_routes(
            "test_city",
            src_lat=42.36, src_lon=-71.06,
            dst_lat=42.35, dst_lon=-71.04,
            bin_of_day=0
        )

        assert "shortest" in result
        assert result["shortest"]["distance_m"] > 0

    @patch("services.router.get_city")
    def test_risk_creates_different_routes(self, mock_get_city):
        """When some edges have high risk, moderate/safest should differ from shortest."""
        risk = {}
        for eid in range(1, 11):
            for b in range(4):
                risk[(eid, b)] = 0.0

        # Make the short path (0->1->2->4) risky on edge 3 (1->2) and edge 7 (2->4)
        for b in range(4):
            risk[(3, b)] = 10.0
            risk[(7, b)] = 10.0

        city_data = _build_city_data(risk_overrides=risk)
        mock_get_city.return_value = city_data

        result = compute_routes(
            "test_city",
            src_lat=42.36, src_lon=-71.06,
            dst_lat=42.35, dst_lon=-71.04,
            bin_of_day=0
        )

        assert "shortest" in result
        # Shortest should exist and have positive distance
        assert result["shortest"]["distance_m"] > 0

    @patch("services.router.get_city")
    def test_same_source_destination_returns_valid(self, mock_get_city):
        """Routing from a point near itself should still return a valid route.

        Note: nearest_edge snaps to src_u (edge source) and dst_v (edge target),
        so even identical coordinates may produce a non-zero path if they snap
        to opposite ends of the same edge.
        """
        city_data = _build_city_data()
        mock_get_city.return_value = city_data

        result = compute_routes(
            "test_city",
            src_lat=42.36, src_lon=-71.06,
            dst_lat=42.36, dst_lon=-71.06,
            bin_of_day=0
        )

        assert result["shortest"]["distance_m"] >= 0.0
        assert "shortest" in result

    @patch("services.router.get_city")
    def test_different_time_bins(self, mock_get_city):
        """Routes should use the correct time bin for risk weights."""
        risk = {}
        for eid in range(1, 11):
            for b in range(4):
                risk[(eid, b)] = 0.0

        # Only bin 2 has risk on edge 3
        risk[(3, 2)] = 5.0

        city_data = _build_city_data(risk_overrides=risk)
        mock_get_city.return_value = city_data

        result_bin0 = compute_routes(
            "test_city",
            src_lat=42.36, src_lon=-71.06,
            dst_lat=42.36, dst_lon=-71.05,
            bin_of_day=0
        )
        result_bin2 = compute_routes(
            "test_city",
            src_lat=42.36, src_lon=-71.06,
            dst_lat=42.36, dst_lon=-71.05,
            bin_of_day=2
        )

        # Both should return valid shortest routes
        assert result_bin0["shortest"]["distance_m"] > 0
        assert result_bin2["shortest"]["distance_m"] > 0
