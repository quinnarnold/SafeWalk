"""Health check routes."""
from fastapi import APIRouter

from config import settings
from models.response import HealthResponse

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    """Internal health check endpoint."""
    return HealthResponse(status="ok", city=settings.CITY_NAME)
