import { z } from 'zod';

const shareCapability = z.string().length(43).regex(/^[A-Za-z0-9_-]+$/);

export const ShareStartSchema = z.object({
  routeGeoJSON: z.object({
    type: z.literal('FeatureCollection'),
    features: z.array(z.object({
      type: z.literal('Feature'),
      geometry: z.object({
        type: z.string(),
        coordinates: z.array(z.any()),
      }),
      properties: z.record(z.unknown()).nullable(),
    })),
  }),
  destinationName: z.string().min(1).max(100).regex(/^[\w\s.,'\-&#/()[\]!@:;+]+$/u),
});
export type ShareStartRequest = z.infer<typeof ShareStartSchema>;

export const ShareLocationSchema = z.object({
  sessionId: z.string().length(22).regex(/^[A-Za-z0-9_-]+$/),
  writerToken: shareCapability,
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
});
export type ShareLocationRequest = z.infer<typeof ShareLocationSchema>;

export const ShareStopSchema = z.object({
  sessionId: z.string().length(22).regex(/^[A-Za-z0-9_-]+$/),
  writerToken: shareCapability,
  reason: z.enum(['arrived', 'canceled']),
});
export type ShareStopRequest = z.infer<typeof ShareStopSchema>;

export const ShareSessionParamsSchema = z.object({
  sessionId: z.string().length(22).regex(/^[A-Za-z0-9_-]+$/),
});
export type ShareSessionParams = z.infer<typeof ShareSessionParamsSchema>;
