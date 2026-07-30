/**
 * Zod validation schemas for route endpoints.
 */
import { z } from 'zod';

/**
 * Allowed city names - prevents path traversal and invalid city loading.
 */
export const VALID_CITIES = ['atlanta', 'boston', 'chicago', 'newyork', 'philadelphia', 'seattle'] as const;
export type ValidCity = typeof VALID_CITIES[number];

/**
 * Query parameters for the route endpoint.
 */
export const RouteQuerySchema = z.object({
  src_lat: z.coerce.number().min(-90).max(90),
  src_lon: z.coerce.number().min(-180).max(180),
  dst_lat: z.coerce.number().min(-90).max(90),
  dst_lon: z.coerce.number().min(-180).max(180),
  bin: z.coerce.number().int().min(0).max(3).default(2),
  speed_mps: z.coerce.number().positive().default(1.4),
});

export type RouteQuery = z.infer<typeof RouteQuerySchema>;

/**
 * Route parameters (city name).
 * Validates against allowed cities to prevent path traversal attacks.
 */
export const RouteParamsSchema = z.object({
  city: z.enum(VALID_CITIES, {
    errorMap: () => ({ message: `Invalid city. Supported: ${VALID_CITIES.join(', ')}` }),
  }),
});

export type RouteParams = z.infer<typeof RouteParamsSchema>;

/**
 * Schema for a single route from Python compute layer.
 */
const RouteInfoSchema = z.object({
  distance_m: z.number(),
  time_s: z.number(),
  pred_risk: z.number(),
  raw_coords: z.array(z.array(z.number())),
});

/**
 * Response from Python compute layer.
 * - shortest: Always present
 * - moderate: Only present if it reduces risk vs shortest
 * - safest: Only present if it reduces risk vs shortest
 */
export const PythonRouteResponseSchema = z.object({
  shortest: RouteInfoSchema,
  moderate: RouteInfoSchema.nullable(),
  safest: RouteInfoSchema.nullable(),
});

export type PythonRouteResponse = z.infer<typeof PythonRouteResponseSchema>;
