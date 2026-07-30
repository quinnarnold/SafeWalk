import type { FastifyPluginAsync } from 'fastify';
import { RouteQuerySchema, RouteParamsSchema, type RouteQuery, type RouteParams, type PythonRouteResponse } from '../schemas/route.js';
import { computeRoute } from '../services/python-client.js';
import { mapboxMatch } from '../services/mapbox.js';
import { cacheGet, cacheSet } from '../services/redis-cache.js';
import { routeCacheKey } from '../utils/cache-key.js';
import { setPrivateNoStore } from '../utils/private-response.js';
import { config, CITIES } from '../config.js';
import {
  createLineString,
  createRouteFeature,
  createFeatureCollection,
  type RouteFeature,
  type RouteFeatureCollection,
} from '../utils/geojson.js';

function buildRouteFeatures(
  routeData: PythonRouteResponse,
  matched: { shortest: number[][] | null; moderate: number[][] | null; safest: number[][] | null }
): RouteFeature[] {
  const features: RouteFeature[] = [
    createRouteFeature(
      'shortest',
      createLineString(matched.shortest ?? routeData.shortest.raw_coords),
      {
        distance_m: routeData.shortest.distance_m,
        time_s: routeData.shortest.time_s,
        pred_risk: routeData.shortest.pred_risk,
      }
    ),
  ];

  if (routeData.moderate) {
    features.push(
      createRouteFeature(
        'moderate',
        createLineString(matched.moderate ?? routeData.moderate.raw_coords),
        {
          distance_m: routeData.moderate.distance_m,
          time_s: routeData.moderate.time_s,
          pred_risk: routeData.moderate.pred_risk,
        }
      )
    );
  }

  if (routeData.safest) {
    features.push(
      createRouteFeature(
        'safest',
        createLineString(matched.safest ?? routeData.safest.raw_coords),
        {
          distance_m: routeData.safest.distance_m,
          time_s: routeData.safest.time_s,
          pred_risk: routeData.safest.pred_risk,
        }
      )
    );
  }

  return features;
}

function matchedCacheKey(rawKey: string): string {
  return rawKey + ':mm';
}

function backgroundMapMatch(
  routeData: PythonRouteResponse,
  cacheKeyStr: string,
) {
  Promise.all([
    mapMatchCoords(routeData.shortest.raw_coords),
    routeData.moderate ? mapMatchCoords(routeData.moderate.raw_coords) : null,
    routeData.safest ? mapMatchCoords(routeData.safest.raw_coords) : null,
  ]).then(([shortest, moderate, safest]) => {
    console.log(`[map-match] shortest=${!!shortest} moderate=${!!moderate} safest=${!!safest}`);
    if (!shortest && !moderate && !safest) {
      return;
    }

    const features = buildRouteFeatures(routeData, { shortest, moderate, safest });
    const result = createFeatureCollection(features);

    return cacheSet(matchedCacheKey(cacheKeyStr), result, config.routeCacheTtl);
  }).then((updated) => {
    if (updated !== undefined) {
      console.log('[map-match] Background map-matched route cached');
    }
  }).catch(() => {
    console.warn('[map-match] Background map-matching failed');
  });
}

const CITY_COVERAGE_RADIUS_M = 25_000;

function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6_371_000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function isWithinCoverage(city: string, lat: number, lon: number): boolean {
  const cityInfo = CITIES.find(c => c.name === city);
  if (!cityInfo) return false;
  const [centerLon, centerLat] = cityInfo.center;
  return haversineDistance(lat, lon, centerLat, centerLon) <= CITY_COVERAGE_RADIUS_M;
}

export const routeRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.get<{ Params: RouteParams; Querystring: RouteQuery }>(
    '/:city/route',
    async (request, reply) => {
      setPrivateNoStore(reply);
      const startTime = Date.now();

      const paramsResult = RouteParamsSchema.safeParse(request.params);
      if (!paramsResult.success) {
        return reply.status(400).send({
          error: 'Invalid city parameter',
          details: paramsResult.error.issues,
        });
      }

      const queryResult = RouteQuerySchema.safeParse(request.query);
      if (!queryResult.success) {
        return reply.status(400).send({
          error: 'Invalid query parameters',
          details: queryResult.error.issues,
        });
      }

      const { city } = paramsResult.data;
      const { src_lat, src_lon, dst_lat, dst_lon, bin, speed_mps } = queryResult.data;

      request.log.info({ city, bin }, 'Route request');

      const cacheKeyStr = routeCacheKey(city, src_lat, src_lon, dst_lat, dst_lon, bin, speed_mps);

      const cachedMatched = await cacheGet<RouteFeatureCollection>(matchedCacheKey(cacheKeyStr));
      if (cachedMatched) {
        request.log.info({ elapsed: Date.now() - startTime }, 'Cache hit (matched)');
        return cachedMatched;
      }

      const cachedRaw = await cacheGet<RouteFeatureCollection>(cacheKeyStr);
      if (cachedRaw) {
        request.log.info({ elapsed: Date.now() - startTime }, 'Cache hit (raw)');
        return cachedRaw;
      }

      const srcInCity = isWithinCoverage(city, src_lat, src_lon);
      const dstInCity = isWithinCoverage(city, dst_lat, dst_lon);

      let routeData;
      if (srcInCity && dstInCity) {
        try {
          routeData = await computeRoute({
            city,
            srcLat: src_lat,
            srcLon: src_lon,
            dstLat: dst_lat,
            dstLon: dst_lon,
            bin,
            speedMps: speed_mps,
          });
        } catch {
          request.log.warn('Python compute failed, falling back to Mapbox Directions');
        }
      } else {
        request.log.info({ srcInCity, dstInCity }, 'Point outside city coverage, using Mapbox Directions');
      }

      if (routeData && routeData.shortest.raw_coords.length <= 2) {
        request.log.warn('Python returned degenerate route, falling back to Mapbox Directions');
        routeData = undefined;
      }

      if (!routeData) {
        try {
          const mbUrl = `https://api.mapbox.com/directions/v5/mapbox/walking/${src_lon},${src_lat};${dst_lon},${dst_lat}?geometries=geojson&overview=full&access_token=${config.mapboxToken}`;
          const mbRes = await fetch(mbUrl, { signal: AbortSignal.timeout(4000) });
          if (!mbRes.ok) {
            throw new Error(`Mapbox Directions responded with ${mbRes.status}`);
          }
          const mbData = await mbRes.json() as {
            routes: Array<{
              geometry: { type: 'LineString'; coordinates: number[][] };
              distance: number;
              duration: number;
            }>;
          };
          const route = mbData.routes[0];
          if (!route) {
            throw new Error('Mapbox Directions returned no routes');
          }
          const fallbackFeature = createRouteFeature(
            'shortest',
            route.geometry,
            { distance_m: route.distance, time_s: route.duration, fallback: true }
          );
          const fallbackResult = createFeatureCollection([fallbackFeature]);
          cacheSet(cacheKeyStr, fallbackResult, 3600).catch(() =>
            request.log.error('Failed to cache fallback route')
          );
          return fallbackResult;
        } catch {
          request.log.error('Mapbox Directions fallback also failed');
          return reply.status(500).send({ error: 'Route computation failed' });
        }
      }

      const features = buildRouteFeatures(routeData, { shortest: null, moderate: null, safest: null });
      const result = createFeatureCollection(features);

      cacheSet(cacheKeyStr, result, 300).catch(() =>
        request.log.error('Failed to cache route result')
      );

      request.log.info({ elapsed: Date.now() - startTime }, 'Route computed');

      backgroundMapMatch(routeData, cacheKeyStr);

      return result;
    }
  );
};

async function mapMatchCoords(coords: number[][]): Promise<number[][] | null> {
  if (!coords.length) {
    return null;
  }

  return mapboxMatch(coords);
}
