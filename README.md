# SafeWalk

SafeWalk is an open-source iOS pedestrian-routing application that compares
shortest and risk-weighted walking routes. It builds time-binned risk surfaces
from public incident data and OpenStreetMap street graphs.

SafeWalk is an experimental planning aid. It does not predict whether a person
will be safe, guarantee a crime-free route, or replace emergency services,
local guidance, or personal judgment. See
[SAFETY_AND_LIMITATIONS.md](SAFETY_AND_LIMITATIONS.md).

## Project context

SafeWalk reflects thousands of hours I spent learning geographic data
processing, KDE-based modeling, full-stack iOS and backend engineering, and
route and navigation systems. I am releasing it so others can learn from and
adapt the work, including its Apple App Attest integration, secure backend
patterns, and OpenStreetMap-based routing pipeline. Responsible adaptations
for other places and contexts are welcome. The aim is to help people make more
informed route choices and to contribute something useful—not to promise
safety or exceed the limitations documented here.

## Related research

SafeWalk was developed before I later encountered the following work; this is
development context, not a claim of research priority:

- Fariha Tabassum Islam, Tanzima Hashem, and Rifat Shahriyar,
  ["A Crowd-enabled Solution for Privacy-Preserving and Personalized Safe
  Route Planning for Fixed or Flexible Destinations (Full
  Version)"](https://arxiv.org/abs/2112.13760), arXiv:2112.13760, first
  submitted in 2021.
- Esther Galbrun, Konstantinos Pelechrinis, and Evimaria Terzi,
  ["Urban navigation beyond shortest route: The case of safe
  paths"](https://doi.org/10.1016/j.is.2015.10.005), *Information Systems* 57
  (2016), 160–171.

These papers are useful independent examples of the broader idea that route
planning can consider a safety-related score alongside distance. Galbrun et
al. is especially close methodologically: it uses public crime data for
Chicago and Philadelphia, an OpenStreetMap road graph, and Gaussian kernel
density estimation to assign crime risk to road segments before finding paths
that trade off distance and risk. Islam et al. instead focuses on
crowdsourced, personalized safety scores and privacy-preserving route queries.
SafeWalk uses public incident reports, time-binned KDE surfaces, and centrally
served edge-weighted routing. These papers do not validate SafeWalk or
establish that any of the systems improves real-world safety outcomes.

## What is included

- SwiftUI iOS application with Mapbox maps and navigation
- Bun/Fastify API for routing, sharing, caching, and transit orchestration
- Python/FastAPI compute service using igraph shortest paths
- Public-data generators for Atlanta, Boston, Chicago, New York,
  Philadelphia, and Seattle
- OpenTripPlanner configuration and public GTFS/OSM download scripts
- Optional Kubernetes and OCI deployment examples

Generated city artifacts and raw incident records are intentionally excluded.
The scripts in `backend-files/` can generate new artifacts from current inputs;
reproducing a historical artifact requires the original input snapshots and
retrieval metadata.

## Architecture

```text
iOS app
  |
  | HTTPS + Apple App Attest
  v
Fastify API (:8080) ------ Redis
  |
  | localhost HTTP
  v
FastAPI compute (:8000)
  |
  v
Generated city graph + KDE risk surface
```

The public-data pipeline creates three runtime input files per city:

- `<city>_split.graphml`
- `<city>_edges_wgs84.parquet`
- `<city>_surface.parquet`

`backend/warmup.py` converts those files into the runtime
`data/<city>/city_data.pkl`.

The generators also write ignored OSM graph caches, seed-specific evaluation
pairs, and research results. See `backend-files/README.md` for the complete
output inventory.

## Requirements

- macOS with Xcode 26.1 for the iOS application; older Xcode versions are
  unverified
- A Mapbox account and iOS SDK download token
- Bun 1.3.12 or newer
- Python 3.11–3.13
- `uv` for the locked data-pipeline environment
- Docker for the packaged backend
- Redis for caching, sharing, and App Attest state

Mapbox's iOS binary packages require a secret token with `Downloads:Read` in
`~/.netrc`. This token must never be committed. Follow the
[Mapbox Navigation SDK installation guide](https://docs.mapbox.com/ios/navigation/guides/install/).

## Generate city artifacts

```bash
cd backend-files
uv sync --locked

# Public API example
uv run python boston/boston.py \
  --cutoff-date 2026-07-01 \
  --seed 42 \
  --output-dir boston/files
```

Atlanta's portal provides a downloadable public CSV rather than the same API
shape used by the other generators:

```bash
uv run python atlanta/atlanta.py \
  --input-csv /path/to/atlanta-crime-export.csv \
  --cutoff-date 2026-07-01 \
  --seed 42 \
  --output-dir atlanta/files
```

The output directories are ignored by Git. Upstream public datasets and
OpenStreetMap change over time, so a historical reproduction requires the
original input snapshots, source URLs, retrieval timestamps, checksums, cutoff
date, seed, dependency lock, and an empty output directory. Data sources,
terms, and redistribution limits are listed in
[DATA_SOURCES.md](DATA_SOURCES.md).

For a fast local smoke test that does not download public records, create a
tiny synthetic Boston graph:

```bash
python -m pip install -r backend/python/requirements.lock
python backend/scripts/create_demo_data.py
```

This writes ignored artifacts to `backend/city_data/`. They are test data, not
real routing or safety data.

## Run the backend

After generating one or more cities, copy the three artifacts into
`backend/city_data/`:

```bash
mkdir -p backend/city_data
cp backend-files/boston/files/boston_{split.graphml,edges_wgs84.parquet,surface.parquet} \
  backend/city_data/

cd backend
cp .env.example .env
docker compose up --build
```

The local Compose configuration sets `AUTH_MODE=disabled`. The server refuses
disabled authentication when `NODE_ENV=production`.

To run the services without Docker:

```bash
cd backend
CITY_NAME=boston \
LOCAL_DATA_DIR="$PWD/city_data" \
OUTPUT_DATA_DIR="$PWD/data" \
python warmup.py

cd python
DATA_DIR="$PWD/../data" python -m uvicorn main:app --port 8000

cd ../ts
bun install --frozen-lockfile
AUTH_MODE=disabled PUBLIC_BASE_URL=http://localhost:8080 bun run dev
```

## Run the iOS application

1. Configure the Mapbox downloads token in `~/.netrc`.
2. Open `frontend/SafeWalk.xcodeproj`.
3. Set your development team, unique bundle identifiers, and a matching App
   Group.
4. For local Debug builds, the API defaults to `http://localhost:8080`.
5. Set `SAFEWALK_API_BASE_URL` and, optionally, `SAFEWALK_MAP_STYLE_URI` in
   Xcode build settings for another deployment.
6. For production, enable App Attest and set the backend
   `APP_ATTEST_APP_ID` to `TEAMID.BUNDLEID`.

See [frontend/README.md](frontend/README.md) for the exact build settings and
Release requirements. Release builds intentionally fall back to the reserved
`api.safewalk.invalid` domain when no backend URL is configured.

## Development checks

```bash
cd backend/ts
bun install --frozen-lockfile
bun run typecheck
bun run lint
bun test

cd ../python
python -m pip install -r requirements-dev.lock
ruff check .
pytest tests/ -v

cd ../../backend-files
uv sync --locked --dev
uv run ruff check .
```

The full iOS CI job is enabled with the repository variable
`ENABLE_IOS_CI=true` and requires a `MAPBOX_DOWNLOADS_TOKEN` secret.

## Configuration and deployment

Backend variables are documented in `backend/.env.example`. Production
deployments require:

- `NODE_ENV=production`
- `AUTH_MODE=app-attest`
- `APP_ATTEST_APP_ID`, `APP_ATTEST_BUNDLE_VERSION`, and allowed validation
  categories matching the distributed iOS build
- `MAPBOX_TOKEN` and `MAPBOX_USERNAME`
- `PUBLIC_BASE_URL`
- Redis, including a password on untrusted networks
- `TRUST_PROXY=true` only when the API is reachable exclusively through a
  trusted reverse proxy that overwrites forwarded-client headers

Files in `backend/k8s/` and `backend/deploy/` are templates. Replace all
example domains, image names, email addresses, and cloud values before use.
No deployment workflow is active by default.

## Privacy

Route requests contain start and destination coordinates. Share My Walk stores
route and live-location data in Redis for up to 50 minutes and exposes it to
holders of a high-entropy share URL. A separate secret authorizes location
updates and session termination. SafeWalk adds no project-operated general
analytics service or user-account database. The linked Mapbox SDKs include
their own telemetry/event components; Mapbox states that they send limited
de-identified location and usage data under its terms. Operators are
responsible for transport security, logs, retention, incident response,
preserving required telemetry controls, and an accurate privacy notice.

The iOS client avoids logging route URLs, coordinates, and response bodies.
See [PRIVACY.md](PRIVACY.md) for the complete data-flow and operator checklist.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

SafeWalk-authored source code and documentation, together with the three
project raster assets I contributed and identified in
[DATA_SOURCES.md](DATA_SOURCES.md), are licensed for reuse under the
[MIT License](LICENSE). I confirm that I have authority to redistribute and
license those project assets. Public datasets, OpenStreetMap data, Mapbox
SDKs/services, GTFS feeds, generated artifacts, Apple-supplied platform
assets, and other third-party materials are not relicensed by that grant. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the runtime boundary.
