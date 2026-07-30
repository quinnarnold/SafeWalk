import type { FastifyPluginAsync } from 'fastify';
import {
  TransitRouteParamsSchema,
  TransitRouteQuerySchema,
  type TransitRouteParams,
  type TransitRouteQuery,
  type TransitRouteResponse,
} from '../schemas/transit-route.js';
import { getTransitItineraries, transitCacheKey, currentTimeIso } from '../services/transit-orchestrator.js';
import { cacheGet, cacheSet } from '../services/redis-cache.js';
import { config } from '../config.js';
import { setPrivateNoStore } from '../utils/private-response.js';

export const transitRouteRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.get<{ Params: TransitRouteParams; Querystring: TransitRouteQuery }>(
    '/:city/transit-route',
    async (request, reply) => {
      setPrivateNoStore(reply);
      const startTime = Date.now();

      const paramsResult = TransitRouteParamsSchema.safeParse(request.params);
      if (!paramsResult.success) {
        return reply.status(400).send({
          error: 'Invalid city parameter',
          details: paramsResult.error.issues,
        });
      }

      const queryResult = TransitRouteQuerySchema.safeParse(request.query);
      if (!queryResult.success) {
        return reply.status(400).send({
          error: 'Invalid query parameters',
          details: queryResult.error.issues,
        });
      }

      const { city } = paramsResult.data;
      const { src_lat, src_lon, dst_lat, dst_lon, bin, depart_at, speed_mps } = queryResult.data;

      request.log.info({ city, bin, hasDepartureTime: depart_at !== undefined }, 'Transit route request');

      const cacheKeyStr = transitCacheKey(city, src_lat, src_lon, dst_lat, dst_lon, bin, speed_mps, depart_at);
      const cached = await cacheGet<TransitRouteResponse>(cacheKeyStr);
      if (cached) {
        request.log.info({ elapsed: Date.now() - startTime }, 'Transit cache hit');
        return cached;
      }

      const departAt = depart_at ?? currentTimeIso();

      let itineraries;
      try {
        itineraries = await getTransitItineraries(
          src_lat, src_lon, dst_lat, dst_lon,
          departAt, city, bin, speed_mps,
        );
      } catch {
        request.log.error('OTP2 query failed');
        return reply.status(502).send({ error: 'Transit routing service unavailable' });
      }

      if (itineraries.length === 0) {
        return reply.status(404).send({ error: 'No transit routes found' });
      }

      const response: TransitRouteResponse = { itineraries };

      cacheSet(cacheKeyStr, response, config.transitCacheTtl).catch(() =>
        request.log.error('Failed to cache transit route'),
      );

      request.log.info({ elapsed: Date.now() - startTime, count: itineraries.length }, 'Transit route computed');
      return response;
    },
  );
};
