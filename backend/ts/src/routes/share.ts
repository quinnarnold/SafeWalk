import type { FastifyPluginAsync, FastifyRequest, FastifyReply } from 'fastify';
import crypto from 'node:crypto';
import { ShareStartSchema, ShareLocationSchema, ShareStopSchema } from '../schemas/share.js';
import {
  cacheExpireStrict,
  cacheGetStrict,
  cacheSetStrict,
} from '../services/redis-cache.js';
import { publish } from '../services/redis-pubsub.js';
import { config } from '../config.js';
import { setPrivateNoStore } from '../utils/private-response.js';

// Stay inside Mapbox's one-hour maximum for temporary tokens.
const SHARE_TTL = 50 * 60;
const GRACE_TTL = 30;

function generateSessionId(): string {
  return crypto.randomBytes(16).toString('base64url');
}

function generateWriterToken(): string {
  return crypto.randomBytes(32).toString('base64url');
}

export function hashWriterToken(writerToken: string): string {
  return crypto.createHash('sha256').update(writerToken).digest('hex');
}

export function writerTokenMatches(writerToken: string, expectedHash: string): boolean {
  const actual = Buffer.from(hashWriterToken(writerToken), 'hex');
  const expected = Buffer.from(expectedHash, 'hex');
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

async function mintMapboxToken(): Promise<string> {
  if (!config.mapboxToken || !config.mapboxUsername) {
    throw new Error('Mapbox token minting is not configured');
  }
  const expires = new Date(Date.now() + 55 * 60 * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  const payload = {
    note: 'share-my-walk watcher token',
    expires,
    scopes: ['styles:read', 'fonts:read', 'tilesets:read'],
  };

  const url = new URL(`https://api.mapbox.com/tokens/v2/${config.mapboxUsername}`);
  url.searchParams.set('access_token', config.mapboxToken);

  const response = await fetch(url.toString(), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10000),
  });

  if (!response.ok) throw new Error('Failed to mint Mapbox token for watcher');
  const data = (await response.json()) as { token?: string };
  if (!data.token) {
    throw new Error('Mapbox token response did not include a token');
  }
  return data.token;
}

async function startShare(request: FastifyRequest, reply: FastifyReply) {
  setPrivateNoStore(reply);
  const parseResult = ShareStartSchema.safeParse(request.body);
  if (!parseResult.success) {
    return reply.status(400).send({ error: 'Invalid request', details: parseResult.error.issues });
  }

  const { routeGeoJSON, destinationName } = parseResult.data;
  const city = (request.params as { city?: string }).city ?? 'boston';
  const sessionId = generateSessionId();
  const writerToken = generateWriterToken();

  let mapboxToken = '';
  try {
    mapboxToken = await mintMapboxToken();
  } catch {
    request.log.error('Failed to mint Mapbox token for share session');
  }

  const sessionData = {
    routeGeoJSON,
    destinationName,
    city,
    startedAt: Date.now(),
    mapboxToken,
    writerTokenHash: hashWriterToken(writerToken),
  };

  await cacheSetStrict(`share:${sessionId}`, sessionData, SHARE_TTL);

  return {
    sessionId,
    writerToken,
    watchUrl: `${config.publicBaseUrl.replace(/\/$/, '')}/watch/${sessionId}`,
  };
}

async function updateLocation(request: FastifyRequest, reply: FastifyReply) {
  setPrivateNoStore(reply);
  const parseResult = ShareLocationSchema.safeParse(request.body);
  if (!parseResult.success) {
    return reply.status(400).send({ error: 'Invalid request', details: parseResult.error.issues });
  }

  const { sessionId, writerToken, lat, lon } = parseResult.data;

  const session = await cacheGetStrict<{ writerTokenHash: string }>(`share:${sessionId}`);
  if (!session) {
    return reply.status(404).send({ error: 'Session not found' });
  }
  if (!writerTokenMatches(writerToken, session.writerTokenHash)) {
    return reply.status(403).send({ error: 'Invalid share writer token' });
  }

  const locationData = { lat, lon, ts: Date.now() };

  await cacheSetStrict(`share:${sessionId}:loc`, locationData, SHARE_TTL);
  await publish(`share:${sessionId}`, JSON.stringify(locationData));

  return { ok: true };
}

async function stopShare(request: FastifyRequest, reply: FastifyReply) {
  setPrivateNoStore(reply);
  const parseResult = ShareStopSchema.safeParse(request.body);
  if (!parseResult.success) {
    return reply.status(400).send({ error: 'Invalid request', details: parseResult.error.issues });
  }

  const { sessionId, writerToken, reason } = parseResult.data;

  const session = await cacheGetStrict<{ writerTokenHash: string }>(`share:${sessionId}`);
  if (!session) {
    return reply.status(404).send({ error: 'Session not found' });
  }
  if (!writerTokenMatches(writerToken, session.writerTokenHash)) {
    return reply.status(403).send({ error: 'Invalid share writer token' });
  }

  await publish(`share:${sessionId}`, JSON.stringify({ type: 'ended', reason }));

  await cacheExpireStrict(`share:${sessionId}`, GRACE_TTL);
  await cacheExpireStrict(`share:${sessionId}:loc`, GRACE_TTL);

  return { ok: true };
}

export const shareRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.post('/:city/share/start', { config: { rateLimit: { max: 5, timeWindow: '1 minute' } } }, startShare);
  fastify.post('/:city/share/location', { config: { rateLimit: { max: 15, timeWindow: '1 minute' } } }, updateLocation);
  fastify.post('/:city/share/stop', stopShare);
};
