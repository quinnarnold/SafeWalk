import { describe, test, expect } from 'bun:test';
import {
  decodeOtpPolyline,
  buildTransitItinerary,
  type EnhancedLeg,
} from '../src/utils/transit-geojson.js';

describe('decodeOtpPolyline', () => {
  test('decodes a simple encoded polyline to [lon, lat] coordinates', () => {
    const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
    const coords = decodeOtpPolyline(encoded);
    expect(coords.length).toBeGreaterThan(0);
    expect(coords[0].length).toBe(2);
  });
});

describe('buildTransitItinerary', () => {
  test('converts OTP legs + SafeWalk walk legs into transit itinerary', () => {
    const legs: EnhancedLeg[] = [
      {
        mode: 'WALK',
        from: { lat: 42.36, lon: -71.06, name: 'Origin', stopId: undefined },
        to: { lat: 42.356, lon: -71.062, name: 'Park Street', stopId: 'mbta:place-pktrm' },
        startTime: '2026-03-18T08:00:00-04:00',
        endTime: '2026-03-18T08:07:00-04:00',
        duration: 420,
        distance_m: 350,
        geometry: { type: 'LineString' as const, coordinates: [[-71.06, 42.36], [-71.062, 42.356]] },
        pred_risk: 0.023,
        safety_type: 'moderate',
      },
      {
        mode: 'SUBWAY',
        from: { lat: 42.356, lon: -71.062, name: 'Park Street', stopId: 'mbta:place-pktrm' },
        to: { lat: 42.373, lon: -71.119, name: 'Harvard', stopId: 'mbta:place-harvd' },
        startTime: '2026-03-18T08:10:00-04:00',
        endTime: '2026-03-18T08:28:00-04:00',
        duration: 1080,
        distance_m: 5200,
        geometry: { type: 'LineString' as const, coordinates: [[-71.062, 42.356], [-71.119, 42.373]] },
        route: { shortName: 'Red', longName: 'Red Line', color: 'DA291C', agency: 'MBTA' },
        intermediateStops: [{ name: 'Charles/MGH', lat: 42.361, lon: -71.071 }],
      },
      {
        mode: 'WALK',
        from: { lat: 42.373, lon: -71.119, name: 'Harvard', stopId: 'mbta:place-harvd' },
        to: { lat: 42.375, lon: -71.121, name: 'Destination', stopId: undefined },
        startTime: '2026-03-18T08:28:00-04:00',
        endTime: '2026-03-18T08:35:00-04:00',
        duration: 420,
        distance_m: 200,
        geometry: { type: 'LineString' as const, coordinates: [[-71.119, 42.373], [-71.121, 42.375]] },
        pred_risk: 0.015,
        safety_type: 'safest',
      },
    ];

    const itinerary = buildTransitItinerary(legs, '2026-03-18T08:00:00-04:00', '2026-03-18T08:35:00-04:00', 2100);
    expect(itinerary.legs).toHaveLength(3);
    expect(itinerary.totalWalkDistance_m).toBe(550);
    expect(itinerary.totalWalkRisk).toBeCloseTo(0.038);
    expect(itinerary.duration).toBe(2100);
  });
});
