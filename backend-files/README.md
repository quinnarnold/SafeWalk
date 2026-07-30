# Public-data pipeline

These scripts build SafeWalk street graphs, time-binned KDE risk surfaces, and
route-evaluation outputs for six cities:

- Atlanta
- Boston
- Chicago
- New York
- Philadelphia
- Seattle

Raw records, caches, generated graphs, Parquet files, and evaluation results
are ignored and are not distributed with the source repository.

## Environment

```bash
uv sync --locked
```

The committed `uv.lock` resolves the shared Python environment. The scripts
use only the dependencies declared in `pyproject.toml`.

## Running a city

Every generator accepts:

- `--output-dir`: generated/cached files for that city; OSMnx HTTP cache data
  is kept under `<output-dir>/cache`
- `--cutoff-date`: month used as the exclusive training cutoff
- `--seed`: seed for origin/destination evaluation sampling; its cache is
  written as `OD_pairs_seed_<seed>.csv`

Example:

```bash
uv run python chicago/chicago.py \
  --output-dir chicago/files \
  --cutoff-date 2026-07-01 \
  --seed 42
```

Boston, Chicago, New York, Philadelphia, and Seattle fetch incident data from
the public endpoints recorded in their source files and `../DATA_SOURCES.md`.
Street graphs are downloaded from OpenStreetMap through OSMnx.

Atlanta uses the downloadable Atlanta Police Department public export because
that portal does not expose the same stable API shape:

```bash
uv run python atlanta/atlanta.py \
  --input-csv /path/to/atlanta-crime-export.csv \
  --output-dir atlanta/files \
  --cutoff-date 2026-07-01 \
  --seed 42
```

The Atlanta CSV must contain `OccurredFromDate`, `Latitude`, `Longitude`,
`LocationType`, and `NIBRS_Offense`.

## Outputs

Each city writes these runtime inputs:

```text
<city>_split.graphml
<city>_edges_wgs84.parquet
<city>_surface.parquet
```

It also writes ignored acquisition/evaluation files:

```text
<city>.graphml
cache/
OD_pairs_seed_<seed>.csv
results/pareto_frontier.csv
```

The first three files are inputs to `../backend/warmup.py`. The unsplit graph
and HTTP cache avoid repeated OpenStreetMap downloads. The seed-specific OD
pairs and Pareto frontier are research diagnostics and are not required by the
runtime.

Reusing an output directory reuses its graph, HTTP cache, and matching
seed-specific OD pairs. Use a new or empty output directory for a fresh
upstream retrieval.

The dependency lock and explicit seed make the software environment and
evaluation sampling repeatable. Live public portals, OpenStreetMap, and their
responses are mutable, so the scripts cannot recreate a historical artifact
from live endpoints alone. Archival reproduction requires the original input
snapshots where their terms permit, exact source URLs, retrieval timestamps,
checksums, cutoff date, seed, dependency lock, and an empty output directory.
See `../DATA_SOURCES.md` before retaining or redistributing any input or output.

Full city runs are network- and compute-intensive and can be throttled by
anonymous public APIs. Atlanta additionally requires a manually obtained CSV.
The OTP download scripts require Bash, curl, unzip, and osmium; the OTP image
build uses an 8 GiB Java heap. These are not exercised by the CLI smoke test.

## Boundaries

```bash
uv run python fetch_boundaries.py --output /tmp/safewalk-boundaries.geojson
```

The boundary file is generated and intentionally ignored.

## Checks

```bash
uv run ruff check .
uv run python -m unittest discover -s tests -v
for city in atlanta boston chicago newyork philadelphia seattle; do
  uv run python "$city/$city.py" --help
done
```
