/**
 * Tests for Zod schemas.
 */
import { describe, it, expect } from 'bun:test';
import { RouteQuerySchema, RouteParamsSchema } from '../src/schemas/route.js';

describe('RouteQuerySchema', () => {
  it('should validate valid query params', () => {
    const result = RouteQuerySchema.safeParse({
      src_lat: '42.361',
      src_lon: '-71.057',
      dst_lat: '42.355',
      dst_lon: '-71.065',
      bin: '2',
    });

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.src_lat).toBe(42.361);
      expect(result.data.src_lon).toBe(-71.057);
      expect(result.data.bin).toBe(2);
      expect(result.data.speed_mps).toBe(1.4); // default
    }
  });

  it('should reject invalid coordinates', () => {
    const result = RouteQuerySchema.safeParse({
      src_lat: '100', // Invalid: > 90
      src_lon: '-71.057',
      dst_lat: '42.355',
      dst_lon: '-71.065',
    });

    expect(result.success).toBe(false);
  });

  it('should reject invalid bin', () => {
    const result = RouteQuerySchema.safeParse({
      src_lat: '42.361',
      src_lon: '-71.057',
      dst_lat: '42.355',
      dst_lon: '-71.065',
      bin: '5', // Invalid: > 3
    });

    expect(result.success).toBe(false);
  });
});

describe('RouteParamsSchema', () => {
  it('should validate valid city param', () => {
    const result = RouteParamsSchema.safeParse({ city: 'boston' });
    expect(result.success).toBe(true);
  });

  it('should reject empty city', () => {
    const result = RouteParamsSchema.safeParse({ city: '' });
    expect(result.success).toBe(false);
  });
});
