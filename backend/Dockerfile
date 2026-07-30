# =============================================================================
# SafeWalk Backend - Hybrid Architecture (Bun + Python)
# =============================================================================

FROM oven/bun:1.3.12@sha256:8956c7667fa17beb6e3c664115e66bdacfe502da5d99603626e74c197bdef160 AS bun

FROM python:3.11-slim

# Install system deps + Bun
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl supervisor \
    && rm -rf /var/lib/apt/lists/*

COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun

RUN useradd -r -u 1000 -m safewalk

WORKDIR /app

# Python setup
COPY python/requirements.lock ./python/
RUN pip install --no-cache-dir -r python/requirements.lock
COPY python/ ./python/

# TypeScript setup (Bun runs TS directly - no build step)
COPY ts/package.json ts/bun.lock ./ts/
RUN cd ts && bun install --production --frozen-lockfile
COPY ts/src ./ts/src

# Warmup (builds city_data.pkl)
COPY warmup.py ./
COPY city_data/ ./city_data/
ARG CITY_NAME=boston
ENV CITY_NAME=${CITY_NAME}
RUN python warmup.py

# Transfer ownership to safewalk user
RUN chown -R safewalk:safewalk /app

# Supervisord
COPY supervisord.conf /etc/supervisor/conf.d/safewalk.conf

# Environment
ENV PORT=8080 PYTHONUNBUFFERED=1 BUN_ENV=production NODE_ENV=production
ENV DATA_DIR=/app/data PYTHON_URL=http://127.0.0.1:8000
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

USER safewalk

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/safewalk.conf"]
