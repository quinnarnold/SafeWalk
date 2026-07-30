"""Create a tiny synthetic Boston dataset for local SafeWalk development."""

import argparse
from pathlib import Path

import geopandas as gpd
import networkx as nx
import pandas as pd
from shapely.geometry import LineString


def create_demo_data(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    nodes = {
        100: (-71.0600, 42.3600),
        200: (-71.0550, 42.3600),
        300: (-71.0500, 42.3600),
        400: (-71.0550, 42.3630),
    }
    edge_specs = [
        (100, 200, 100.0, 0.020),
        (200, 300, 100.0, 0.020),
        (100, 400, 130.0, 0.001),
        (400, 300, 130.0, 0.001),
    ]

    graph = nx.MultiDiGraph()
    graph.graph["crs"] = "EPSG:4326"
    for node_id, (lon, lat) in nodes.items():
        graph.add_node(node_id, x=lon, y=lat)

    edge_rows = []
    edge_id = 0
    for source, target, length_m, risk in edge_specs:
        for u, v in ((source, target), (target, source)):
            line = LineString([nodes[u], nodes[v]])
            graph.add_edge(u, v, key=0, length=length_m, geometry=line.wkt)
            edge_rows.append(
                {
                    "u": u,
                    "v": v,
                    "key": 0,
                    "edge_id": edge_id,
                    "length_m": length_m,
                    "geometry": line,
                    "highway": "residential",
                    "foot": "yes",
                    "risk": risk,
                }
            )
            edge_id += 1

    nx.write_graphml(graph, output_dir / "boston_split.graphml")

    edges = gpd.GeoDataFrame(edge_rows, geometry="geometry", crs="EPSG:4326")
    edges.drop(columns="risk").to_parquet(
        output_dir / "boston_edges_wgs84.parquet",
        index=False,
    )

    risk_rows = [
        {
            "edge_id": row["edge_id"],
            "bin_of_day": time_bin,
            "kde_risk": row["risk"],
        }
        for row in edge_rows
        for time_bin in range(4)
    ]
    pd.DataFrame(risk_rows).to_parquet(
        output_dir / "boston_surface.parquet",
        index=False,
    )

    print(f"Wrote synthetic Boston artifacts to {output_dir}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "city_data",
    )
    args = parser.parse_args()
    create_demo_data(args.output_dir.resolve())


if __name__ == "__main__":
    main()
