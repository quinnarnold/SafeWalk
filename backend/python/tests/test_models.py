"""Tests for Pydantic models."""
import pytest
from pydantic import ValidationError

from models.request import ComputeRouteRequest
from models.response import ComputeRouteResponse, HealthResponse, RouteInfo


class TestComputeRouteRequest:
    """Tests for ComputeRouteRequest model."""

    def test_valid_request(self):
        """Test valid request parsing."""
        request = ComputeRouteRequest(
            city="boston",
            src_lat=42.361,
            src_lon=-71.057,
            dst_lat=42.355,
            dst_lon=-71.065,
            bin=2,
            speed_mps=1.4,
        )

        assert request.city == "boston"
        assert request.src_lat == 42.361
        assert request.bin == 2

    def test_default_values(self):
        """Test default values are applied."""
        request = ComputeRouteRequest(
            city="boston",
            src_lat=42.361,
            src_lon=-71.057,
            dst_lat=42.355,
            dst_lon=-71.065,
        )

        assert request.bin == 2
        assert request.speed_mps == 1.4
        # alpha is no longer a parameter - routes are computed with fixed alphas

    def test_invalid_bin(self):
        """Test validation rejects invalid bin."""
        with pytest.raises(ValidationError):
            ComputeRouteRequest(
                city="boston",
                src_lat=42.361,
                src_lon=-71.057,
                dst_lat=42.355,
                dst_lon=-71.065,
                bin=5,  # Invalid: > 3
            )

    def test_invalid_speed(self):
        """Test validation rejects non-positive speed."""
        with pytest.raises(ValidationError):
            ComputeRouteRequest(
                city="boston",
                src_lat=42.361,
                src_lon=-71.057,
                dst_lat=42.355,
                dst_lon=-71.065,
                speed_mps=-1.0,  # Invalid: negative
            )

    def test_invalid_city(self):
        """Test validation rejects unsupported city names."""
        with pytest.raises(ValidationError):
            ComputeRouteRequest(
                city="../../tmp",
                src_lat=42.361,
                src_lon=-71.057,
                dst_lat=42.355,
                dst_lon=-71.065,
            )


class TestRouteInfo:
    """Tests for RouteInfo model."""

    def test_valid_route_info(self):
        """Test valid route info."""
        route = RouteInfo(
            distance_m=1000.5,
            time_s=714.6,
            pred_risk=0.05,
            raw_coords=[[-71.057, 42.361], [-71.065, 42.355]],
        )

        assert route.distance_m == 1000.5
        assert route.pred_risk == 0.05
        assert len(route.raw_coords) == 2


class TestComputeRouteResponse:
    """Tests for ComputeRouteResponse model."""

    def test_complete_response(self):
        """Test complete route response with shortest, moderate, safest."""
        shortest = RouteInfo(
            distance_m=1000.0,
            time_s=714.3,
            pred_risk=0.05,
            raw_coords=[[-71.057, 42.361]],
        )

        moderate = RouteInfo(
            distance_m=1050.0,
            time_s=750.0,
            pred_risk=0.04,
            raw_coords=[[-71.057, 42.361]],
        )

        safest = RouteInfo(
            distance_m=1100.0,
            time_s=785.7,
            pred_risk=0.03,
            raw_coords=[[-71.057, 42.361]],
        )

        response = ComputeRouteResponse(
            shortest=shortest,
            moderate=moderate,
            safest=safest,
        )

        assert response.shortest.distance_m == 1000.0
        assert response.moderate.distance_m == 1050.0
        assert response.safest.distance_m == 1100.0
        assert response.safest.pred_risk < response.moderate.pred_risk < response.shortest.pred_risk

    def test_response_with_null_routes(self):
        """Test response when moderate/safest don't reduce risk (set to None)."""
        shortest = RouteInfo(
            distance_m=1000.0,
            time_s=714.3,
            pred_risk=0.02,  # Very low risk - safer routes might not help
            raw_coords=[[-71.057, 42.361]],
        )

        response = ComputeRouteResponse(
            shortest=shortest,
            moderate=None,
            safest=None,
        )

        assert response.shortest.distance_m == 1000.0
        assert response.moderate is None
        assert response.safest is None


class TestHealthResponse:
    """Tests for HealthResponse model."""

    def test_health_response(self):
        """Test health response."""
        health = HealthResponse(status="ok", city="boston")

        assert health.status == "ok"
        assert health.city == "boston"
