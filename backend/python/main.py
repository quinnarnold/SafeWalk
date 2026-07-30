"""FastAPI entry point for Python compute layer."""
import logging
import sys
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI

from config import settings
from routes import compute, health
from services.city_loader import preload_city

logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL),
    format="[%(asctime)s] [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[logging.StreamHandler(sys.stdout)],
)

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan handler for startup/shutdown."""
    logger.info(f"Starting Python compute layer for {settings.CITY_NAME}")

    try:
        preload_city()
        logger.info("City data loaded successfully")
    except Exception as e:
        logger.error("FATAL: Failed to load city data (%s)", type(e).__name__)
        raise

    logger.info("Python compute layer ready")

    yield

    logger.info("Shutting down Python compute layer")


app = FastAPI(
    title="SafeWalk Compute Layer",
    description="Internal API for route computation",
    version="1.0.0",
    lifespan=lifespan,
)

app.include_router(health.router, tags=["health"])
app.include_router(compute.router, tags=["compute"])


@app.get("/")
async def root() -> dict[str, str]:
    """Root endpoint for basic health check."""
    return {"status": "ok", "service": "python-compute"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="127.0.0.1",
        port=8000,
        reload=True,
        log_level=settings.LOG_LEVEL.lower(),
    )
