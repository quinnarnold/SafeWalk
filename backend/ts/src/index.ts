import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { config, validateConfig } from './config.js';
import { registerRoutes } from './routes/index.js';
import { closeRedis, connectRedis } from './services/redis-cache.js';
import { verifyRequestSignature } from './middleware/auth.js';
import { checkPythonHealth } from './services/python-client.js';

async function waitForPython(maxAttempts = 60): Promise<boolean> {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const healthy = await checkPythonHealth();
    if (healthy) {
      console.log(`[startup] Python ready after ${attempt} attempt(s)`);
      return true;
    }
    if (attempt < maxAttempts) {
      const delayMs = attempt <= 10 ? 500 : 2000;
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }
  return false;
}

async function buildServer() {
  const fastify = Fastify({
    trustProxy: config.trustProxy,
    disableRequestLogging: true,
    logger: {
      level: config.logLevel,
      transport:
        config.nodeEnv === 'development'
          ? {
              target: 'pino-pretty',
              options: {
                translateTime: 'HH:MM:ss Z',
                ignore: 'pid,hostname',
              },
            }
          : undefined,
    },
  });

  const allowedOrigins = [
    ...config.allowedOrigins,
    new URL(config.publicBaseUrl).origin,
    ...(config.nodeEnv === 'development' ? ['http://localhost:3000', 'http://127.0.0.1:3000'] : []),
  ];

  await fastify.register(cors, {
    origin: (origin, callback) => {
      if (!origin) {
        callback(null, true);
        return;
      }
      if (allowedOrigins.includes(origin)) {
        callback(null, true);
      } else {
        callback(new Error('CORS origin not allowed'), false);
      }
    },
    methods: ['GET', 'POST', 'OPTIONS'],
    credentials: true,
  });

  await fastify.register(helmet, {
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false,
    hsts: {
      maxAge: 31536000,
      includeSubDomains: true,
    },
  });

  await fastify.register(rateLimit, {
    max: 100,
    timeWindow: '1 minute',
    keyGenerator: (request) => request.ip ?? 'unknown',
    errorResponseBuilder: (request, context) => ({
      error: 'Too Many Requests',
      message: `Rate limit exceeded. Try again in ${Math.ceil(context.ttl / 1000)} seconds.`,
      statusCode: 429,
    }),
  });

  fastify.addHook('preHandler', verifyRequestSignature);

  await fastify.register(registerRoutes);

  const signals: NodeJS.Signals[] = ['SIGINT', 'SIGTERM'];
  for (const signal of signals) {
    process.on(signal, async () => {
      fastify.log.info(`Received ${signal}, shutting down...`);
      await fastify.close();
      await closeRedis();
      process.exit(0);
    });
  }

  return fastify;
}

async function start() {
  validateConfig();

  const pythonReady = await waitForPython();
  if (!pythonReady) {
    console.error('[startup] FATAL: Python service unavailable');
    process.exit(1);
  }

  connectRedis().then(ok => {
    if (ok) console.log('[startup] Redis connected eagerly');
    else console.warn('[startup] Redis eager connect failed, will retry on first use');
  });

  const fastify = await buildServer();

  try {
    await fastify.listen({
      port: config.port,
      host: config.host,
    });

    fastify.log.info(`SafeWalk API running on http://${config.host}:${config.port}`);
    fastify.log.info(`City: ${config.cityName}`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
}

start();
