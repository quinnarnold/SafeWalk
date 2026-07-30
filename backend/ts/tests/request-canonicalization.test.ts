import { describe, expect, test } from 'bun:test';
import {
  canonicalQuery,
  canonicalRequestData,
  stableJson,
} from '../src/utils/request-canonicalization.js';

describe('request canonicalization', () => {
  test('sorts and RFC 3986 encodes query parameters', () => {
    expect(canonicalQuery('/route?z=two+words&a=!')).toBe('a=%21&z=two%20words');
  });

  test('sorts nested JSON object keys', () => {
    expect(stableJson({ z: 1, a: { y: true, b: null } }))
      .toBe('{"a":{"b":null,"y":true},"z":1}');
  });

  test('binds method, path, query, and body', () => {
    const canonical = canonicalRequestData('123', 'post', '/share?b=2&a=1', { z: 1 });
    expect(canonical.split('\n').slice(0, 4)).toEqual([
      '123',
      'POST',
      '/share',
      'a=1&b=2',
    ]);
    expect(canonical.split('\n')[4]).toMatch(/^[a-f0-9]{64}$/);
  });
});
