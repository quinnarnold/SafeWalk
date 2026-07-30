import { computeRoute } from './python-client.js';
import { mapboxMatch } from './mapbox.js';
import { queryOtp, type OtpItinerary, type OtpLeg } from './otp-client.js';
import { decodeOtpPolyline, buildTransitItinerary } from '../utils/transit-geojson.js';
import type { TransitLeg, TransitItinerary } from '../schemas/transit-route.js';
import { cacheKey } from '../utils/cache-key.js';

export function transitCacheKey(
  city: string, srcLat: number, srcLon: number,
  dstLat: number, dstLon: number, bin: number, speedMps: number, departAt?: string,
): string {
  return cacheKey(
    'transit',
    city,
    srcLat.toFixed(4),
    srcLon.toFixed(4),
    dstLat.toFixed(4),
    dstLon.toFixed(4),
    bin,
    speedMps.toFixed(3),
    departAt ?? 'now',
  );
}

export function currentTimeIso(): string {
  return new Date().toISOString();
}

export function otpLegToTransitLeg(leg: OtpLeg): TransitLeg {
  const coordinates = decodeOtpPolyline(leg.legGeometry.points);
  return {
    mode: leg.mode,
    from: {
      lat: leg.from.lat,
      lon: leg.from.lon,
      name: leg.from.name,
      stopId: leg.from.stop?.gtfsId,
    },
    to: {
      lat: leg.to.lat,
      lon: leg.to.lon,
      name: leg.to.name,
      stopId: leg.to.stop?.gtfsId,
    },
    startTime: leg.startTime,
    endTime: leg.endTime,
    duration: leg.duration,
    distance_m: leg.distance,
    geometry: { type: 'LineString', coordinates },
    route: leg.route
      ? {
          shortName: leg.route.shortName,
          longName: leg.route.longName,
          color: leg.route.color,
          agency: leg.route.agency.name,
        }
      : undefined,
    intermediateStops: leg.intermediateStops ?? undefined,
  };
}

async function enhanceWalkLeg(
  leg: TransitLeg,
  city: string,
  bin: number,
  speedMps: number,
): Promise<TransitLeg> {
  try {
    const routeData = await computeRoute({
      city,
      srcLat: leg.from.lat,
      srcLon: leg.from.lon,
      dstLat: leg.to.lat,
      dstLon: leg.to.lon,
      bin,
      speedMps,
    });

    const safeRoute = routeData.moderate ?? routeData.shortest;
    const safetyType = routeData.moderate ? 'moderate' : 'shortest';
    let coordinates = safeRoute.raw_coords;

    const matched = await mapboxMatch(coordinates);
    if (matched) {
      coordinates = matched;
    }

    return {
      ...leg,
      distance_m: safeRoute.distance_m,
      duration: safeRoute.time_s,
      geometry: { type: 'LineString', coordinates },
      pred_risk: safeRoute.pred_risk,
      safety_type: safetyType,
    };
  } catch {
    return leg;
  }
}

export async function processItinerary(
  otpItinerary: OtpItinerary,
  city: string,
  bin: number,
  speedMps: number,
): Promise<TransitItinerary> {
  const legs: TransitLeg[] = [];

  for (const otpLeg of otpItinerary.legs) {
    const transitLeg = otpLegToTransitLeg(otpLeg);

    if (otpLeg.mode === 'WALK' && transitLeg.distance_m > 50) {
      const enhanced = await enhanceWalkLeg(transitLeg, city, bin, speedMps);
      legs.push(enhanced);
    } else {
      legs.push(transitLeg);
    }
  }

  return buildTransitItinerary(
    legs,
    otpItinerary.startTime,
    otpItinerary.endTime,
    otpItinerary.duration,
  );
}

export async function getTransitItineraries(
  srcLat: number, srcLon: number,
  dstLat: number, dstLon: number,
  departAt: string, city: string,
  bin: number, speedMps: number,
): Promise<TransitItinerary[]> {
  const otpItineraries = await queryOtp({
    srcLat, srcLon, dstLat, dstLon,
    departAt,
    numItineraries: 10,
  });

  if (otpItineraries.length === 0) return [];

  const topItineraries = otpItineraries.slice(0, 5);
  return Promise.all(
    topItineraries.map((it) => processItinerary(it, city, bin, speedMps)),
  );
}
