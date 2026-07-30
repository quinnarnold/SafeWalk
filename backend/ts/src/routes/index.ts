import type { FastifyPluginAsync } from 'fastify';
import { healthRoutes } from './health.js';
import { citiesRoutes } from './cities.js';
import { routeRoutes } from './route.js';
import { mapboxTokenRoutes } from './mapbox-token.js';
import { shareRoutes } from './share.js';
import { watchRoutes } from './watch.js';
import { transitRouteRoutes } from './transit-route.js';
import { attestRoutes } from './attest.js';

export const registerRoutes: FastifyPluginAsync = async (fastify) => {
  await fastify.register(healthRoutes);
  await fastify.register(citiesRoutes);
  await fastify.register(routeRoutes);
  await fastify.register(mapboxTokenRoutes);
  await fastify.register(shareRoutes);
  await fastify.register(watchRoutes);
  await fastify.register(transitRouteRoutes);
  await fastify.register(attestRoutes);
};
