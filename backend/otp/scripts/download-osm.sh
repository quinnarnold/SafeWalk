#!/usr/bin/env bash
set -euo pipefail

DEST="${1:-/data/osm}"
mkdir -p "$DEST"

BBB="https://download.bbbike.org/osm/bbbike"
GEO="https://download.geofabrik.de/north-america/us"

download() {
  local name="$1" url="$2"
  echo "  Downloading $name..."
  curl -fSL --retry 3 -L -o "$DEST/$name" "$url"
}

echo "Downloading metro-area OSM extracts..."

# BBBike metro extracts (available directly)
download "chicago.osm.pbf" "$BBB/Chicago/Chicago.osm.pbf"
download "newyork.osm.pbf" "$BBB/NewYork/NewYork.osm.pbf"
download "philadelphia.osm.pbf" "$BBB/Philadelphia/Philadelphia.osm.pbf"
download "seattle.osm.pbf" "$BBB/Seattle/Seattle.osm.pbf"

# Boston and Atlanta not on BBBike — clip from Geofabrik state extracts
echo "  Downloading Massachusetts state (will clip to Boston metro)..."
curl -fSL --retry 3 -L -o "$DEST/massachusetts.osm.pbf" "$GEO/massachusetts-latest.osm.pbf"
osmium extract -b "-71.25,42.20,-70.85,42.50" "$DEST/massachusetts.osm.pbf" -o "$DEST/boston.osm.pbf" --overwrite
rm "$DEST/massachusetts.osm.pbf"

echo "  Downloading Georgia state (will clip to Atlanta metro)..."
curl -fSL --retry 3 -L -o "$DEST/georgia.osm.pbf" "$GEO/georgia-latest.osm.pbf"
osmium extract -b "-84.60,33.55,-84.15,33.95" "$DEST/georgia.osm.pbf" -o "$DEST/atlanta.osm.pbf" --overwrite
rm "$DEST/georgia.osm.pbf"

echo "Merging into combined.osm.pbf..."
osmium merge \
  "$DEST/boston.osm.pbf" \
  "$DEST/chicago.osm.pbf" \
  "$DEST/newyork.osm.pbf" \
  "$DEST/atlanta.osm.pbf" \
  "$DEST/philadelphia.osm.pbf" \
  "$DEST/seattle.osm.pbf" \
  -o "$DEST/combined.osm.pbf" --overwrite

echo "Combined OSM extract:"
ls -lh "$DEST"/*.osm.pbf
