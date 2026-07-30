"""Edge geometry extraction utilities."""
import logging

from shapely.geometry import LineString

logger = logging.getLogger(__name__)


def concat_edges_coords_and_preserve_idx(
    ig_graph,
    edge_indices: list[int]
) -> tuple[list[tuple[float, float]], set[int]]:
    """
    Concatenate coordinates for the ordered edge index list.

    Avoids duplicate adjacent points and returns preserve_idx_set containing
    indices of coords corresponding to edge boundaries.

    Args:
        ig_graph: igraph Graph object
        edge_indices: List of igraph edge indices

    Returns:
        Tuple of (coords list, preserve_idx set)
    """
    coords: list[tuple[float, float]] = []
    preserve: set[int] = set()

    for eidx in edge_indices:
        e = ig_graph.es[eidx]
        geom = e["geometry"]

        if isinstance(geom, LineString):
            pts = list(geom.coords)
        else:
            src_v = ig_graph.vs[e.source]
            tgt_v = ig_graph.vs[e.target]
            pts = [
                (src_v["x"], src_v["y"]),
                (tgt_v["x"], tgt_v["y"])
            ]

        if coords and pts and coords[-1] == pts[0]:
            append_pts = pts[1:]
        else:
            append_pts = pts

        if append_pts:
            coords.extend(append_pts)
            preserve.add(len(coords) - 1)
        else:
            preserve.add(len(coords) - 1)

    if coords:
        preserve.add(0)
        preserve.add(len(coords) - 1)

    return coords, preserve


def densify_coords(
    coords: list[tuple[float, float]],
    max_m: float = 12.0
) -> list[tuple[float, float]]:
    """
    Densify coordinates by interpolating between points.

    Args:
        coords: List of (lon, lat) coordinate tuples
        max_m: Maximum distance between points in meters

    Returns:
        Densified coordinate list
    """
    if not coords or len(coords) < 2:
        return coords

    out = [coords[0]]
    for (x1, y1), (x2, y2) in zip(coords, coords[1:]):
        dist_deg = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
        dist_m = dist_deg * 111320.0
        steps = max(0, int(dist_m / max_m) - 1)

        for i in range(steps):
            t = (i + 1) / (steps + 1)
            out.append((x1 + t * (x2 - x1), y1 + t * (y2 - y1)))
        out.append((x2, y2))

    return out


def _perp_distance(
    point: tuple[float, float],
    line_start: tuple[float, float],
    line_end: tuple[float, float]
) -> float:
    """Perpendicular distance from point to line defined by line_start and line_end."""
    x0, y0 = point
    x1, y1 = line_start
    x2, y2 = line_end
    dx = x2 - x1
    dy = y2 - y1

    if dx == 0.0 and dy == 0.0:
        return ((x0 - x1) ** 2 + (y0 - y1) ** 2) ** 0.5

    num = abs(dy * x0 - dx * y0 + x2 * y1 - y2 * x1)
    den = (dx ** 2 + dy ** 2) ** 0.5
    return num / den


def cap_with_preserve(
    coords: list[tuple[float, float]],
    max_points: int = 100,
    preserve_idx: set[int] | None = None
) -> list[tuple[float, float]]:
    """
    Sample coords to <= max_points using shape-preserving selection.

    Points are ranked by perpendicular distance to the line between their
    neighbors — high-curvature points (turns, bends) are kept preferentially
    while collinear points on straight segments are dropped first.

    Indices in preserve_idx (edge boundaries) are always retained.
    """
    if preserve_idx is None:
        preserve_idx = set()

    n = len(coords)
    if n <= max_points:
        return coords

    valid_preserve_idx = {i for i in preserve_idx if 0 <= i < n}

    if len(valid_preserve_idx) >= max_points:
        logger.warning(
            f"[cap_with_preserve] More points to preserve ({len(valid_preserve_idx)}) "
            f"than max_points ({max_points}). Sampling from preserved points."
        )
        sorted_indices = sorted(valid_preserve_idx)
        step = len(sorted_indices) / max_points
        sampled_indices = [sorted_indices[int(i * step)] for i in range(max_points)]
        if sorted_indices[-1] not in sampled_indices:
            sampled_indices[-1] = sorted_indices[-1]
        return [coords[i] for i in sampled_indices]

    must_keep = {0, n - 1} | valid_preserve_idx
    budget = max_points - len(must_keep)

    if budget <= 0:
        return [coords[i] for i in sorted(must_keep)]

    removable = []
    for i in range(1, n - 1):
        if i in must_keep:
            continue
        d = _perp_distance(coords[i], coords[i - 1], coords[i + 1])
        removable.append((d, i))

    removable.sort(reverse=True)
    for d, idx in removable[:budget]:
        must_keep.add(idx)

    return [coords[i] for i in sorted(must_keep)]


def coords_for_display_from_edges(
    ig_graph,
    edge_indices: list[int],
    max_points: int = 100,
    densify_max_m: float = 12.0
) -> tuple[list[tuple[float, float]], bool]:
    """
    Get display-ready coordinates from edge indices.

    Concatenates, densifies, and caps coordinates.

    Args:
        ig_graph: igraph Graph object
        edge_indices: List of igraph edge indices
        max_points: Maximum number of points to return
        densify_max_m: Maximum distance between densified points

    Returns:
        Tuple of (coordinates, is_within_limit)
    """
    raw_coords, preserve_idx = concat_edges_coords_and_preserve_idx(ig_graph, edge_indices)
    dens = densify_coords(raw_coords, max_m=densify_max_m)

    if not dens:
        return [], True

    new_preserve_idx: set[int] = set()
    for i in preserve_idx:
        if i < 0 or i >= len(raw_coords):
            continue
        px, py = raw_coords[i]

        try:
            exact_idx = next(j for j, c in enumerate(dens) if c[0] == px and c[1] == py)
            new_preserve_idx.add(exact_idx)
        except StopIteration:
            best_j = min(
                range(len(dens)),
                key=lambda j: (dens[j][0] - px) ** 2 + (dens[j][1] - py) ** 2
            )
            new_preserve_idx.add(best_j)

    capped = cap_with_preserve(dens, max_points=max_points, preserve_idx=new_preserve_idx)
    return capped, len(capped) <= max_points


def extract_raw_coords(
    ig_graph,
    edge_indices: list[int]
) -> list[list[float]]:
    """
    Extract raw coordinates from edge indices as GeoJSON-style [lon, lat] arrays.

    Skips densification so that natural edge geometry is preserved — curvy
    roads retain more points while straight segments stay sparse. Combined
    with shape-preserving capping this produces better Mapbox map-matching
    input than densify-then-uniform-sample.
    """
    coords, preserve_idx = concat_edges_coords_and_preserve_idx(ig_graph, edge_indices)
    capped = cap_with_preserve(coords, max_points=500, preserve_idx=preserve_idx)
    return [[c[0], c[1]] for c in capped]
