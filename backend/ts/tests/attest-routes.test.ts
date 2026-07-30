import { describe, it, expect, beforeEach, mock } from 'bun:test';

// Mock all external dependencies
let storedChallenge: string | null = null;
let challengeConsumed = false;
let attestResult = { valid: true };

mock.module('../src/services/app-attest.js', () => ({
  generateChallenge: () => 'test-challenge-abc123',
  storeChallenge: mock((c: string) => {
    storedChallenge = c;
    return Promise.resolve();
  }),
  consumeChallenge: mock((c: string) => {
    if (challengeConsumed) return Promise.resolve(false);
    challengeConsumed = true;
    return Promise.resolve(c === storedChallenge);
  }),
  verifyAttestation: mock(() => Promise.resolve(attestResult)),
}));

mock.module('../src/config.js', () => ({
  config: {
    appAttestAppId: 'ABCDE12345.com.safewalk.app',
    nodeEnv: 'development',
  },
}));

// Mock Redis
mock.module('ioredis', () => {
  function Redis() {
    return {
      get: () => Promise.resolve(null),
      set: () => Promise.resolve('OK'),
      del: () => Promise.resolve(1),
      quit: () => Promise.resolve('OK'),
      on: () => {},
      duplicate: function() { return this; },
    };
  }
  Redis.prototype = {};
  return { default: Redis };
});

describe('attest route handlers', () => {
  beforeEach(() => {
    storedChallenge = null;
    challengeConsumed = false;
    attestResult = { valid: true };
  });

  describe('GET /:city/attest/challenge', () => {
    it('returns a challenge string', async () => {
      const { attestRoutes } = await import('../src/routes/attest.js');

      let registeredHandler: Function | null = null;
      const mockFastify = {
        get: (_path: string, _opts: unknown, handler: Function) => {
          registeredHandler = handler;
        },
        post: () => {},
      };

      await attestRoutes(mockFastify as any, {});
      expect(registeredHandler).not.toBeNull();

      const headers: Record<string, string> = {};
      const reply = {
        header(name: string, value: string) {
          headers[name.toLowerCase()] = value;
          return this;
        },
      };
      const result = await registeredHandler!({}, reply);
      expect(result).toEqual({ challenge: 'test-challenge-abc123' });
      expect(storedChallenge).toBe('test-challenge-abc123');
      expect(headers['cache-control']).toContain('no-store');
    });
  });

  describe('POST /:city/attest/verify', () => {
    let verifyHandler: Function | null = null;

    beforeEach(async () => {
      const { attestRoutes } = await import('../src/routes/attest.js');
      const mockFastify = {
        get: () => {},
        post: (_path: string, _opts: unknown, handler: Function) => {
          verifyHandler = handler;
        },
      };
      await attestRoutes(mockFastify as any, {});
      storedChallenge = 'test-challenge-abc123';
    });

    function makeReply() {
      let statusCode = 200;
      let body: unknown = null;
      const reply = {
        status(c: number) { statusCode = c; return reply; },
        send(b: unknown) { body = b; return reply; },
        header() { return reply; },
        get statusCode() { return statusCode; },
        get body() { return body; },
      };
      return reply;
    }

    it('rejects missing fields', async () => {
      const reply = makeReply();
      await verifyHandler!(
        { body: { keyId: 'k' } },
        reply
      );
      expect(reply.statusCode).toBe(400);
      expect((reply.body as any).error).toContain('Missing required');
    });

    it('rejects empty body', async () => {
      const reply = makeReply();
      await verifyHandler!(
        { body: null },
        reply
      );
      expect(reply.statusCode).toBe(400);
    });

    it('rejects consumed/expired challenge', async () => {
      challengeConsumed = true;
      const reply = makeReply();
      await verifyHandler!(
        {
          body: { keyId: 'k1', attestation: 'data', challenge: 'test-challenge-abc123' },
          log: { warn: () => {}, error: () => {} },
        },
        reply
      );
      expect(reply.statusCode).toBe(403);
      expect((reply.body as any).error).toContain('expired');
    });

    it('rejects failed attestation verification', async () => {
      attestResult = { valid: false, error: 'Bad cert' } as any;
      const reply = makeReply();
      await verifyHandler!(
        {
          body: { keyId: 'k1', attestation: 'data', challenge: 'test-challenge-abc123' },
          log: { warn: () => {}, error: () => {} },
        },
        reply
      );
      expect(reply.statusCode).toBe(403);
      expect((reply.body as any).error).toContain('failed');
    });

    it('succeeds with valid attestation', async () => {
      const reply = makeReply();
      const result = await verifyHandler!(
        {
          body: { keyId: 'k1', attestation: 'data', challenge: 'test-challenge-abc123' },
          log: { warn: () => {}, error: () => {} },
        },
        reply
      );
      expect(result).toEqual({ verified: true });
    });
  });
});
