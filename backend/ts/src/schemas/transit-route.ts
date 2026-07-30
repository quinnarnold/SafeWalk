import { z } from 'zod';
import { VALID_CITIES } from './route.js';

export const TransitRouteParamsSchema = z.object({
  city: z.enum(VALID_CITIES, {
    errorMap: () => ({ message: `Invalid city. Supported: ${VALID_CITIES.join(', ')}` }),
  }),
});

export type TransitRouteParams = z.infer<typeof TransitRouteParamsSchema>;

export const TransitRouteQuerySchema = z.object({
  src_lat: z.coerce.number().min(-90).max(90),
  src_lon: z.coerce.number().min(-180).max(180),
  dst_lat: z.coerce.number().min(-90).max(90),
  dst_lon: z.coerce.number().min(-180).max(180),
  bin: z.coerce.number().int().min(0).max(3).default(2),
  depart_at: z.string().optional(),
  speed_mps: z.coerce.number().positive().default(1.4),
});

export type TransitRouteQuery = z.infer<typeof TransitRouteQuerySchema>;

const LegLocationSchema = z.object({
  lat: z.number(),
  lon: z.number(),
  name: z.string(),
  stopId: z.string().optional(),
});

const TransitRouteInfoSchema = z.object({
  shortName: z.string(),
  longName: z.string(),
  color: z.string(),
  agency: z.string(),
});

const IntermediateStopSchema = z.object({
  name: z.string(),
  lat: z.number(),
  lon: z.number(),
});

const LineStringSchema = z.object({
  type: z.literal('LineString'),
  coordinates: z.array(z.array(z.number())),
});

export const TransitLegSchema = z.object({
  mode: z.string(),
  from: LegLocationSchema,
  to: LegLocationSchema,
  startTime: z.string(),
  endTime: z.string(),
  duration: z.number(),
  distance_m: z.number(),
  geometry: LineStringSchema,
  route: TransitRouteInfoSchema.optional(),
  intermediateStops: z.array(IntermediateStopSchema).optional(),
  pred_risk: z.number().optional(),
  safety_type: z.enum(['shortest', 'moderate', 'safest']).optional(),
});

export type TransitLeg = z.infer<typeof TransitLegSchema>;

export const TransitItinerarySchema = z.object({
  startTime: z.string(),
  endTime: z.string(),
  duration: z.number(),
  legs: z.array(TransitLegSchema),
  totalWalkDistance_m: z.number(),
  totalWalkRisk: z.number().optional(),
});

export type TransitItinerary = z.infer<typeof TransitItinerarySchema>;

export const TransitRouteResponseSchema = z.object({
  itineraries: z.array(TransitItinerarySchema),
});

export type TransitRouteResponse = z.infer<typeof TransitRouteResponseSchema>;
