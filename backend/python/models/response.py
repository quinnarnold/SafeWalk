"""Pydantic response models."""
from pydantic import BaseModel, Field


class RouteInfo(BaseModel):
    """Information about a single route."""

    distance_m: float = Field(..., description="Route distance in meters")
    time_s: float = Field(..., description="Route time in seconds")
    pred_risk: float = Field(..., description="Predicted risk score")
    raw_coords: list[list[float]] = Field(
        ...,
        description="Route coordinates as [lon, lat] pairs"
    )


class ComputeRouteResponse(BaseModel):
    """Response model for route computation."""

    shortest: RouteInfo = Field(..., description="Shortest route by distance")
    moderate: RouteInfo | None = Field(
        None,
        description="Balanced route (moderate alpha). Only included if it reduces risk vs shortest."
    )
    safest: RouteInfo | None = Field(
        None,
        description="Safest route (maximum alpha). Only included if it reduces risk vs shortest."
    )


class HealthResponse(BaseModel):
    """Response model for health check."""

    status: str = Field(default="ok")
    city: str = Field(..., description="Currently loaded city")
