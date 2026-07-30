import { describe, test, expect, mock } from 'bun:test';

mock.module('redis-errors', () => {
  class RedisError extends Error {}
  class ParserError extends RedisError {}
  class ReplyError extends RedisError {}
  class AbortError extends RedisError {}
  class InterruptError extends AbortError {}
  return { RedisError, ParserError, ReplyError, AbortError, InterruptError };
});

mock.module('ioredis', () => {
  const Redis = function () {
    return {
      get: () => Promise.resolve(null),
      set: () => Promise.resolve('OK'),
      del: () => Promise.resolve(1),
      expire: () => Promise.resolve(1),
      quit: () => Promise.resolve('OK'),
      on: () => {},
    };
  };
  return { default: Redis };
});

import {
  otpLegToTransitLeg,
  currentTimeIso,
  transitCacheKey,
} from '../src/services/transit-orchestrator.js';
import type { OtpLeg } from '../src/services/otp-client.js';

describe('transitCacheKey', () => {
  test('hashes all parameters instead of exposing coordinates', () => {
    const key = transitCacheKey('boston', 42.36, -71.06, 42.35, -71.08, 2, 1.4);
    expect(key).toMatch(/^[a-f0-9]{40}$/);
    expect(key).not.toContain('42.36');
  });

  test('changes when departAt changes', () => {
    const first = transitCacheKey('boston', 42.36, -71.06, 42.35, -71.08, 2, 1.4, '2026-03-18T08:00');
    const second = transitCacheKey('boston', 42.36, -71.06, 42.35, -71.08, 2, 1.4, '2026-03-18T09:00');
    expect(first).not.toBe(second);
  });
});

describe('currentTimeIso', () => {
  test('returns a valid ISO 8601 string close to now', () => {
    const iso = currentTimeIso();
    const parsed = new Date(iso).getTime();
    const now = Date.now();
    expect(Math.abs(parsed - now)).toBeLessThan(1000);
  });
});

describe('otpLegToTransitLeg', () => {
  test('converts OTP walk leg to transit leg', () => {
    const otpLeg: OtpLeg = {
      mode: 'WALK',
      from: { lat: 42.36, lon: -71.06, name: 'Origin', stop: null },
      to: { lat: 42.356, lon: -71.062, name: 'Station', stop: { gtfsId: 'mbta:1' } },
      startTime: '2026-03-18T08:00:00-04:00',
      endTime: '2026-03-18T08:07:00-04:00',
      duration: 420,
      distance: 350,
      legGeometry: { points: '_p~iF~ps|U', length: 1 },
      route: null,
      intermediateStops: null,
    };
    const leg = otpLegToTransitLeg(otpLeg);
    expect(leg.mode).toBe('WALK');
    expect(leg.from.name).toBe('Origin');
    expect(leg.to.stopId).toBe('mbta:1');
    expect(leg.geometry.type).toBe('LineString');
  });
});
