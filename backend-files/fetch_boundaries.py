"""Fetch SafeWalk city boundaries from OpenStreetMap via OSMnx."""

import argparse
import json
from pathlib import Path

import osmnx as ox

CITIES = [
    {"name": "Atlanta", "query": "Atlanta, Georgia, USA"},
    {"name": "Boston", "query": "Boston, Massachusetts, USA"},
    {"name": "Chicago", "query": "Chicago, Illinois, USA"},
    {"name": "New York", "query": "New York City, New York, USA"},
    {"name": "Philadelphia", "query": "Philadelphia, Pennsylvania, USA"},
    {"name": "Seattle", "query": "Seattle, Washington, USA"},
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent / "safewalk_city_boundaries.geojson",
    )
    args = parser.parse_args()

    features = []
    for city in CITIES:
        print(f"Fetching boundary: {city['name']} ...")
        gdf = ox.geocode_to_gdf(city["query"])
        geom = gdf.geometry.iloc[0]
        features.append(
            {
                "type": "Feature",
                "properties": {"name": city["name"]},
                "geometry": geom.__geo_interface__,
            }
        )
        print(f"  Done. Geometry type: {geom.geom_type}")

    collection = {"type": "FeatureCollection", "features": features}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(collection), encoding="utf-8")
    print(f"Wrote {len(features)} features to {args.output}")


if __name__ == "__main__":
    main()
