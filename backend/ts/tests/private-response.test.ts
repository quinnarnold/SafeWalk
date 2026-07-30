import { describe, expect, it } from 'bun:test';
import Fastify from 'fastify';
import { PRIVATE_NO_STORE, setPrivateNoStore } from '../src/utils/private-response.js';
import { watchRoutes } from '../src/routes/watch.js';
import { watchPageHtml } from '../src/routes/watch-page.js';

describe('private response handling', () => {
  it('sets the shared no-store policy', () => {
    let value: string | undefined;
    const reply = {
      header(name: string, headerValue: string) {
        if (name === 'Cache-Control') value = headerValue;
        return this;
      },
    };

    setPrivateNoStore(reply as never);

    expect(value).toBe(PRIVATE_NO_STORE);
  });

  it('sets no-store even when a bearer watch URL has expired', async () => {
    const app = Fastify();
    await app.register(watchRoutes);

    const response = await app.inject({
      method: 'GET',
      url: `/watch/${'a'.repeat(22)}`,
    });

    expect(response.statusCode).toBe(404);
    expect(response.headers['cache-control']).toBe(PRIVATE_NO_STORE);
    expect(response.headers['referrer-policy']).toBe('no-referrer');
    await app.close();
  });

  it('requests watcher data without browser caching or credentials', () => {
    const html = watchPageHtml('a'.repeat(22));
    expect(html).toContain("cache: 'no-store'");
    expect(html).toContain("credentials: 'omit'");
  });
});
