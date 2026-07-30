import { config } from '../config.js';
import { cacheGet, cacheSet } from './redis-cache.js';
import { mapMatchCacheKey } from '../utils/cache-key.js';

interface MapboxMatchResponse {
  matchings?: Array<{
    geometry?: {
      type: string;
      coordinates: number[][];
    };
  }>;
}

const CHUNK_SIZE = 70;
const CHUNK_OVERLAP = 10;

async function matchChunk(coords: number[][]): Promise<number[][] | null> {
  if (!config.mapboxToken || !coords.length) {
    return null;
  }

  const coordsStr = coords.map(([lon, lat]) => `${lon},${lat}`).join(';');
  const radiuses = coords.map(() => '30').join(';');

  const url = new URL(`https://api.mapbox.com/matching/v5/mapbox/walking/${coordsStr}`);
  url.searchParams.set('geometries', 'geojson');
  url.searchParams.set('overview', 'full');
  url.searchParams.set('tidy', 'true');
  url.searchParams.set('steps', 'false');
  url.searchParams.set('radiuses', radiuses);
  url.searchParams.set('access_token', config.mapboxToken);

  const response = await fetch(url.toString(), {
    method: 'GET',
    signal: AbortSignal.timeout(4000),
  });

  if (!response.ok) {
    await response.body?.cancel();
    console.warn(`[Mapbox] Map-matching chunk returned status ${response.status}`);
    return null;
  }

  const data = (await response.json()) as MapboxMatchResponse;

  if (!data.matchings?.length) {
    return null;
  }

  const matched: number[][] = [];
  for (const matching of data.matchings) {
    const seg = matching?.geometry?.coordinates;
    if (seg?.length) {
      matched.push(...seg);
    }
  }

  return matched.length ? matched : null;
}

function splitIntoChunks(coords: number[][]): number[][][] {
  if (coords.length <= CHUNK_SIZE) {
    return [coords];
  }

  const chunks: number[][][] = [];
  let start = 0;

  while (start < coords.length) {
    const end = Math.min(start + CHUNK_SIZE, coords.length);
    chunks.push(coords.slice(start, end));

    if (end >= coords.length) break;
    start = end - CHUNK_OVERLAP;
  }

  return chunks;
}

function stitchChunks(results: (number[][] | null)[]): number[][] | null {
  const matched: number[][] = [];

  for (let i = 0; i < results.length; i++) {
    const chunk = results[i];
    if (!chunk?.length) {
      return null;
    }

    if (i === 0) {
      matched.push(...chunk);
    } else {
      const prevLast = matched[matched.length - 1];
      if (!prevLast) {
        matched.push(...chunk);
        continue;
      }

      let bestIdx = 0;
      let bestDist = Infinity;
      const searchLimit = Math.min(chunk.length, 20);
      for (let j = 0; j < searchLimit; j++) {
        const pt = chunk[j];
        if (!pt) continue;
        const d = (pt[0]! - prevLast[0]!) ** 2 + (pt[1]! - prevLast[1]!) ** 2;
        if (d < bestDist) {
          bestDist = d;
          bestIdx = j;
        }
      }

      matched.push(...chunk.slice(bestIdx + 1));
    }
  }

  return matched.length ? matched : null;
}

export async function mapboxMatch(coords: number[][]): Promise<number[][] | null> {
  if (!coords.length) {
    return null;
  }

  const cacheKeyStr = mapMatchCacheKey(coords);
  const cached = await cacheGet<number[][] | false>(cacheKeyStr);

  if (cached !== null) {
    if (cached === false) {
      return null;
    }
    return cached;
  }

  if (!config.mapboxToken) {
    console.warn('[Mapbox] No MAPBOX_TOKEN configured, skipping map-matching');
    return null;
  }

  try {
    const chunks = splitIntoChunks(coords);
    const results = await Promise.all(chunks.map(matchChunk));
    const matchedCoords = stitchChunks(results);

    if (!matchedCoords) {
      await cacheSet(cacheKeyStr, false, 3600);
      return null;
    }

    cacheSet(cacheKeyStr, matchedCoords, config.mmCacheTtl).catch(() =>
      console.warn('[Mapbox] Failed to cache match result')
    );

    return matchedCoords;
  } catch {
    console.error('[Mapbox] Map-matching request failed');
    return null;
  }
}

export function capCoordsForMapbox(coords: number[][], maxPoints = 100): number[][] {
  const n = coords.length;
  if (n <= maxPoints) {
    return coords;
  }

  const step = Math.max(1, Math.floor((n - 1) / (maxPoints - 1)));
  const result: number[][] = [];

  for (let i = 0; i < n; i += step) {
    const coord = coords[i];
    if (coord) {
      result.push(coord);
    }
  }

  const lastCoord = coords[n - 1];
  if (lastCoord && result[result.length - 1] !== lastCoord) {
    result.push(lastCoord);
  }

  return result;
}
