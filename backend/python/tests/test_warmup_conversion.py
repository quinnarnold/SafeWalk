"""Tests for NetworkX-to-igraph conversion in warmup.py."""
import igraph as ig
import networkx as nx
import numpy as np


def _make_small_nx_graph():
    """Build a small NetworkX MultiDiGraph mimicking warmup.py output."""
    G = nx.MultiDiGraph()

    nodes = [
        ("100", {"x": -71.06, "y": 42.36}),
        ("200", {"x": -71.05, "y": 42.36}),
        ("300", {"x": -71.04, "y": 42.36}),
    ]
    G.add_nodes_from(nodes)

    G.add_edge("100", "200", key=0, edge_id=1, length_m=100.0, geometry=None)
    G.add_edge("200", "100", key=0, edge_id=2, length_m=100.0, geometry=None)
    G.add_edge("200", "300", key=0, edge_id=3, length_m=150.0, geometry=None)
    G.add_edge("300", "200", key=0, edge_id=4, length_m=150.0, geometry=None)

    return G


class TestFromNetworkxConversion:
    """Tests for ig.Graph.from_networkx preserving graph structure."""

    def test_vertex_count_preserved(self):
        G = _make_small_nx_graph()
        ig_graph = ig.Graph.from_networkx(G)
        assert ig_graph.vcount() == G.number_of_nodes()

    def test_edge_count_preserved(self):
        G = _make_small_nx_graph()
        ig_graph = ig.Graph.from_networkx(G)
        assert ig_graph.ecount() == G.number_of_edges()

    def test_node_attributes_preserved(self):
        G = _make_small_nx_graph()
        ig_graph = ig.Graph.from_networkx(G)

        for v in ig_graph.vs:
            nx_name = v["_nx_name"]
            assert v["x"] == G.nodes[nx_name]["x"]
            assert v["y"] == G.nodes[nx_name]["y"]

    def test_edge_attributes_preserved(self):
        G = _make_small_nx_graph()
        ig_graph = ig.Graph.from_networkx(G)

        ig_edge_ids = set(ig_graph.es["edge_id"])
        nx_edge_ids = {d["edge_id"] for _, _, d in G.edges(data=True)}
        assert ig_edge_ids == nx_edge_ids

    def test_edge_length_preserved(self):
        G = _make_small_nx_graph()
        ig_graph = ig.Graph.from_networkx(G)

        ig_lengths = sorted(ig_graph.es["length_m"])
        nx_lengths = sorted(d["length_m"] for _, _, d in G.edges(data=True))
        assert ig_lengths == nx_lengths

    def test_nx_node_mapping_bijective(self):
        G = _make_small_nx_graph()
        ig_graph = ig.Graph.from_networkx(G)

        nx_node_to_idx = {v["_nx_name"]: v.index for v in ig_graph.vs}

        assert len(nx_node_to_idx) == ig_graph.vcount()
        assert set(nx_node_to_idx.values()) == set(range(ig_graph.vcount()))
        assert set(nx_node_to_idx.keys()) == set(G.nodes)

    def test_directed_preserved(self):
        G = _make_small_nx_graph()
        ig_graph = ig.Graph.from_networkx(G)
        assert ig_graph.is_directed()


class TestPrecomputedWeights:
    """Tests for precomputed weight vector construction."""

    def test_weight_vectors_shape(self):
        G = _make_small_nx_graph()
        ig_graph = ig.Graph.from_networkx(G)

        length_weights = np.array(
            [e["length_m"] if e["length_m"] is not None else 1.0 for e in ig_graph.es],
            dtype=np.float64,
        )
        assert length_weights.shape == (ig_graph.ecount(),)

    def test_zero_risk_weights_equal_length(self):
        G = _make_small_nx_graph()
        ig_graph = ig.Graph.from_networkx(G)

        length_weights = np.array(ig_graph.es["length_m"], dtype=np.float64)
        risk_arr = np.zeros(ig_graph.ecount(), dtype=np.float64)

        moderate_weights = length_weights + 75000 * np.log1p(risk_arr)
        np.testing.assert_array_almost_equal(moderate_weights, length_weights)

    def test_risk_increases_weight(self):
        G = _make_small_nx_graph()
        ig_graph = ig.Graph.from_networkx(G)

        length_weights = np.array(ig_graph.es["length_m"], dtype=np.float64)

        risk_arr = np.array([1.0] * ig_graph.ecount(), dtype=np.float64)
        moderate_weights = length_weights + 75000 * np.log1p(risk_arr)

        assert np.all(moderate_weights > length_weights)

    def test_safest_weights_higher_than_moderate(self):
        G = _make_small_nx_graph()
        ig_graph = ig.Graph.from_networkx(G)

        length_weights = np.array(ig_graph.es["length_m"], dtype=np.float64)
        risk_arr = np.array([0.5] * ig_graph.ecount(), dtype=np.float64)

        moderate = length_weights + 75000 * np.log1p(risk_arr)
        safest = length_weights + 200000 * np.log1p(risk_arr)

        assert np.all(safest >= moderate)
