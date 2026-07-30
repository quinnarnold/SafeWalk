import { createHash } from 'crypto';
import { config } from '../config.js';

export function cacheKey(prefix: string, ...parts: (string | number)[]): string {
  const raw = `${config.cityName}|${prefix}|${parts.map(String).join('|')}`;
  return createHash('sha1').update(raw).digest('hex');
}

// Increment when map-match parameters change to invalidate cached results
const MM_CACHE_VERSION = 'v3';

export function mapMatchCacheKey(coords: number[][]): string {
  const coordsHash = createHash('sha1').update(JSON.stringify(coords)).digest('hex');
  return cacheKey('mm', MM_CACHE_VERSION, coords.length, coordsHash);
}

export function routeCacheKey(
  cityName: string,
  srcLat: number,
  srcLon: number,
  dstLat: number,
  dstLon: number,
  bin: number,
  speedMps: number
): string {
  const roundedSrcLat = srcLat.toFixed(4);
  const roundedSrcLon = srcLon.toFixed(4);
  const roundedDstLat = dstLat.toFixed(4);
  const roundedDstLon = dstLon.toFixed(4);
  const roundedSpeed = speedMps.toFixed(3);

  return cacheKey(
    'route',
    cityName,
    roundedSrcLat,
    roundedSrcLon,
    roundedDstLat,
    roundedDstLon,
    bin,
    roundedSpeed
  );
}
