"""Tests for geometry utilities."""

from services.geometry import (
    cap_with_preserve,
    densify_coords,
)


class TestDensifyCoords:
    """Tests for densify_coords function."""

    def test_empty_coords(self):
        """Test empty coordinates returns empty."""
        result = densify_coords([])
        assert result == []

    def test_single_point(self):
        """Test single point returns unchanged."""
        coords = [(0.0, 0.0)]
        result = densify_coords(coords)
        assert result == coords

    def test_two_points_close(self):
        """Test two close points (no densification needed)."""
        coords = [(0.0, 0.0), (0.0001, 0.0001)]  # Very close together
        result = densify_coords(coords, max_m=12.0)
        # Should return both points with no interpolation
        assert len(result) >= 2

    def test_two_points_far(self):
        """Test two far points (densification needed)."""
        coords = [(0.0, 0.0), (0.01, 0.01)]  # ~1.5km apart at equator
        result = densify_coords(coords, max_m=12.0)
        # Should add interpolated points
        assert len(result) > 2
        # First and last should match original
        assert result[0] == coords[0]
        assert result[-1] == coords[1]


class TestCapWithPreserve:
    """Tests for cap_with_preserve function."""

    def test_no_cap_needed(self):
        """Test coords under limit returns unchanged."""
        coords = [(0.0, 0.0), (1.0, 1.0), (2.0, 2.0)]
        result = cap_with_preserve(coords, max_points=10)
        assert result == coords

    def test_preserves_endpoints(self):
        """Test first and last points are preserved."""
        coords = [(i * 0.1, i * 0.1) for i in range(100)]
        result = cap_with_preserve(coords, max_points=10)

        assert result[0] == coords[0]
        assert result[-1] == coords[-1]
        assert len(result) <= 10

    def test_preserves_indices(self):
        """Test specified indices are preserved."""
        coords = [(i * 0.1, i * 0.1) for i in range(100)]
        preserve = {25, 50, 75}  # Preserve these indices

        result = cap_with_preserve(coords, max_points=20, preserve_idx=preserve)

        # All preserved points should be in result
        for idx in preserve:
            assert coords[idx] in result

    def test_handles_more_preserve_than_max(self):
        """Test handling when preserve indices exceed max points."""
        coords = [(i * 0.1, i * 0.1) for i in range(100)]
        preserve = set(range(50))  # Preserve 50 indices

        result = cap_with_preserve(coords, max_points=10, preserve_idx=preserve)

        # Should still return something reasonable
        assert len(result) <= 50  # At most the preserved count
