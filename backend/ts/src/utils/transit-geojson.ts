import type { TransitItinerary, TransitLeg } from '../schemas/transit-route.js';

export type EnhancedLeg = TransitLeg;

export function decodeOtpPolyline(encoded: string): number[][] {
  const coords: number[][] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < encoded.length) {
    let shift = 0;
    let result = 0;
    let byte: number;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lat += result & 1 ? ~(result >> 1) : result >> 1;

    shift = 0;
    result = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lng += result & 1 ? ~(result >> 1) : result >> 1;

    coords.push([lng / 1e5, lat / 1e5]);
  }

  return coords;
}

export function buildTransitItinerary(
  legs: EnhancedLeg[],
  startTime: string,
  endTime: string,
  duration: number,
): TransitItinerary {
  let totalWalkDistance = 0;
  let totalWalkRisk = 0;

  for (const leg of legs) {
    if (leg.mode === 'WALK') {
      totalWalkDistance += leg.distance_m;
      if (leg.pred_risk !== undefined) {
        totalWalkRisk += leg.pred_risk;
      }
    }
  }

  return {
    startTime,
    endTime,
    duration,
    legs,
    totalWalkDistance_m: totalWalkDistance,
    totalWalkRisk: totalWalkRisk || undefined,
  };
}
