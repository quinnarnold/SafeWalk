import type { FastifyPluginAsync, FastifyRequest, FastifyReply } from 'fastify';
import { ShareSessionParamsSchema } from '../schemas/share.js';
import { cacheGet } from '../services/redis-cache.js';
import {
  closeSubscriber,
  createSubscriber,
  subscribe,
} from '../services/redis-pubsub.js';
import { watchPageHtml } from './watch-page.js';
import { PRIVATE_NO_STORE, setPrivateNoStore } from '../utils/private-response.js';

interface ShareSession {
  routeGeoJSON: unknown;
  destinationName: string;
  city: string;
  startedAt: number;
  mapboxToken: string;
}

async function watchPage(request: FastifyRequest, reply: FastifyReply) {
  setPrivateNoStore(reply);
  reply.header('Referrer-Policy', 'no-referrer');
  const parseResult = ShareSessionParamsSchema.safeParse(request.params);
  if (!parseResult.success) {
    return reply.status(400).send('Invalid session');
  }

  const { sessionId } = parseResult.data;
  const session = await cacheGet<ShareSession>(`share:${sessionId}`);
  if (!session) {
    return reply.status(404).type('text/html').send(
      '<html><body><h1>Walk session not found</h1><p>This link may have expired.</p></body></html>'
    );
  }

  reply.header(
    'Content-Security-Policy',
    [
      "default-src 'none'",
      "script-src 'self' 'unsafe-inline' https://api.mapbox.com",
      "style-src 'self' 'unsafe-inline' https://api.mapbox.com",
      "connect-src 'self' https://api.mapbox.com https://*.tiles.mapbox.com",
      "img-src 'self' data: blob: https://api.mapbox.com https://*.tiles.mapbox.com",
      "worker-src blob:",
    ].join('; ')
  );
  return reply.type('text/html').send(watchPageHtml(sessionId));
}

async function watchData(request: FastifyRequest, reply: FastifyReply) {
  setPrivateNoStore(reply);
  const parseResult = ShareSessionParamsSchema.safeParse(request.params);
  if (!parseResult.success) {
    return reply.status(400).send({ error: 'Invalid session' });
  }

  const { sessionId } = parseResult.data;
  const session = await cacheGet<ShareSession>(`share:${sessionId}`);
  if (!session) {
    return reply.status(404).send({ error: 'Session not found' });
  }

  const lastLocation = await cacheGet<{ lat: number; lon: number; ts: number }>(
    `share:${sessionId}:loc`
  );

  return {
    routeGeoJSON: session.routeGeoJSON,
    destinationName: session.destinationName,
    city: session.city,
    mapboxToken: session.mapboxToken,
    lastLocation,
  };
}

async function watchEvents(request: FastifyRequest, reply: FastifyReply) {
  setPrivateNoStore(reply);
  const parseResult = ShareSessionParamsSchema.safeParse(request.params);
  if (!parseResult.success) {
    return reply.status(400).send('Invalid session');
  }

  const { sessionId } = parseResult.data;
  const session = await cacheGet<unknown>(`share:${sessionId}`);
  if (!session) {
    return reply.status(404).send('Session not found');
  }

  const subscriber = createSubscriber();
  try {
    await subscribe(subscriber, `share:${sessionId}`);
  } catch {
    request.log.error('Failed to subscribe to share events');
    await closeSubscriber(subscriber);
    return reply.status(503).send('Event stream unavailable');
  }

  subscriber.on('error', () => {
    request.log.error('Share event subscriber failed');
    void closeSubscriber(subscriber);
    reply.raw.end();
  });

  reply.hijack();
  reply.raw.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': PRIVATE_NO_STORE,
    Connection: 'keep-alive',
  });
  reply.raw.flushHeaders();

  subscriber.on('message', (_channel: string, message: string) => {
    reply.raw.write(`data: ${message}\n\n`);

    try {
      const parsed = JSON.parse(message);
      if (parsed.type === 'ended') {
        void closeSubscriber(subscriber);
        reply.raw.end();
      }
    } catch {
      // Malformed message -- continue streaming
    }
  });

  request.raw.on('close', () => {
    void closeSubscriber(subscriber);
  });
}

export const watchRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.get('/watch/:sessionId', watchPage);
  fastify.get('/watch/:sessionId/data', watchData);
  fastify.get('/watch/:sessionId/events', watchEvents);
};
