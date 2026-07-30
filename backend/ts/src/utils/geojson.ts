/**
 * GeoJSON building utilities.
 */

/**
 * GeoJSON LineString geometry.
 */
export interface LineStringGeometry {
  type: 'LineString';
  coordinates: number[][];
}

/**
 * GeoJSON Feature with LineString geometry.
 */
export interface RouteFeature {
  type: 'Feature';
  geometry: LineStringGeometry;
  properties: {
    type: 'shortest' | 'moderate' | 'safest';
    distance_m: number;
    time_s: number;
    pred_risk?: number;
    fallback?: boolean;
  };
}

/**
 * GeoJSON FeatureCollection for routes.
 */
export interface RouteFeatureCollection {
  type: 'FeatureCollection';
  features: RouteFeature[];
}

/**
 * Create a LineString geometry.
 */
export function createLineString(coordinates: number[][]): LineStringGeometry {
  return {
    type: 'LineString',
    coordinates,
  };
}

/**
 * Create a route feature.
 */
export function createRouteFeature(
  routeType: 'shortest' | 'moderate' | 'safest',
  geometry: LineStringGeometry,
  metrics: {
    distance_m: number;
    time_s: number;
    pred_risk?: number;
    fallback?: boolean;
  }
): RouteFeature {
  return {
    type: 'Feature',
    geometry,
    properties: {
      type: routeType,
      ...metrics,
    },
  };
}

/**
 * Create a FeatureCollection from route features.
 */
export function createFeatureCollection(
  features: RouteFeature[]
): RouteFeatureCollection {
  return {
    type: 'FeatureCollection',
    features,
  };
}
