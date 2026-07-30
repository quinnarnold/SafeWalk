/**
 * Health check endpoint.
 */
import type { FastifyPluginAsync } from 'fastify';
import { checkPythonHealth } from '../services/python-client.js';
import { checkRedisHealth } from '../services/redis-cache.js';
import { checkOtpHealth } from '../services/otp-client.js';

export const healthRoutes: FastifyPluginAsync = async (fastify) => {
  /**
   * GET / - Basic health check
   */
  fastify.get('/', async () => {
    return { status: 'ok' };
  });

  /**
   * GET /health - Detailed health check with dependencies
   */
  fastify.get('/health', async (_request, reply) => {
    const [pythonHealthy, redisHealthy, otpHealthy] = await Promise.all([
      checkPythonHealth(),
      checkRedisHealth(),
      checkOtpHealth(),
    ]);

    const healthy = pythonHealthy && redisHealthy;

    return reply.status(healthy ? 200 : 503).send({
      status: healthy ? 'ok' : 'degraded',
      services: {
        python: pythonHealthy ? 'ok' : 'error',
        redis: redisHealthy ? 'ok' : 'error',
        otp: otpHealthy ? 'ok' : 'unavailable',
      },
    });
  });
};
