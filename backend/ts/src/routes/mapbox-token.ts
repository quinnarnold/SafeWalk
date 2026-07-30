import type { FastifyPluginAsync, FastifyRequest, FastifyReply } from 'fastify';
import { config } from '../config.js';
import { setPrivateNoStore } from '../utils/private-response.js';

/**
 * Creates a short-lived (~55 minutes) token with limited scopes for navigation.
 * The permanent MAPBOX_TOKEN never leaves the server.
 */
async function createTempToken(
  request: FastifyRequest,
  reply: FastifyReply
) {
  setPrivateNoStore(reply);
  if (!config.mapboxToken) {
    return reply.status(500).send({ error: 'MAPBOX_TOKEN not configured' });
  }
  if (!config.mapboxUsername) {
    return reply.status(500).send({ error: 'MAPBOX_USERNAME not configured' });
  }

  const expires = new Date(Date.now() + 55 * 60 * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z');

  const payload = {
    note: 'SafeWalk temporary client token',
    expires,
    scopes: [
      'styles:read',
      'fonts:read',
      'tilesets:read',
      'map:read',
      'datasets:read',
      'navigation:download',
    ],
  };

  try {
    const url = new URL(`https://api.mapbox.com/tokens/v2/${config.mapboxUsername}`);
    url.searchParams.set('access_token', config.mapboxToken);

    const response = await fetch(url.toString(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10000),
    });

    if (!response.ok) {
      await response.body?.cancel();
      return reply.status(response.status).send({
        error: 'Mapbox token API failed',
      });
    }

    const data = (await response.json()) as { token?: string };
    if (!data.token) {
      return reply.status(502).send({ error: 'Mapbox token response did not include a token' });
    }

    return {
      mapbox_token: data.token,
      expires,
      scopes: payload.scopes,
    };
  } catch {
    request.log.error('Failed to create temporary Mapbox token');
    return reply.status(500).send({ error: 'Failed to create temporary token' });
  }
}

export const mapboxTokenRoutes: FastifyPluginAsync = async (fastify) => {
  const rateLimitConfig = { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } };
  fastify.post('/mapbox-temporary-token', rateLimitConfig, createTempToken);
  fastify.post('/:city/mapbox-temporary-token', rateLimitConfig, createTempToken);
};
