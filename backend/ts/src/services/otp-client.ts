import { config } from '../config.js';

export interface OtpQueryParams {
  srcLat: number;
  srcLon: number;
  dstLat: number;
  dstLon: number;
  departAt: string;
  numItineraries?: number;
}

export interface OtpStop {
  name: string;
  lat: number;
  lon: number;
}

export interface OtpRoute {
  shortName: string;
  longName: string;
  color: string;
  agency: { name: string };
}

export interface OtpLeg {
  mode: string;
  from: { lat: number; lon: number; name: string; stop: { gtfsId: string } | null };
  to: { lat: number; lon: number; name: string; stop: { gtfsId: string } | null };
  startTime: string;
  endTime: string;
  duration: number;
  distance: number;
  legGeometry: { points: string; length: number };
  route: OtpRoute | null;
  intermediateStops: OtpStop[] | null;
}

export interface OtpItinerary {
  startTime: string;
  endTime: string;
  duration: number;
  legs: OtpLeg[];
}

export function buildOtpQuery(params: OtpQueryParams): string {
  const numItineraries = params.numItineraries ?? 10;
  return `{
  planConnection(
    origin: { location: { coordinate: { latitude: ${params.srcLat}, longitude: ${params.srcLon} } } }
    destination: { location: { coordinate: { latitude: ${params.dstLat}, longitude: ${params.dstLon} } } }
    dateTime: { earliestDeparture: "${params.departAt}" }
    first: ${numItineraries}
    modes: {
      transit: { transit: [{ mode: BUS }, { mode: RAIL }, { mode: SUBWAY }, { mode: TRAM }, { mode: FERRY }] }
    }
  ) {
    edges {
      node {
        startTime
        endTime
        duration
        legs {
          mode
          from { lat lon name stop { gtfsId } }
          to { lat lon name stop { gtfsId } }
          startTime
          endTime
          duration
          distance
          legGeometry { points length }
          route { shortName longName color agency { name } }
          intermediateStops { name lat lon }
        }
      }
    }
  }
}`;
}

export function parseOtpResponse(response: unknown): OtpItinerary[] {
  const data = response as {
    data: {
      planConnection: {
        edges: Array<{ node: OtpItinerary }>;
      };
    };
  };

  const edges = data?.data?.planConnection?.edges;
  if (!Array.isArray(edges)) {
    return [];
  }

  return edges.map((edge) => edge.node);
}

export async function queryOtp(params: OtpQueryParams): Promise<OtpItinerary[]> {
  const query = buildOtpQuery(params);

  const response = await fetch(`${config.otpUrl}/otp/routers/default/index/graphql`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
    signal: AbortSignal.timeout(15000),
  });

  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`OTP2 query returned status ${response.status}`);
  }

  const json = await response.json();
  return parseOtpResponse(json);
}

export async function checkOtpHealth(): Promise<boolean> {
  try {
    const response = await fetch(`${config.otpUrl}/otp/actuators/health`, {
      method: 'GET',
      signal: AbortSignal.timeout(5000),
    });
    return response.ok;
  } catch {
    return false;
  }
}
