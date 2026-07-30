"""Route computation endpoints."""
import logging

from fastapi import APIRouter, HTTPException

from models.request import ComputeRouteRequest
from models.response import ComputeRouteResponse
from services.router import compute_routes

logger = logging.getLogger(__name__)
logger.info("routes/compute.py imported")

router = APIRouter()


@router.post("/compute-route", response_model=ComputeRouteResponse)
def compute_route(request: ComputeRouteRequest) -> ComputeRouteResponse:
    """
    Compute routes between two points.

    Returns shortest, moderate, and safest routes with metrics.
    """
    try:
        result = compute_routes(
            city_name=request.city,
            src_lat=request.src_lat,
            src_lon=request.src_lon,
            dst_lat=request.dst_lat,
            dst_lon=request.dst_lon,
            bin_of_day=request.bin,
            speed_mps=request.speed_mps,
        )
        return ComputeRouteResponse(**result)

    except FileNotFoundError:
        logger.error("City data is unavailable")
        raise HTTPException(status_code=404, detail="City data is unavailable")

    except Exception as e:
        logger.error("Route computation failed (%s)", type(e).__name__)
        raise HTTPException(status_code=500, detail="Route computation failed")
