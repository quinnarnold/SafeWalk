import { describe, it, expect, beforeEach, mock } from 'bun:test';
import crypto from 'crypto';

// Mock Redis before importing app-attest
const redisStore = new Map<string, string>();
const mockRedis = {
  get: mock((key: string) => Promise.resolve(redisStore.get(key) ?? null)),
  set: mock((...args: unknown[]) => {
    const [key, value] = args as [string, string];
    redisStore.set(key, value);
    return Promise.resolve('OK');
  }),
  del: mock((key: string) => {
    const existed = redisStore.has(key);
    redisStore.delete(key);
    return Promise.resolve(existed ? 1 : 0);
  }),
  eval: mock(() => Promise.resolve(1)),
  quit: () => Promise.resolve('OK'),
};

mock.module('../src/services/redis-cache.js', () => ({
  getRedis: () => mockRedis,
  cacheGet: () => Promise.resolve(null),
  cacheSet: () => Promise.resolve(),
  cacheGetStrict: () => Promise.resolve(null),
  cacheSetStrict: () => Promise.resolve(),
  cacheExpireStrict: () => Promise.resolve(),
}));

import {
  generateChallenge,
  storeChallenge,
  consumeChallenge,
  verifyAttestation,
} from '../src/services/app-attest.js';

beforeEach(() => {
  redisStore.clear();
  mockRedis.get.mockClear();
  mockRedis.set.mockClear();
  mockRedis.del.mockClear();
  mockRedis.eval.mockClear();
});

describe('generateChallenge', () => {
  it('returns base64url string', () => {
    const challenge = generateChallenge();
    expect(challenge).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  it('returns 43-char string (32 bytes base64url)', () => {
    const challenge = generateChallenge();
    expect(challenge.length).toBeGreaterThanOrEqual(42);
    expect(challenge.length).toBeLessThanOrEqual(44);
  });

  it('generates unique values', () => {
    const challenges = new Set(Array.from({ length: 10 }, () => generateChallenge()));
    expect(challenges.size).toBe(10);
  });
});

describe('storeChallenge', () => {
  it('stores challenge in Redis with TTL', async () => {
    await storeChallenge('test-challenge');
    expect(mockRedis.set).toHaveBeenCalledWith(
      'attest:challenge:test-challenge',
      '1',
      'EX',
      300
    );
  });

  it('does not propagate Redis command details when storage fails', async () => {
    mockRedis.set.mockImplementationOnce(() =>
      Promise.reject(new Error('sensitive-challenge-capability')),
    );

    await expect(storeChallenge('sensitive-challenge-capability')).rejects.toThrow(
      'Storage operation failed',
    );
  });
});

describe('consumeChallenge', () => {
  it('returns true when challenge exists', async () => {
    redisStore.set('attest:challenge:my-challenge', '1');
    const result = await consumeChallenge('my-challenge');
    expect(result).toBe(true);
    expect(mockRedis.del).toHaveBeenCalledWith('attest:challenge:my-challenge');
  });

  it('returns false when challenge does not exist', async () => {
    mockRedis.del.mockImplementationOnce(() => Promise.resolve(0));
    const result = await consumeChallenge('nonexistent');
    expect(result).toBe(false);
  });

  it('challenge can only be consumed once', async () => {
    redisStore.set('attest:challenge:once', '1');
    const first = await consumeChallenge('once');
    expect(first).toBe(true);

    // After deletion, del returns 0
    mockRedis.del.mockImplementationOnce(() => Promise.resolve(0));
    const second = await consumeChallenge('once');
    expect(second).toBe(false);
  });

  it('does not propagate Redis command details when consumption fails', async () => {
    mockRedis.del.mockImplementationOnce(() =>
      Promise.reject(new Error('sensitive-challenge-capability')),
    );

    await expect(consumeChallenge('sensitive-challenge-capability')).rejects.toThrow(
      'Storage operation failed',
    );
  });
});

describe('verifyAttestation', () => {
  it('rejects non-apple-appattest format', async () => {
    // Encode a CBOR object with wrong fmt
    const { encode } = await import('cbor-x');
    const attestation = encode({
      fmt: 'wrong-format',
      attStmt: { x5c: [], receipt: Buffer.alloc(0) },
      authData: Buffer.alloc(37),
    });

    const result = await verifyAttestation(
      'key1',
      attestation.toString('base64'),
      'challenge',
      'com.test.app'
    );
    expect(result.valid).toBe(false);
    expect(result.error).toContain('Invalid attestation format');
  });

  it('rejects missing certificate chain', async () => {
    const { encode } = await import('cbor-x');
    const attestation = encode({
      fmt: 'apple-appattest',
      attStmt: { x5c: [Buffer.alloc(10)], receipt: Buffer.alloc(0) },
      authData: Buffer.alloc(37),
    });

    const result = await verifyAttestation(
      'key1',
      attestation.toString('base64'),
      'challenge',
      'com.test.app'
    );
    expect(result.valid).toBe(false);
    expect(result.error).toContain('Missing certificate chain');
  });

  it('rejects invalid base64 gracefully', async () => {
    const result = await verifyAttestation(
      'key1',
      'not-valid-cbor-data!!!',
      'challenge',
      'com.test.app'
    );
    expect(result.valid).toBe(false);
    expect(result.error).toBeDefined();
  });
});

// verifyAssertion integration tests are in app-attest-assertion.test.ts
// (isolated to avoid module mock conflicts with auth.test.ts)
