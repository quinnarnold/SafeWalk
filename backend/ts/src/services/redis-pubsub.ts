import Redis from 'ioredis';
import { config } from '../config.js';

let publisher: Redis | null = null;

function getPublisher(): Redis {
  if (!publisher) {
    publisher = new Redis({
      host: config.redisHost,
      port: config.redisPort,
      password: config.redisPassword,
      lazyConnect: true,
      maxRetriesPerRequest: 3,
    });
  }
  return publisher;
}

export async function publish(channel: string, message: string): Promise<void> {
  const client = getPublisher();
  try {
    await client.publish(channel, message);
  } catch {
    throw new Error('Storage operation failed');
  }
}

export async function subscribe(client: Redis, channel: string): Promise<void> {
  try {
    await client.subscribe(channel);
  } catch {
    throw new Error('Storage operation failed');
  }
}

export async function closeSubscriber(client: Redis): Promise<void> {
  try {
    await client.unsubscribe();
    await client.quit();
  } catch {
    // Connection cleanup is best-effort and must not expose Redis command data.
  }
}

export function createSubscriber(): Redis {
  return new Redis({
    host: config.redisHost,
    port: config.redisPort,
    password: config.redisPassword,
    lazyConnect: true,
    maxRetriesPerRequest: 3,
  });
}
