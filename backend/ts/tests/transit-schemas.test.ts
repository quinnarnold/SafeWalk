import { describe, test, expect } from 'bun:test';
import {
  TransitRouteQuerySchema,
  TransitLegSchema,
  TransitItinerarySchema,
} from '../src/schemas/transit-route.js';

describe('TransitRouteQuerySchema', () => {
  test('validates valid transit route request', () => {
    const result = TransitRouteQuerySchema.safeParse({
      src_lat: '42.36',
      src_lon: '-71.06',
      dst_lat: '42.35',
      dst_lon: '-71.08',
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.bin).toBe(2);
      expect(result.data.depart_at).toBeUndefined();
    }
  });

  test('accepts optional depart_at ISO timestamp', () => {
    const result = TransitRouteQuerySchema.safeParse({
      src_lat: '42.36',
      src_lon: '-71.06',
      dst_lat: '42.35',
      dst_lon: '-71.08',
      depart_at: '2026-03-18T08:00:00-04:00',
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.depart_at).toBe('2026-03-18T08:00:00-04:00');
    }
  });

  test('rejects missing coordinates', () => {
    const result = TransitRouteQuerySchema.safeParse({ src_lat: '42.36' });
    expect(result.success).toBe(false);
  });
});

describe('TransitLegSchema', () => {
  test('validates a walk leg', () => {
    const result = TransitLegSchema.safeParse({
      mode: 'WALK',
      from: { lat: 42.36, lon: -71.06, name: 'Origin' },
      to: { lat: 42.356, lon: -71.062, name: 'Park Street' },
      startTime: '2026-03-18T08:00:00-04:00',
      endTime: '2026-03-18T08:07:00-04:00',
      duration: 420,
      distance_m: 350,
      geometry: { type: 'LineString', coordinates: [[-71.06, 42.36], [-71.062, 42.356]] },
    });
    expect(result.success).toBe(true);
  });

  test('validates a transit leg with route info', () => {
    const result = TransitLegSchema.safeParse({
      mode: 'SUBWAY',
      from: { lat: 42.356, lon: -71.062, name: 'Park Street', stopId: 'mbta:place-pktrm' },
      to: { lat: 42.373, lon: -71.119, name: 'Harvard', stopId: 'mbta:place-harvd' },
      startTime: '2026-03-18T08:10:00-04:00',
      endTime: '2026-03-18T08:28:00-04:00',
      duration: 1080,
      distance_m: 5200,
      geometry: { type: 'LineString', coordinates: [[-71.062, 42.356], [-71.119, 42.373]] },
      route: { shortName: 'Red', longName: 'Red Line', color: 'DA291C', agency: 'MBTA' },
      intermediateStops: [{ name: 'Charles/MGH', lat: 42.361, lon: -71.071 }],
    });
    expect(result.success).toBe(true);
  });
});
