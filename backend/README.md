# SafeWalk backend

The backend combines a Bun/Fastify API with a Python/FastAPI routing service.
Each runtime image serves one city and contains a prebuilt graph, spatial
index, and four time-bin weight vectors.

## Services

- `ts/`: request validation, App Attest verification, rate limiting, Redis
  caching and pub/sub, Mapbox token minting/map matching, sharing, and transit
  orchestration
- `python/`: nearest-edge lookup and igraph shortest/risk-weighted routes
- `warmup.py`: converts generated GraphML/Parquet inputs into the runtime
  pickle
- `otp/`: OpenTripPlanner image and public feed download scripts

## Authentication

Production uses Apple App Attest. Protected requests include
`X-App-Attest-KeyId`, `X-App-Attest-Assertion`, and `X-Timestamp`. Public
routes are limited to health, city discovery, App Attest bootstrap, and
unguessable watcher URLs.

Assertions bind the timestamp, HTTP method, path, canonical query, and request
body hash. The backend validates the Apple certificate chain, nonce, App ID,
AAGUID, public-key/key-ID relationship, assertion signature, relying-party
hash, and monotonic counter.

If an otherwise signed request refers to a credential that has expired or
disappeared from Redis, the backend returns a stable, non-sensitive recovery
code. The client clears only the stale key, performs one new attestation, and
retries once; other authentication failures remain generic and fail closed.

`AUTH_MODE=disabled` is provided for local development only. Startup fails if
it is used with `NODE_ENV=production`.

## API

| Method | Route | Authentication |
| --- | --- | --- |
| `GET` | `/` | Public |
| `GET` | `/health` | Public |
| `GET` | `/cities` | Public |
| `GET` | `/:city/attest/challenge` | Public, rate limited |
| `POST` | `/:city/attest/verify` | Public, rate limited |
| `GET` | `/:city/route` | App Attest |
| `GET` | `/:city/transit-route` | App Attest |
| `POST` | `/:city/mapbox-temporary-token` | App Attest |
| `POST` | `/:city/share/start` | App Attest |
| `POST` | `/:city/share/location` | App Attest |
| `POST` | `/:city/share/stop` | App Attest |
| `GET` | `/watch/:sessionId` | Share URL |
| `GET` | `/watch/:sessionId/data` | Share URL |
| `GET` | `/watch/:sessionId/events` | Share URL |

Supported cities are Atlanta, Boston, Chicago, New York, Philadelphia, and
Seattle.

## Local development

See the root README for city-artifact generation. Then:

```bash
cp .env.example .env
docker compose up --build
```

Or run the two services independently:

```bash
cd python
python -m pip install -r requirements-dev.lock
DATA_DIR=../data python -m uvicorn main:app --port 8000

cd ../ts
bun install --frozen-lockfile
AUTH_MODE=disabled bun run dev
```

Redis is required for App Attest credentials and sharing. Route and map-match
caches degrade to misses if Redis operations fail. Sharing fails closed when
Redis is unavailable. Starting a share returns a high-entropy viewer URL and a
separate writer capability; location and stop requests require the writer
capability.

Routes containing location data, App Attest bootstrap responses, temporary
tokens, and share responses use `Cache-Control: private, no-store`.

## Tests

```bash
cd ts
bun run typecheck
bun run lint
bun test

cd ../python
ruff check .
pytest tests/ -v
```

## Containers

The Docker build expects these files in `city_data/` for `CITY_NAME`:

```text
<city>_split.graphml
<city>_edges_wgs84.parquet
<city>_surface.parquet
```

Example:

```bash
docker build --build-arg CITY_NAME=boston -t safewalk-boston .
```

The committed Bun and Python lockfiles are used for frozen production
installs. Update the input requirements files and regenerate the locks with
`uv pip compile` when dependencies change.

Building an image is not license clearance to distribute it. The backend image
includes GPL-licensed igraph/python-igraph, and the OTP image includes
LGPL-licensed OpenTripPlanner plus OSM/GTFS-derived data. Review
`../THIRD_PARTY_NOTICES.md` and `../DATA_SOURCES.md`, generate an exact SBOM,
and satisfy the artifact-specific source, notice, data, and service terms
before distribution.

Set `TRUST_PROXY=true` only when the API is reachable exclusively through a
trusted reverse proxy that overwrites forwarded-client headers.

## Deployment templates

`k8s/` and `deploy/` contain generic examples, not an active production
deployment. They use `safewalk.example.com`, `ghcr.io/your-org`, and other
replacement values. Review resource sizing, architecture, secrets, ingress,
network policies, persistence, and environment protection before use.
