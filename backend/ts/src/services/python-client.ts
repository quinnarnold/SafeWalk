import { config } from '../config.js';
import { PythonRouteResponse, PythonRouteResponseSchema } from '../schemas/route.js';

export interface ComputeRouteParams {
  city: string;
  srcLat: number;
  srcLon: number;
  dstLat: number;
  dstLon: number;
  bin: number;
  speedMps: number;
}

export async function computeRoute(params: ComputeRouteParams): Promise<PythonRouteResponse> {
  const url = `${config.pythonUrl}/compute-route`;

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    signal: AbortSignal.timeout(30000),
    body: JSON.stringify({
      city: params.city,
      src_lat: params.srcLat,
      src_lon: params.srcLon,
      dst_lat: params.dstLat,
      dst_lon: params.dstLon,
      bin: params.bin,
      speed_mps: params.speedMps,
    }),
  });

  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`Python compute layer returned status ${response.status}`);
  }

  const data = await response.json();

  const parsed = PythonRouteResponseSchema.safeParse(data);
  if (!parsed.success) {
    throw new Error('Python compute layer returned an invalid response');
  }

  return parsed.data;
}

export async function checkPythonHealth(): Promise<boolean> {
  const url = `${config.pythonUrl}/health`;

  try {
    const response = await fetch(url, {
      method: 'GET',
      signal: AbortSignal.timeout(5000),
    });
    return response.ok;
  } catch {
    return false;
  }
}
