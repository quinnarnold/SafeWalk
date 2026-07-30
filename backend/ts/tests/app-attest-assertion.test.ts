/**
 * verifyAssertion integration tests.
 *
 * Isolated from app-attest.test.ts because auth.test.ts globally mocks the
 * app-attest module. This file mocks only redis-cache so the real
 * verifyAssertion runs with controlled Redis state.
 */
import { describe, it, expect, beforeEach, mock } from 'bun:test';
import crypto from 'crypto';

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

const { verifyAssertion } = await import('../src/services/app-attest.js');

const keyId = 'test-assertion-key';
const appId = 'com.test.app';

function makeCredentialAndAssertion(
  signCount: number,
  assertionExtensions = { validationCategory: 4, bundleVersion: '1' },
) {
  const { encode } = require('cbor-x');
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
  });

  const publicKeyDer = publicKey.export({ type: 'spki', format: 'der' });

  const credential = {
    publicKey: publicKeyDer.toString('base64'),
    receipt: Buffer.alloc(32).toString('base64'),
    signCount: signCount - 1,
    validationCategory: 4,
    bundleVersion: '1',
    createdAt: Date.now(),
  };

  const rpIdHash = crypto.createHash('sha256').update(appId).digest();
  const flags = Buffer.from([0x81]);
  const signCountBuf = Buffer.alloc(4);
  signCountBuf.writeUInt32BE(signCount, 0);
  const extensions = encode(assertionExtensions);
  const authenticatorData = Buffer.concat([rpIdHash, flags, signCountBuf, extensions]);

  const clientData = `${Math.floor(Date.now() / 1000)}GET/boston/route`;
  const clientDataHash = crypto.createHash('sha256').update(clientData).digest();
  const nonce = crypto
    .createHash('sha256')
    .update(Buffer.concat([authenticatorData, clientDataHash]))
    .digest();

  // Apple App Attest signs ECDSA-SHA256 over nonce (not over authData||cdh).
  const signature = crypto.sign('sha256', nonce, privateKey);

  const assertionCbor = encode({ signature, authenticatorData });

  return {
    credential,
    assertionBase64: assertionCbor.toString('base64'),
    clientData,
  };
}

beforeEach(() => {
  redisStore.clear();
  mockRedis.get.mockClear();
  mockRedis.set.mockClear();
  mockRedis.del.mockClear();
  mockRedis.eval.mockClear();
});

describe('verifyAssertion', () => {
  it('returns false when no stored credential', async () => {
    const result = await verifyAssertion('unknown-key', 'dGVzdA==', 'data', appId);
    expect(result.valid).toBe(false);
    expect(result.reason).toBe('no-stored-credential');
  });

  it('verifies valid assertion with correct key and counter', async () => {
    const { credential, assertionBase64, clientData } = makeCredentialAndAssertion(1);
    redisStore.set(`attest:key:${keyId}`, JSON.stringify(credential));

    const result = await verifyAssertion(keyId, assertionBase64, clientData, appId);
    expect(result.valid).toBe(true);
    expect(mockRedis.eval).toHaveBeenCalled();
  });

  it('rejects replayed assertion (sign count not increasing)', async () => {
    const { credential, assertionBase64, clientData } = makeCredentialAndAssertion(1);
    credential.signCount = 5;
    redisStore.set(`attest:key:${keyId}`, JSON.stringify(credential));

    const result = await verifyAssertion(keyId, assertionBase64, clientData, appId);
    expect(result.valid).toBe(false);
  });

  it('rejects assertion with wrong key', async () => {
    const { credential, assertionBase64, clientData } = makeCredentialAndAssertion(1);

    const { publicKey: otherPub } = crypto.generateKeyPairSync('ec', {
      namedCurve: 'prime256v1',
    });
    credential.publicKey = otherPub.export({ type: 'spki', format: 'der' }).toString('base64');
    redisStore.set(`attest:key:${keyId}`, JSON.stringify(credential));

    const result = await verifyAssertion(keyId, assertionBase64, clientData, appId);
    expect(result.valid).toBe(false);
  });

  it('rejects assertion with tampered client data', async () => {
    const { credential, assertionBase64 } = makeCredentialAndAssertion(1);
    redisStore.set(`attest:key:${keyId}`, JSON.stringify(credential));

    const result = await verifyAssertion(keyId, assertionBase64, 'tampered-client-data', appId);
    expect(result.valid).toBe(false);
  });

  it('rejects assertion with a mismatched bundle version', async () => {
    const { credential, assertionBase64, clientData } = makeCredentialAndAssertion(
      1,
      { validationCategory: 4, bundleVersion: '9.9' },
    );
    redisStore.set(`attest:key:${keyId}`, JSON.stringify(credential));

    const result = await verifyAssertion(keyId, assertionBase64, clientData, appId);
    expect(result.valid).toBe(false);
    expect(result.reason).toBe('invalid-validation-extensions');
  });

  it('returns false when atomicUpdateSignCount fails (TOCTOU)', async () => {
    const { credential, assertionBase64, clientData } = makeCredentialAndAssertion(1);
    redisStore.set(`attest:key:${keyId}`, JSON.stringify(credential));
    mockRedis.eval.mockImplementationOnce(() => Promise.resolve(0));

    const result = await verifyAssertion(keyId, assertionBase64, clientData, appId);
    expect(result.valid).toBe(false);
  });

  it('handles malformed CBOR assertion gracefully', async () => {
    const credential = {
      publicKey: Buffer.alloc(32).toString('base64'),
      receipt: Buffer.alloc(32).toString('base64'),
      signCount: 0,
      validationCategory: 4,
      bundleVersion: '1',
      createdAt: Date.now(),
    };
    redisStore.set(`attest:key:${keyId}`, JSON.stringify(credential));

    const result = await verifyAssertion(keyId, 'bm90LWNib3I=', 'data', appId);
    expect(result.valid).toBe(false);
  });
});
