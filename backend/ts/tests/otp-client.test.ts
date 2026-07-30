import { describe, test, expect } from 'bun:test';
import {
  buildOtpQuery,
  parseOtpResponse,
  type OtpItinerary,
} from '../src/services/otp-client.js';

describe('buildOtpQuery', () => {
  test('generates valid GraphQL query with coordinates', () => {
    const query = buildOtpQuery({
      srcLat: 42.36,
      srcLon: -71.06,
      dstLat: 42.35,
      dstLon: -71.08,
      departAt: '2026-03-18T08:00:00-04:00',
      numItineraries: 5,
    });
    expect(query).toContain('planConnection');
    expect(query).toContain('42.36');
    expect(query).toContain('-71.06');
    expect(query).toContain('SUBWAY');
  });
});

describe('parseOtpResponse', () => {
  test('extracts itineraries with legs from OTP response', () => {
    const mockResponse = {
      data: {
        planConnection: {
          edges: [
            {
              node: {
                startTime: '2026-03-18T08:00:00-04:00',
                endTime: '2026-03-18T08:42:00-04:00',
                duration: 2520,
                legs: [
                  {
                    mode: 'WALK',
                    from: { lat: 42.36, lon: -71.06, name: 'Origin', stop: null },
                    to: { lat: 42.356, lon: -71.062, name: 'Park Street', stop: { gtfsId: 'mbta:place-pktrm' } },
                    startTime: '2026-03-18T08:00:00-04:00',
                    endTime: '2026-03-18T08:07:00-04:00',
                    duration: 420,
                    distance: 350,
                    legGeometry: { points: 'encodedPolyline', length: 45 },
                    route: null,
                    intermediateStops: null,
                  },
                  {
                    mode: 'SUBWAY',
                    from: { lat: 42.356, lon: -71.062, name: 'Park Street', stop: { gtfsId: 'mbta:place-pktrm' } },
                    to: { lat: 42.373, lon: -71.119, name: 'Harvard', stop: { gtfsId: 'mbta:place-harvd' } },
                    startTime: '2026-03-18T08:10:00-04:00',
                    endTime: '2026-03-18T08:28:00-04:00',
                    duration: 1080,
                    distance: 5200,
                    legGeometry: { points: 'encodedPolyline2', length: 120 },
                    route: { shortName: 'Red', longName: 'Red Line', color: 'DA291C', agency: { name: 'MBTA' } },
                    intermediateStops: [
                      { name: 'Charles/MGH', lat: 42.361, lon: -71.071 },
                    ],
                  },
                  {
                    mode: 'WALK',
                    from: { lat: 42.373, lon: -71.119, name: 'Harvard', stop: { gtfsId: 'mbta:place-harvd' } },
                    to: { lat: 42.375, lon: -71.121, name: 'Destination', stop: null },
                    startTime: '2026-03-18T08:28:00-04:00',
                    endTime: '2026-03-18T08:35:00-04:00',
                    duration: 420,
                    distance: 350,
                    legGeometry: { points: 'encodedPolyline3', length: 25 },
                    route: null,
                    intermediateStops: null,
                  },
                ],
              },
            },
          ],
        },
      },
    };

    const itineraries = parseOtpResponse(mockResponse);
    expect(itineraries).toHaveLength(1);
    expect(itineraries[0].legs).toHaveLength(3);
    expect(itineraries[0].legs[0].mode).toBe('WALK');
    expect(itineraries[0].legs[1].mode).toBe('SUBWAY');
    expect(itineraries[0].legs[1].route?.shortName).toBe('Red');
    expect(itineraries[0].legs[2].mode).toBe('WALK');
    expect(itineraries[0].duration).toBe(2520);
  });

  test('returns empty array for no results', () => {
    const emptyResponse = {
      data: { planConnection: { edges: [] } },
    };
    expect(parseOtpResponse(emptyResponse)).toEqual([]);
  });
});
