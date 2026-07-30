import logging

import pytest
from fastapi import HTTPException

from models.request import ComputeRouteRequest
from routes import compute
from services.spatial import nearest_edge


def test_outside_coverage_error_does_not_include_coordinates():
    class DistantTree:
        def query(self, _points, k):
            assert k == 1
            return [[1.0]], [[0]]

    with pytest.raises(ValueError) as exc_info:
        nearest_edge(DistantTree(), [('u', 'v', 0)], -71.123456, 42.654321)

    message = str(exc_info.value)
    assert '42.654321' not in message
    assert '-71.123456' not in message
    assert message == 'Requested point is outside the graph coverage area'


def test_compute_boundary_redacts_exception_text_and_logs(monkeypatch, caplog):
    sentinel = '42.654321,-71.123456 writer-capability-secret'

    def fail_route(**_kwargs):
        raise RuntimeError(sentinel)

    monkeypatch.setattr(compute, 'compute_routes', fail_route)
    request = ComputeRouteRequest(
        city='boston',
        src_lat=42.654321,
        src_lon=-71.123456,
        dst_lat=42.35,
        dst_lon=-71.04,
        bin=2,
        speed_mps=1.4,
    )

    with caplog.at_level(logging.ERROR), pytest.raises(HTTPException) as exc_info:
        compute.compute_route(request)

    assert exc_info.value.status_code == 500
    assert exc_info.value.detail == 'Route computation failed'
    observable = f'{exc_info.value.detail}\n{caplog.text}'
    assert sentinel not in observable
    assert '42.654321' not in observable
    assert '-71.123456' not in observable
    assert 'writer-capability-secret' not in observable
