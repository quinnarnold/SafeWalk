#!/usr/bin/env bash
set -euo pipefail

DEST="${1:-/data/gtfs}"
mkdir -p "$DEST"

echo "Downloading GTFS feeds for all cities..."

download() {
  local name="$1" url="$2"
  echo "  Downloading $name..."
  curl -fSL --retry 5 --retry-delay 5 --retry-all-errors \
    --connect-timeout 30 --max-time 120 \
    -A "Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -o "$DEST/$name" "$url"
}

validate() {
  local file="$1"
  local basename="${file##*/}"
  if [ ! -f "$file" ]; then
    echo "ERROR: $file not found"; exit 1
  fi
  local size
  size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
  echo "  $basename: ${size} bytes"
  if [ "$size" -lt 5000 ]; then
    echo "ERROR: $basename is suspiciously small ($size bytes)"; exit 1
  fi
  local magic
  magic=$(head -c 2 "$file" | od -A n -t x1 | tr -d ' ')
  if [ "$magic" != "504b" ]; then
    echo "ERROR: $basename is not a valid zip (magic: $magic)"
    exit 1
  fi
  local required_files="agency.txt stops.txt routes.txt trips.txt stop_times.txt"
  local contents
  contents=$(unzip -l "$file" | awk '{print $NF}')
  for req in $required_files; do
    if ! echo "$contents" | grep -qx "$req"; then
      echo "ERROR: $basename is missing required GTFS file: $req"
      exit 1
    fi
  done
}

# Boston (MBTA)
download "mbta.zip" "https://cdn.mbta.com/MBTA_GTFS.zip"

# Chicago (CTA) - via Mobility Database mirror (CTA origin blocked by Cloudflare in CI)
download "cta.zip" "https://storage.googleapis.com/storage/v1/b/mdb-latest/o/us-illinois-chicago-transit-authority-cta-gtfs-389.zip?alt=media"

# New York (MTA) - subway + rail + bus boroughs
download "mta-subway.zip" "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_subway.zip"
download "mta-lirr.zip" "https://rrgtfsfeeds.s3.amazonaws.com/gtfslirr.zip"
download "mta-mnr.zip" "https://rrgtfsfeeds.s3.amazonaws.com/gtfsmnr.zip"
download "mta-bus-bx.zip" "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_bx.zip"
download "mta-bus-b.zip" "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_b.zip"
download "mta-bus-m.zip" "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_m.zip"
download "mta-bus-q.zip" "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_q.zip"
download "mta-bus-si.zip" "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_si.zip"

# Atlanta (MARTA)
download "marta.zip" "https://itsmarta.com/google_transit_feed/google_transit.zip"

# Philadelphia (SEPTA) - version tag changes per release; use GitHub releases API
# SEPTA distributes gtfs_public.zip as a nested zip containing google_bus.zip
# and google_rail.zip, so we extract the inner feeds as separate GTFS files.
SEPTA_URL=$(curl -fsSL --retry 3 "https://api.github.com/repos/septadev/GTFS/releases/latest" \
  | grep -o '"browser_download_url": "[^"]*gtfs_public.zip"' \
  | head -1 | cut -d'"' -f4)
if [ -z "$SEPTA_URL" ]; then
  echo "ERROR: Could not resolve SEPTA GTFS latest release URL"; exit 1
fi
download "septa_outer.zip" "$SEPTA_URL"
echo "  Extracting nested SEPTA feeds..."
unzip -o "$DEST/septa_outer.zip" -d "$DEST/septa_tmp"
mv "$DEST/septa_tmp/google_bus.zip" "$DEST/septa-bus.zip"
mv "$DEST/septa_tmp/google_rail.zip" "$DEST/septa-rail.zip"
rm -rf "$DEST/septa_tmp" "$DEST/septa_outer.zip"

# Seattle (King County Metro + Sound Transit) - via Mobility Database mirror (origin servers block CI)
download "kcm.zip" "https://storage.googleapis.com/storage/v1/b/mdb-latest/o/us-washington-king-county-metro-gtfs-1330.zip?alt=media"
download "sound-transit.zip" "https://storage.googleapis.com/storage/v1/b/mdb-latest/o/us-washington-sound-transit-gtfs-268.zip?alt=media"

# Validate all feeds
echo "Validating feeds..."
for f in "$DEST"/*.zip; do
  validate "$f"
done

echo "Downloaded and validated $(ls "$DEST"/*.zip | wc -l) GTFS feeds"
ls -lh "$DEST"/*.zip
