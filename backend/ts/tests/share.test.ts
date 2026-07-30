import { describe, it, expect } from 'bun:test';
import {
  ShareStartSchema,
  ShareLocationSchema,
  ShareStopSchema,
  ShareSessionParamsSchema,
} from '../src/schemas/share';
import { hashWriterToken, writerTokenMatches } from '../src/routes/share';

describe('ShareStartSchema', () => {
  it('accepts valid start request', () => {
    const result = ShareStartSchema.safeParse({
      routeGeoJSON: { type: 'FeatureCollection', features: [] },
      destinationName: 'Home',
    });
    expect(result.success).toBe(true);
  });

  it('rejects destinationName over 100 chars', () => {
    const result = ShareStartSchema.safeParse({
      routeGeoJSON: { type: 'FeatureCollection', features: [] },
      destinationName: 'x'.repeat(101),
    });
    expect(result.success).toBe(false);
  });
});

describe('ShareLocationSchema', () => {
  it('accepts valid location update', () => {
    const result = ShareLocationSchema.safeParse({
      sessionId: 'a1b2c3d4e5f6g7h8i9j0kl',
      writerToken: 'a'.repeat(43),
      lat: 42.3601,
      lon: -71.0589,
    });
    expect(result.success).toBe(true);
  });

  it('rejects missing sessionId', () => {
    const result = ShareLocationSchema.safeParse({
      lat: 42.3601,
      lon: -71.0589,
    });
    expect(result.success).toBe(false);
  });
});

describe('ShareStopSchema', () => {
  it('accepts valid stop request', () => {
    const result = ShareStopSchema.safeParse({
      sessionId: 'a1b2c3d4e5f6g7h8i9j0kl',
      writerToken: 'a'.repeat(43),
      reason: 'arrived',
    });
    expect(result.success).toBe(true);
  });

  it('rejects invalid reason', () => {
    const result = ShareStopSchema.safeParse({
      sessionId: 'a1b2c3d4e5f6g7h8i9j0kl',
      writerToken: 'a'.repeat(43),
      reason: 'exploded',
    });
    expect(result.success).toBe(false);
  });
});

describe('ShareSessionParamsSchema', () => {
  it('accepts valid sessionId', () => {
    const result = ShareSessionParamsSchema.safeParse({
      sessionId: 'a1b2c3d4e5f6g7h8i9j0kl',
    });
    expect(result.success).toBe(true);
  });
});

describe('session ID generation', () => {
  it('generates URL-safe base64 IDs', () => {
    const crypto = require('node:crypto');
    const id = crypto.randomBytes(16).toString('base64url');
    expect(id.length).toBe(22);
    expect(/^[A-Za-z0-9_-]+$/.test(id)).toBe(true);
  });
});

describe('share writer capability', () => {
  it('accepts only the token whose hash is stored with the session', () => {
    const token = 'a'.repeat(43);
    const storedHash = hashWriterToken(token);
    expect(writerTokenMatches(token, storedHash)).toBe(true);
    expect(writerTokenMatches('b'.repeat(43), storedHash)).toBe(false);
  });
});
