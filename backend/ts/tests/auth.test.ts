import { describe, it, expect, beforeEach, mock } from 'bun:test';

const mockConfig = {
  appAttestAppId: 'com.test.safewalk',
  nodeEnv: 'development',
};
mock.module('../src/config.js', () => ({ config: mockConfig }));

let mockVerifyAssertion = mock(() => Promise.resolve({ valid: false }));
mock.module('../src/services/app-attest.js', () => ({
  verifyAssertion: (...args: unknown[]) => mockVerifyAssertion(...args),
}));

import {
  APP_ATTEST_CREDENTIAL_NOT_FOUND,
  verifyRequestSignature,
} from '../src/middleware/auth.js';

function makeRequest(overrides: Record<string, unknown> = {}) {
  return {
    url: '/boston/route?src_lat=42',
    method: 'GET',
    headers: {},
    log: { warn: () => {}, error: () => {} },
    ...overrides,
  };
}

function makeReply() {
  let statusCode = 200;
  let body: unknown = null;
  return {
    code(c: number) { statusCode = c; return this; },
    send(b: unknown) { body = b; return this; },
    get statusCode() { return statusCode; },
    get body() { return body; },
  };
}

describe('verifyRequestSignature - public paths', () => {
  const publicPaths = [
    '/',
    '/health',
    '/cities',
    '/watch/abc123',
    '/watch/abc123/page',
    '/boston/attest/challenge',
    '/boston/attest/verify',
  ];

  for (const path of publicPaths) {
    it(`skips auth for public path: ${path}`, async () => {
      const req = makeRequest({ url: path });
      const reply = makeReply();
      await verifyRequestSignature(req as any, reply as any);
      expect(reply.statusCode).toBe(200);
      expect(reply.body).toBeNull();
    });
  }
});

describe('verifyRequestSignature - non-public paths require App Attest', () => {
  const privatePaths = [
    '/boston/route',
    '/boston/transit-route',
    '/boston/mapbox-temporary-token',
    '/newyork/mapbox-temporary-token',
    '/share/start',
    '/share/location',
    '/share/stop',
  ];

  for (const path of privatePaths) {
    it(`rejects missing App Attest headers for: ${path}`, async () => {
      const req = makeRequest({ url: path, headers: {} });
      const reply = makeReply();
      await verifyRequestSignature(req as any, reply as any);
      expect(reply.statusCode).toBe(401);
      expect((reply.body as any).message).toContain('App Attest authentication required');
    });
  }
});

describe('verifyRequestSignature - App Attest', () => {
  beforeEach(() => {
    mockVerifyAssertion = mock(() => Promise.resolve({ valid: false }));
  });

  it('accepts valid App Attest assertion', async () => {
    mockVerifyAssertion = mock(() => Promise.resolve({ valid: true }));
    const ts = Math.floor(Date.now() / 1000);
    const req = makeRequest({
      url: '/boston/route',
      headers: {
        'x-app-attest-keyid': 'test-key-id',
        'x-app-attest-assertion': 'dGVzdA==',
        'x-timestamp': String(ts),
      },
    });
    const reply = makeReply();
    await verifyRequestSignature(req as any, reply as any);
    expect(reply.statusCode).toBe(200);
    expect(mockVerifyAssertion).toHaveBeenCalledTimes(1);
  });

  it('rejects missing timestamp', async () => {
    const req = makeRequest({
      url: '/boston/route',
      headers: {
        'x-app-attest-keyid': 'test-key-id',
        'x-app-attest-assertion': 'dGVzdA==',
      },
    });
    const reply = makeReply();
    await verifyRequestSignature(req as any, reply as any);
    expect(reply.statusCode).toBe(401);
    expect((reply.body as any).message).toContain('Missing timestamp');
  });

  it('rejects expired timestamp', async () => {
    const oldTs = Math.floor(Date.now() / 1000) - 360;
    const req = makeRequest({
      url: '/boston/route',
      headers: {
        'x-app-attest-keyid': 'key',
        'x-app-attest-assertion': 'dGVzdA==',
        'x-timestamp': String(oldTs),
      },
    });
    const reply = makeReply();
    await verifyRequestSignature(req as any, reply as any);
    expect(reply.statusCode).toBe(401);
    expect((reply.body as any).message).toContain('expired');
  });

  it('rejects NaN timestamp', async () => {
    const req = makeRequest({
      url: '/boston/route',
      headers: {
        'x-app-attest-keyid': 'key',
        'x-app-attest-assertion': 'dGVzdA==',
        'x-timestamp': 'not-a-number',
      },
    });
    const reply = makeReply();
    await verifyRequestSignature(req as any, reply as any);
    expect(reply.statusCode).toBe(401);
    expect((reply.body as any).message).toContain('expired');
  });

  it('rejects invalid assertion', async () => {
    const ts = Math.floor(Date.now() / 1000);
    const req = makeRequest({
      url: '/boston/route',
      headers: {
        'x-app-attest-keyid': 'key',
        'x-app-attest-assertion': 'dGVzdA==',
        'x-timestamp': String(ts),
      },
    });
    const reply = makeReply();
    await verifyRequestSignature(req as any, reply as any);
    expect(reply.statusCode).toBe(401);
    expect((reply.body as any).message).toContain('Invalid App Attest');
    expect((reply.body as any).code).toBeUndefined();
  });

  it('returns the stable client recovery code only for a missing stored credential', async () => {
    mockVerifyAssertion = mock(() => Promise.resolve({
      valid: false,
      reason: 'no-stored-credential',
    }));
    const warnings: unknown[][] = [];
    const ts = Math.floor(Date.now() / 1000);
    const req = makeRequest({
      url: '/boston/route',
      headers: {
        'x-app-attest-keyid': 'sensitive-key-id',
        'x-app-attest-assertion': 'sensitive-assertion',
        'x-timestamp': String(ts),
      },
      log: {
        warn: (...args: unknown[]) => warnings.push(args),
        error: () => {},
      },
    });
    const reply = makeReply();

    await verifyRequestSignature(req as any, reply as any);

    expect(reply.statusCode).toBe(401);
    expect(reply.body).toEqual({
      error: 'Unauthorized',
      code: APP_ATTEST_CREDENTIAL_NOT_FOUND,
      message: 'App Attest credential is no longer available',
    });
    const observable = JSON.stringify({ body: reply.body, warnings });
    expect(observable).not.toContain('sensitive-key-id');
    expect(observable).not.toContain('sensitive-assertion');
  });

  it('keeps the Swift client and server recovery-code contract aligned', async () => {
    const swiftSource = await Bun.file(
      new URL('../../../frontend/SafeWalk/ApiService.swift', import.meta.url),
    ).text();
    expect(swiftSource).toContain(
      `appAttestCredentialNotFoundCode = "${APP_ATTEST_CREDENTIAL_NOT_FOUND}"`,
    );
    expect(swiftSource).toContain('JSONDecoder().decode(ErrorEnvelope.self, from: data)');
  });

  it('binds path, sorted query, and body hash into the assertion', async () => {
    mockVerifyAssertion = mock(() => Promise.resolve({ valid: true }));
    const ts = Math.floor(Date.now() / 1000);
    const req = makeRequest({
      url: '/boston/route?src_lat=42&src_lon=-71',
      method: 'GET',
      headers: {
        'x-app-attest-keyid': 'key',
        'x-app-attest-assertion': 'dGVzdA==',
        'x-timestamp': String(ts),
      },
    });
    const reply = makeReply();
    await verifyRequestSignature(req as any, reply as any);
    expect(reply.statusCode).toBe(200);
    const call = mockVerifyAssertion.mock.calls[0];
    expect(call[2]).toBe([
      String(ts),
      'GET',
      '/boston/route',
      'src_lat=42&src_lon=-71',
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    ].join('\n'));
    expect(call[3]).toBe(mockConfig.appAttestAppId);
  });
});
