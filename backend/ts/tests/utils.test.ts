/**
 * Tests for utility functions.
 */
import { describe, it, expect } from 'bun:test';
import { cacheKey, routeCacheKey, mapMatchCacheKey } from '../src/utils/cache-key.js';
import {
  createLineString,
  createRouteFeature,
  createFeatureCollection,
} from '../src/utils/geojson.js';

describe('cacheKey', () => {
  it('should generate consistent hash', () => {
    const key1 = cacheKey('test', 'a', 'b', 123);
    const key2 = cacheKey('test', 'a', 'b', 123);
    expect(key1).toBe(key2);
  });

  it('should generate different hashes for different inputs', () => {
    const key1 = cacheKey('test', 'a');
    const key2 = cacheKey('test', 'b');
    expect(key1).not.toBe(key2);
  });
});

describe('routeCacheKey', () => {
  it('should round coordinates to 6 decimal places', () => {
    const key1 = routeCacheKey('boston', 42.3611234567, -71.0572345678, 42.355, -71.065, 2, 1.4);
    const key2 = routeCacheKey('boston', 42.3611234568, -71.0572345679, 42.355, -71.065, 2, 1.4);
    expect(key1).toBe(key2);
  });
});

describe('mapMatchCacheKey', () => {
  it('should include coords length', () => {
    const coords = [[1, 2], [3, 4]];
    const key = mapMatchCacheKey(coords);
    expect(key).toBeTruthy();
  });
});

describe('createLineString', () => {
  it('should create valid LineString geometry', () => {
    const coords = [[-71.057, 42.361], [-71.065, 42.355]];
    const geom = createLineString(coords);

    expect(geom.type).toBe('LineString');
    expect(geom.coordinates).toEqual(coords);
  });
});

describe('createRouteFeature', () => {
  it('should create valid Feature', () => {
    const geom = createLineString([[-71.057, 42.361]]);
    const feature = createRouteFeature('shortest', geom, {
      distance_m: 1000,
      time_s: 714,
      pred_risk: 0.05,
    });

    expect(feature.type).toBe('Feature');
    expect(feature.properties.type).toBe('shortest');
    expect(feature.properties.distance_m).toBe(1000);
  });
});

describe('createFeatureCollection', () => {
  it('should create valid FeatureCollection', () => {
    const geom = createLineString([[-71.057, 42.361]]);
    const feature = createRouteFeature('shortest', geom, {
      distance_m: 1000,
      time_s: 714,
      pred_risk: 0.05,
    });

    const collection = createFeatureCollection([feature]);

    expect(collection.type).toBe('FeatureCollection');
    expect(collection.features).toHaveLength(1);
  });
});
