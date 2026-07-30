import { afterEach, describe, expect, it } from 'bun:test';
import { config } from '../src/config.js';
import { computeRoute } from '../src/services/python-client.js';
import { mapboxMatch } from '../src/services/mapbox.js';
import { queryOtp } from '../src/services/otp-client.js';
import { subscribe } from '../src/services/redis-pubsub.js';

const originalFetch = globalThis.fetch;
const originalMapboxToken = config.mapboxToken;
const originalWarn = console.warn;
const originalError = console.error;

afterEach(() => {
  globalThis.fetch = originalFetch;
  (config as { mapboxToken: string }).mapboxToken = originalMapboxToken;
  console.warn = originalWarn;
  console.error = originalError;
});

describe('upstream error redaction', () => {
  const sentinel = '42.654321,-71.123456 bearer-capability-secret';

  it('does not propagate a Python response body', async () => {
    globalThis.fetch = async () => new Response(sentinel, { status: 502 });

    let message = '';
    try {
      await computeRoute({
        city: 'boston',
        srcLat: 42.654321,
        srcLon: -71.123456,
        dstLat: 42.35,
        dstLon: -71.04,
        bin: 2,
        speedMps: 1.4,
      });
    } catch (error) {
      message = error instanceof Error ? error.message : String(error);
    }

    expect(message).toBe('Python compute layer returned status 502');
    expect(message).not.toContain(sentinel);
  });

  it('does not propagate an OTP response body that echoes its query', async () => {
    globalThis.fetch = async () => new Response(sentinel, { status: 503 });

    let message = '';
    try {
      await queryOtp({
        srcLat: 42.654321,
        srcLon: -71.123456,
        dstLat: 42.35,
        dstLon: -71.04,
        departAt: '2026-07-30T09:00:00-04:00',
      });
    } catch (error) {
      message = error instanceof Error ? error.message : String(error);
    }

    expect(message).toBe('OTP2 query returned status 503');
    expect(message).not.toContain(sentinel);
  });

  it('does not log Mapbox response bodies, request URLs, or thrown text', async () => {
    const logArguments: unknown[][] = [];
    console.warn = (...args: unknown[]) => logArguments.push(args);
    console.error = (...args: unknown[]) => logArguments.push(args);
    (config as { mapboxToken: string }).mapboxToken = 'bearer-capability-secret';

    globalThis.fetch = async () => new Response(sentinel, { status: 429 });
    await mapboxMatch([[-71.123456, 42.654321], [-71.12, 42.65]]);

    globalThis.fetch = async () => {
      throw new Error(sentinel);
    };
    await mapboxMatch([[-71.123456, 42.654321], [-71.11, 42.64]]);

    const observable = JSON.stringify(logArguments);
    expect(observable).toContain('Map-matching');
    expect(observable).not.toContain('42.654321');
    expect(observable).not.toContain('-71.123456');
    expect(observable).not.toContain('bearer-capability-secret');
  });

  it('keeps raw Swift SDK and network errors out of client logging boundaries', async () => {
    const apiSource = await Bun.file(
      new URL('../../../frontend/SafeWalk/ApiService.swift', import.meta.url),
    ).text();
    const routeViewModelSource = await Bun.file(
      new URL('../../../frontend/SafeWalk/ViewModels/RouteViewModel.swift', import.meta.url),
    ).text();
    const transitSource = await Bun.file(
      new URL('../../../frontend/SafeWalk/TransitNavigationManager.swift', import.meta.url),
    ).text();

    expect(apiSource).not.toContain('case networkError(Error)');
    expect(apiSource).not.toContain('case decodingError(Error)');
    expect(routeViewModelSource).not.toContain('print("MapKit lookup error: \\(error)")');
    expect(routeViewModelSource).not.toContain(
      'print("Share My Walk: startShareSession failed: \\(error)")',
    );
    expect(routeViewModelSource).not.toContain(
      'msg = "Unable to start navigation: \\(error.localizedDescription)"',
    );
    expect(transitSource).not.toContain(
      'self.error = "Unable to start navigation: \\(error.localizedDescription)"',
    );
  });

  it('does not propagate a Redis subscription channel capability', async () => {
    const client = {
      subscribe: () => Promise.reject(new Error(sentinel)),
    };

    let message = '';
    try {
      await subscribe(client as never, `share:${sentinel}`);
    } catch (error) {
      message = error instanceof Error ? error.message : String(error);
    }

    expect(message).toBe('Storage operation failed');
    expect(message).not.toContain(sentinel);
  });
});
