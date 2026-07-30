import Redis from 'ioredis';
import { config } from '../config.js';

let redis: Redis | null = null;

export class StorageUnavailableError extends Error {
  constructor() {
    super('Storage operation failed');
    this.name = 'StorageUnavailableError';
  }
}

export function getRedis(): Redis {
  if (!redis) {
    redis = new Redis({
      host: config.redisHost,
      port: config.redisPort,
      password: config.redisPassword,
      lazyConnect: true,
      maxRetriesPerRequest: 3,
      retryStrategy(times) {
        return Math.min(times * 100, 30000);
      },
    });

    redis.on('error', () => {
      console.error('[Redis] Connection error');
    });

    redis.on('connect', () => {
      console.log('[Redis] Connected');
    });
  }
  return redis;
}

export async function connectRedis(): Promise<boolean> {
  try {
    const client = getRedis();
    await client.connect();
    return true;
  } catch {
    console.error('[Redis] Failed to connect at startup');
    return false;
  }
}

export async function cacheGet<T>(key: string): Promise<T | null> {
  try {
    return await cacheGetStrict<T>(key);
  } catch {
    console.error('[Redis] Cache read failed');
    return null;
  }
}

export async function cacheSet<T>(key: string, value: T, ttl: number): Promise<void> {
  try {
    await cacheSetStrict(key, value, ttl);
  } catch {
    console.error('[Redis] Cache write failed');
  }
}

export async function cacheDel(key: string): Promise<void> {
  try {
    const client = getRedis();
    await client.del(key);
  } catch {
    console.error('[Redis] Cache delete failed');
  }
}

export async function cacheGetStrict<T>(key: string): Promise<T | null> {
  let value: string | null;
  try {
    value = await getRedis().get(key);
  } catch {
    throw new StorageUnavailableError();
  }
  if (value === null) {
    return null;
  }

  try {
    return JSON.parse(value) as T;
  } catch {
    return value as unknown as T;
  }
}

export async function cacheSetStrict<T>(key: string, value: T, ttl: number): Promise<void> {
  try {
    await getRedis().set(key, JSON.stringify(value), 'EX', ttl);
  } catch {
    throw new StorageUnavailableError();
  }
}

export async function cacheExpireStrict(key: string, ttl: number): Promise<void> {
  try {
    await getRedis().expire(key, ttl);
  } catch {
    throw new StorageUnavailableError();
  }
}

export async function checkRedisHealth(): Promise<boolean> {
  try {
    const client = getRedis();
    const result = await client.ping();
    return result === 'PONG';
  } catch {
    return false;
  }
}

export async function closeRedis(): Promise<void> {
  if (redis) {
    await redis.quit();
    redis = null;
  }
}
