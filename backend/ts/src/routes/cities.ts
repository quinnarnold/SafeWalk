import type { FastifyPluginAsync } from 'fastify';
import { CITIES } from '../config.js';

export const citiesRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.get('/cities', async () => {
    return {
      cities: CITIES.map((city) => ({
        name: city.name,
        center: [...city.center],
        defaultZoom: city.defaultZoom,
      })),
    };
  });
};
