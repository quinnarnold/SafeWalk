"""Pydantic request models."""
from typing import Literal

from pydantic import BaseModel, Field


class ComputeRouteRequest(BaseModel):
    """Request model for route computation."""

    city: Literal[
        "atlanta",
        "boston",
        "chicago",
        "newyork",
        "philadelphia",
        "seattle",
    ] = Field(
        ...,
        description=(
            "City name (one of: atlanta, boston, chicago, newyork, "
            "philadelphia, seattle)"
        ),
    )
    src_lat: float = Field(..., description="Source latitude")
    src_lon: float = Field(..., description="Source longitude")
    dst_lat: float = Field(..., description="Destination latitude")
    dst_lon: float = Field(..., description="Destination longitude")
    bin: int = Field(
        default=2,
        ge=0,
        le=3,
        description="Time bin (0-3, representing 6-hour periods)"
    )
    speed_mps: float = Field(
        default=1.4,
        gt=0,
        description="Walking speed in meters per second"
    )
